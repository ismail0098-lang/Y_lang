// ============================================================
//  Y-Lang  —  PTX Code Emitter
//  ptx_emitter.rs
//
//  Backend code generator targeting NVIDIA PTX.
//  Converts validated AST nodes into virtual assembly.
//  Bypasses high-level CUDA runtime and talks directly 
//  to the silicon via instructions like ldmatrix and cp.async.
// ============================================================

#![allow(dead_code)]

use std::fmt::Write;
use crate::ast::*;

/// Manages virtual registers and produces raw PTX strings.
pub struct PtxEmitter {
    pub ptx_buffer: String,
    
    // Virtual register counters to maintain uniqueness
    reg_u32_count: u32,
    reg_f32_count: u32,
    reg_pred_count: u32,
}

impl PtxEmitter {
    pub fn new() -> Self {
        let mut buffer = String::new();
        // Emit PTX header
        writeln!(&mut buffer, ".version 8.0").unwrap();
        // Assume sm_80 or sm_89 depending on feature set needed (sm_80 for cp.async).
        writeln!(&mut buffer, ".target sm_80").unwrap();
        writeln!(&mut buffer, ".address_size 64").unwrap();
        writeln!(&mut buffer, "").unwrap();

        Self {
            ptx_buffer: buffer,
            reg_u32_count: 0,
            reg_f32_count: 0,
            reg_pred_count: 0,
        }
    }

    /// Allocates a new virtual 32-bit register (e.g. `%r5`)
    fn alloc_reg32(&mut self) -> String {
        let name = format!("%r{}", self.reg_u32_count);
        self.reg_u32_count += 1;
        name
    }

    /// Allocates a new virtual float register (e.g. `%f2`)
    fn alloc_regf32(&mut self) -> String {
        let name = format!("%f{}", self.reg_f32_count);
        self.reg_f32_count += 1;
        name
    }

    pub fn emit_program(&mut self, prog: &Program) -> String {
        for item in &prog.items {
            if let Item::Kernel(k) = item {
                self.emit_kernel(k);
            }
        }
        self.ptx_buffer.clone()
    }

    fn emit_kernel(&mut self, kernel: &KernelDecl) {
        // Emit kernel signature
        writeln!(&mut self.ptx_buffer, ".visible .entry {}(", kernel.name).unwrap();
        
        let param_count = kernel.params.len();
        for (i, param) in kernel.params.iter().enumerate() {
            // E.g. GlobalMemory translates to 64-bit pointers
            let ptx_type = match &param.ty {
                Type::Generic { base, .. } if base == "GlobalMemory" => ".param .u64",
                _ => ".param .b32" // fallback payload
            };
            
            write!(&mut self.ptx_buffer, "    {} {}_{}", ptx_type, param.name, i).unwrap();
            if i < param_count - 1 {
                writeln!(&mut self.ptx_buffer, ",").unwrap();
            } else {
                writeln!(&mut self.ptx_buffer).unwrap();
            }
        }
        writeln!(&mut self.ptx_buffer, ") {{").unwrap();
        
        // Declare virtual registers at the top of the kernel block
        // (For simplicity in this prototype, we'll declare a batch of virtual registers)
        writeln!(&mut self.ptx_buffer, "    .reg .b32 %r<100>;").unwrap();
        writeln!(&mut self.ptx_buffer, "    .reg .f32 %f<100>;").unwrap();
        writeln!(&mut self.ptx_buffer, "    .reg .b64 %rd<50>;").unwrap();
        writeln!(&mut self.ptx_buffer, "    .reg .pred %p<20>;").unwrap();
        writeln!(&mut self.ptx_buffer).unwrap();

        // Emit body
        self.emit_block(&kernel.body);

        writeln!(&mut self.ptx_buffer, "}}").unwrap();
    }

    fn emit_block(&mut self, block: &Block) {
        for stmt in &block.stmts {
            self.emit_stmt(stmt);
        }
    }

    fn emit_stmt(&mut self, stmt: &Stmt) {
        match stmt {
            Stmt::Let { name, init, cache_policy, .. } => {
                if let Some(expr) = init {
                    // Check if it's an allocation or instruction
                    let val_str = self.emit_expr(expr, cache_policy.as_ref());
                    writeln!(&mut self.ptx_buffer, "    // let {} = ...", name).unwrap();
                    if !val_str.is_empty() {
                         writeln!(&mut self.ptx_buffer, "    {}", val_str).unwrap();
                    }
                }
            }
            Stmt::TypeAlias { name, .. } => {
                writeln!(&mut self.ptx_buffer, "    // type {} defined", name).unwrap();
            }
            Stmt::For { loop_var, start, end, body, .. } => {
                writeln!(&mut self.ptx_buffer, "    // for {} in ...", loop_var).unwrap();
                writeln!(&mut self.ptx_buffer, "    $LOOP_START_{}:", loop_var).unwrap();
                self.emit_block(body);
                // Pseudo-branch logic
                writeln!(&mut self.ptx_buffer, "    // increment and branch back").unwrap();
                writeln!(&mut self.ptx_buffer, "    bra $LOOP_START_{};", loop_var).unwrap();
            }
            Stmt::Assign { target, value, .. } => {
                writeln!(&mut self.ptx_buffer, "    // ASSIGN LOGIC").unwrap();
                let dst = self.emit_expr(target, None);
                let src = self.emit_expr(value, None);
                // Actual move logic relies on what 'target' is, but for demonstration:
                if !src.is_empty() {
                    writeln!(&mut self.ptx_buffer, "    {}", src).unwrap();
                }
            }
            Stmt::Expr(expr) => {
                let call_str = self.emit_expr(expr, None);
                if !call_str.is_empty() {
                    writeln!(&mut self.ptx_buffer, "    {}", call_str).unwrap();
                }
            }
            Stmt::Return(_, _) => {}
            _ => {} // Chisel blocks and new constructs
        }
    }

    fn emit_expr(&mut self, expr: &Expr, cache_policy: Option<&CachePolicyAttr>) -> String {
        match expr {
            Expr::Call { func, args, .. } => {
                if let Expr::Ident(fname, _) = &**func {
                    if fname == "cp_async" {
                        // Assuming args are (src_ptr, dst_smem)
                        // Emits hardware async copy 
                        return "cp.async.ca.shared.global [%rd_smem], [%rd_gmem], 16;".into();
                    } else if fname == "mma_sync" {
                        return "mma.sync.aligned.m16n8k16.row.col.f32.f16.f16.f32 {%f0,%f1}, {%r0,%r1}, {%r2,%r3}, {%f0,%f1};".into();
                    } else if fname == "store" {
                        return "st.global.v4.f32 [%rd_out], {%f0,%f1,%f2,%f3};".into();
                    }
                }
                "".into()
            }
            Expr::MemberAccess { base, member, .. } => {
                if member == "wait" {
                    // Pipeline block wait
                    return "cp.async.wait_group 0;".into();
                }
                "".into()
            }
            Expr::Path { namespace, member, .. } => {
                if namespace == "barrier" && member == "sync" {
                    return "bar.sync 0;".into();
                }
                if namespace == "Fragment" && member == "zero" {
                    return "mov.b32 %f0, 0f00000000;".into(); // Float zero synthesis
                }
                // Memory loads handling Cache policy
                if namespace == "GlobalMemory" && member == "load" {
                     let mut cache_str = ".ca"; 
                     if let Some(cp) = cache_policy {
                         if cp.policy == "L2_PERSIST" {
                             cache_str = ".lu"; // closest logical equivalent or custom PTX 8.0 hints
                         } else if cp.policy == "L2_EVICT_FIRST" {
                             cache_str = ".L2::evict_first"; // Requires newer PTX versions
                         }
                     }
                     return format!("ld.global{} [%rd_ptr];", cache_str);
                }

                if namespace == "SharedMemory" && member == "alloc" {
                    return ".shared .align 128 .b8 smem[8192];".into(); // Prototype SMEM block
                }
                "".into()
            }
            Expr::GenericCall { func, .. } => {
                // Same logic handles like a Path or Call
                 self.emit_expr(&**func, cache_policy)
            }
            _ => "".into()
        }
    }
}
