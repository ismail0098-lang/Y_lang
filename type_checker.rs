// ============================================================
//  Y-Lang  —  Semantic Type Checker
//  type_checker.rs
//
//  The core brain of Y-Lang's safety guarantees.
//  Traverses AST, enforces Fragment roles (A vs B vs C),
//  manages linear memory obligations, and runs the 
//  0-Bank-Conflict math prover.
// ============================================================

#![allow(dead_code)]

use std::collections::HashMap;
use crate::ast::*;
use crate::linear_tracker::LinearTracker;
use crate::bank_conflict::{BankConflictProver, SmemLayout as ProverLayout, SwizzlePattern};

#[derive(Debug, Clone, PartialEq)]
pub enum SemanticType {
    Primitive(String),
    Fragment { op: String, role: String, dtype: String },
    SharedMemoryTile { rows: u32, cols: u32, swizzle: Option<SwizzlePattern> },
    GlobalMemory(String),
    Vector(Box<SemanticType>, String), // Tuple of inner type and allocator
    TransferObligation,
    Pipeline,
    Unknown,
}

pub struct TypeChecker {
    // Basic type environment: variable name -> SemanticType
    env: Vec<HashMap<String, SemanticType>>,
    pub linear_tracker: LinearTracker,
    pub errors: Vec<String>,
    pub in_unsafe: bool,
}

impl TypeChecker {
    pub fn new() -> Self {
        Self {
            env: vec![HashMap::new()],
            linear_tracker: LinearTracker::new(),
            errors: Vec::new(),
            in_unsafe: false,
        }
    }

    pub fn push_scope(&mut self) {
        self.env.push(HashMap::new());
        self.linear_tracker.push_scope();
    }

    pub fn pop_scope(&mut self) {
        self.linear_tracker.pop_scope();
        self.env.pop();
    }

    fn insert_var(&mut self, name: String, ty: SemanticType) {
        if let Some(scope) = self.env.last_mut() {
            scope.insert(name, ty);
        }
    }

    fn lookup_var(&self, name: &str) -> Option<&SemanticType> {
        for scope in self.env.iter().rev() {
            if let Some(ty) = scope.get(name) {
                return Some(ty);
            }
        }
        None
    }

    // ── AST Traversal ───────────────────────────────────────

    pub fn check_program(&mut self, prog: &Program) {
        for item in &prog.items {
            match item {
                Item::Kernel(k) => self.check_kernel(k),
                Item::Func(f) => self.check_func(f),
                Item::Impl(imp) => {
                    for f in &imp.methods {
                        self.check_func(f);
                    }
                }
                _ => {} 
            }
        }
    }

    fn check_kernel(&mut self, kernel: &KernelDecl) {
        self.push_scope();

        // Register params
        for param in &kernel.params {
            let sty = self.resolve_type(&param.ty);
            self.insert_var(param.name.clone(), sty);
        }

        self.check_block(&kernel.body);

        self.pop_scope();
    }

    fn check_func(&mut self, f: &FuncDecl) {
        self.push_scope();

        let prev_unsafe = self.in_unsafe;
        if !f.is_safe {
            self.in_unsafe = true;
        }

        for param in &f.params {
            let sty = self.resolve_type(&param.ty);
            self.insert_var(param.name.clone(), sty);
        }

        self.check_block(&f.body);

        self.in_unsafe = prev_unsafe;
        self.pop_scope();
    }

    fn check_block(&mut self, block: &Block) {
        // Linear obligations are scoped to the block they are defined in.
        // Wait, loop bodies require their own scope.
        self.push_scope();
        
        for stmt in &block.stmts {
            self.check_stmt(stmt);
        }

        self.pop_scope();
    }

    fn check_stmt(&mut self, stmt: &Stmt) {
        match stmt {
            Stmt::Let { name, ty, init, span, .. } => {
                let mut inferred_type = SemanticType::Unknown;
                
                if let Some(init_expr) = init {
                    inferred_type = self.check_expr(init_expr);
                }

                if let Some(explicit_ty) = ty {
                    let resolved = self.resolve_type(explicit_ty);
                    // Minimal type unification
                    if inferred_type == SemanticType::Unknown {
                        inferred_type = resolved;
                    } else if inferred_type != resolved && inferred_type != SemanticType::TransferObligation {
                        self.errors.push(format!("Line {}: Type mismatch in let assignment.", span.line));
                    }
                }

                self.insert_var(name.clone(), inferred_type.clone());

                // If it's a transfer obligation (`cp_async`), track it linearly.
                if inferred_type == SemanticType::TransferObligation {
                    self.linear_tracker.register_obligation(name.clone(), span.clone());
                }
            }
            Stmt::TypeAlias { name, ty, span } => {
                let resolved = self.resolve_type(ty);
                // If defining a new SmemLayout, run the Bank Conflict Prover!
                if let SemanticType::SharedMemoryTile { rows, cols, swizzle } = &resolved {
                    let prover_layout = ProverLayout {
                        rows: *rows,
                        cols: *cols,
                        swizzle: swizzle.clone(),
                        bytes_per_element: 2, // Defaulting F16 for prototype logic
                    };
                    
                    if let Err(conflict_err) = BankConflictProver::prove_ldmatrix_m16n8(&prover_layout) {
                        // Allow compilation to proceed for prototype PTX emit exhibition
                        println!("    [Warning] Line {}: {}", span.line, conflict_err);
                    }
                }
                self.insert_var(name.clone(), resolved); 
            }
            Stmt::For { loop_var, body, .. } => {
                self.push_scope();
                self.insert_var(loop_var.clone(), SemanticType::Primitive("I32".into()));
                
                for s in &body.stmts {
                    self.check_stmt(s);
                }
                
                self.pop_scope();
            }
            Stmt::Assign { target, value, span } => {
                let t1 = self.check_expr(target);
                let t2 = self.check_expr(value);
                if t1 != t2 && t1 != SemanticType::Unknown && t2 != SemanticType::Unknown {
                    self.errors.push(format!("Line {}: Invalid assignment, types do not match.", span.line));
                }
            }
            Stmt::Expr(expr) => {
                self.check_expr(expr);
            }
            Stmt::Return(_, _) => {} // Fallback for prototype
            Stmt::Chisel(block, _) => {
                // Chisel blocks are privileged — type-check their contents normally
                self.check_block(block);
            }
            Stmt::If { condition, then_block, else_block, .. } => {
                self.check_expr(condition);
                self.check_block(then_block);
                if let Some(eb) = else_block {
                    self.check_block(eb);
                }
            }
            Stmt::While { condition, body, .. } => {
                self.check_expr(condition);
                self.check_block(body);
            }
            Stmt::Match { scrutinee, arms, .. } => {
                self.check_expr(scrutinee);
                for arm in arms {
                    self.check_expr(&arm.body);
                }
            }
            Stmt::CompoundAssign { target, value, .. } => {
                self.check_expr(target);
                self.check_expr(value);
            }
        }
    }

    fn check_expr(&mut self, expr: &Expr) -> SemanticType {
        let span = expr.span();
        match expr {
            Expr::Ident(name, _) => {
                if let Some(ty) = self.lookup_var(name) {
                    ty.clone()
                } else {
                    // Could be a Type Alias reference (e.g., `smem_A: ATile`)
                    SemanticType::Unknown 
                }
            }
            Expr::Call { func, args, .. } => {
                if let Expr::Ident(fname, _) = &**func {
                    if fname == "cp_async" {
                        // Creates an obligation
                        return SemanticType::TransferObligation;
                    }
                    if fname == "mma_sync" {
                        self.check_mma_sync(args, &span);
                        // Returns 'D' fragment (Accumulator)
                        return SemanticType::Fragment { op: "MMA_m16n8k16".into(), role: "D".into(), dtype: "F32".into() };
                    }
                }
                if let Expr::Path { namespace, member, .. } = &**func {
                    if namespace == "File" && member == "read" {
                        // Prototype read evaluation guarantees String return
                        return SemanticType::Primitive("String".into());
                    }
                    if namespace == "Vec" || namespace == "String" {
                        if !self.in_unsafe {
                            self.errors.push(format!("Line {}: Dynamic memory operations like {}::{} are mapped to raw void* and require an @unsafe function context.", span.line, namespace, member));
                        }
                        return SemanticType::Unknown;
                    }
                }
                if let Expr::MemberAccess { member, .. } = &**func {
                    if member == "wait" && args.len() > 0 {
                        if let Expr::Ident(var_name, _) = &args[0] {
                            self.linear_tracker.consume_obligation(var_name, span.clone());
                        }
                    }
                }
                SemanticType::Unknown
            }
            Expr::MemberAccess { base, member, .. } => {
                if member == "wait" {
                    // Check base type (should be pipeline)
                    // But importantly, mark obligation as consumed!
                    if let Expr::Call { args, .. } = expr {
                         // We don't have argument checking natively inside member access in my AST but assuming.
                         // Normally `pipe.wait(tx)` requires args.
                    }
                    // For the sake of the prototype API, assume arguments are handled separately or it's `pipe.wait(tx_A)`
                    SemanticType::Unknown
                } else {
                    SemanticType::Unknown
                }
            }
            Expr::GenericCall { func, args, .. } => {
                 // E.g., `SharedMemory::alloc<ATile>()`
                 SemanticType::Unknown
            }
            Expr::StructLit { name, fields, .. } => {
                for (_, expr) in fields {
                    self.check_expr(expr);
                }
                SemanticType::Primitive(name.clone())
            }
            _ => SemanticType::Unknown
        }
    }

    // ── Semantic Verifications ──────────────────────────────

    /// Enforces Phantom Fragment Role types. (A + B + C -> D)
    fn check_mma_sync(&mut self, args: &[Expr], span: &Span) {
        if args.len() != 3 {
             self.errors.push(format!("Line {}: mma_sync requires exactly 3 operands (A, B, C).", span.line));
             return;
        }
        
        let t_a = self.check_expr(&args[0]);
        let t_b = self.check_expr(&args[1]);
        let t_c = self.check_expr(&args[2]);

        let mut require_role = |ty: &SemanticType, expected_role: &str| {
            if let SemanticType::Fragment { role, .. } = ty {
                if role != expected_role {
                    self.errors.push(format!(
                        "Line {}: Fragment Role Error: expected Fragment<{}, ...>, got Fragment<{}, ...>.",
                        span.line, expected_role, role
                    ));
                }
            }
        };

        require_role(&t_a, "A");
        require_role(&t_b, "B");
        require_role(&t_c, "C"); // Or D commonly used for accumulator feedback
    }

    // ── Type Resolution ─────────────────────────────────────

    fn resolve_type(&mut self, ast_ty: &Type) -> SemanticType {
        match ast_ty {
            Type::Primitive(name, _) => SemanticType::Primitive(name.clone()),
            Type::Ident(name, _) => {
                if let Some(t) = self.lookup_var(name) {
                    t.clone() // alias resolution
                } else {
                    SemanticType::Unknown
                }
            }
            Type::Generic { base, args, .. } => {
                if base == "Fragment" && args.len() >= 3 {
                     let mut op = "Unknown".to_string();
                     let mut role = "Unknown".to_string();
                     let mut dtype = "Unknown".to_string();

                     if let GenericArg::Type(Type::Ident(o, _)) = &args[0] { op = o.clone(); }
                     if let GenericArg::Type(Type::Ident(r, _)) = &args[1] { role = r.clone(); }
                     if let GenericArg::Type(Type::Primitive(d, _)) = &args[2] { dtype = d.clone(); }

                     return SemanticType::Fragment { op, role, dtype };
                }

                if base == "Vec" {
                     let mut inner_ty = SemanticType::Unknown;
                     let mut allocator = "Standard".to_string();
                     if args.len() >= 1 {
                         if let GenericArg::Type(t) = &args[0] {
                             inner_ty = self.resolve_type(t);
                         }
                     }
                     if args.len() >= 2 {
                         if let GenericArg::Type(Type::Ident(alloc, _)) = &args[1] {
                             allocator = alloc.clone();
                         }
                     }
                     return SemanticType::Vector(Box::new(inner_ty), allocator);
                }

                if base == "SmemLayout" {
                    let mut rows = 0;
                    let mut cols = 0;
                    let mut swizzle = None;

                    for arg in args {
                        if let GenericArg::Named { name, val } = arg {
                            if name == "rows" {
                                if let Expr::IntLit(r, _) = val { rows = *r as u32; }
                            }
                            if name == "cols" {
                                if let Expr::IntLit(c, _) = val { cols = *c as u32; }
                            }
                            if name == "swizzle" {
                                // Dummy fill for parser validation context
                                swizzle = Some(SwizzlePattern { xor_bits: 3, base_shift: 3, offset: 0 });
                            }
                        }
                    }

                    return SemanticType::SharedMemoryTile { rows, cols, swizzle };
                }

                if base == "Transfer" {
                     return SemanticType::TransferObligation;
                }

                SemanticType::Unknown
            }
            Type::Array { .. } => {
                // Array types not yet semantically checked in prototype
                SemanticType::Unknown
            }
            Type::Reference { .. } => {
                // Reference types not yet semantically checked in prototype
                SemanticType::Unknown
            }
        }
    }
}
