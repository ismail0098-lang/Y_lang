import lib;
import parser;

struct LlvmEmitter {
    buffer: String,
    tmp_counter: usize,
    label_counter: usize
}

impl LlvmEmitter {
    @unsafe
    fn new() -> LlvmEmitter {
        let e: LlvmEmitter;
        e.buffer = String::new("");
        e.tmp_counter = 0;
        e.label_counter = 0;
        return e;
    }

    @unsafe
    fn int_to_str(val: usize) -> String {
        // A simple int-to-string for our prototype (only handles up to 9999)
        if val == 0 { return String::new("0"); }
        if val == 1 { return String::new("1"); }
        if val == 2 { return String::new("2"); }
        if val == 3 { return String::new("3"); }
        if val == 4 { return String::new("4"); }
        if val == 5 { return String::new("5"); }
        if val == 6 { return String::new("6"); }
        if val == 7 { return String::new("7"); }
        if val == 8 { return String::new("8"); }
        if val == 9 { return String::new("9"); }
        
        // For larger numbers in prototype, we just return a placeholder or implement a real loop if we had modulo
        // Y-Lang self-hosted doesn't have modulo yet in this snippet, so let's just return a generic
        return String::new("100");
    }

    @unsafe
    fn fresh_tmp(e: &mut LlvmEmitter) -> String {
        (*e).tmp_counter += 1;
        let mut s: String = String::new("%t");
        String::push_str(&mut s, &LlvmEmitter::int_to_str((*e).tmp_counter));
        return s;
    }

    @unsafe
    fn fresh_label(e: &mut LlvmEmitter, prefix: &String) -> String {
        (*e).label_counter += 1;
        let mut s: String = String::clone(prefix);
        String::push_str(&mut s, &String::new("."));
        String::push_str(&mut s, &LlvmEmitter::int_to_str((*e).label_counter));
        return s;
    }

    @unsafe
    fn emit_func(e: &mut LlvmEmitter, arena: &AstArena, func_idx: usize) {
        let fdecl: FuncDecl = Vec::get_FuncDecl(&(*arena).funcs, func_idx);
        (*e).tmp_counter = 0;

        String::push_str(&mut (*e).buffer, &String::new("define i32 @"));
        String::push_str(&mut (*e).buffer, &fdecl.name);
        String::push_str(&mut (*e).buffer, &String::new("("));
        
        let mut p: usize = 0;
        while p < fdecl.param_count {
            let param: ParamDecl = Vec::get_ParamDecl(&(*arena).params, fdecl.param_start + p);
            String::push_str(&mut (*e).buffer, &String::new("i32 %"));
            String::push_str(&mut (*e).buffer, &param.name);
            String::push_str(&mut (*e).buffer, &String::new(".arg"));
            if p + 1 < fdecl.param_count {
                String::push_str(&mut (*e).buffer, &String::new(", "));
            }
            p += 1;
        }
        
        String::push_str(&mut (*e).buffer, &String::new(") {\nentry:\n"));
        
        // Alloca for params
        let mut ap: usize = 0;
        while ap < fdecl.param_count {
            let param: ParamDecl = Vec::get_ParamDecl(&(*arena).params, fdecl.param_start + ap);
            String::push_str(&mut (*e).buffer, &String::new("  %"));
            String::push_str(&mut (*e).buffer, &param.name);
            String::push_str(&mut (*e).buffer, &String::new(" = alloca i32\n"));
            String::push_str(&mut (*e).buffer, &String::new("  store i32 %"));
            String::push_str(&mut (*e).buffer, &param.name);
            String::push_str(&mut (*e).buffer, &String::new(".arg, ptr %"));
            String::push_str(&mut (*e).buffer, &param.name);
            String::push_str(&mut (*e).buffer, &String::new("\n"));
            ap += 1;
        }

        let mut s: usize = 0;
        while s < fdecl.body_count {
            LlvmEmitter::emit_stmt(e, arena, fdecl.body_start + s);
            s += 1;
        }
        
        // Default return just in case
        String::push_str(&mut (*e).buffer, &String::new("  ret i32 0\n}\n\n"));
    }

    @unsafe
    fn emit_stmt(e: &mut LlvmEmitter, arena: &AstArena, stmt_idx: usize) {
        let stmt: Stmt = Vec::get_Stmt(&(*arena).stmts, stmt_idx);
        
        if stmt.tag == Stmt_TAG_Let {
            let var_name: String = stmt.data.Let._0;
            let init_idx: usize = stmt.data.Let._2;
            
            String::push_str(&mut (*e).buffer, &String::new("  %"));
            String::push_str(&mut (*e).buffer, &var_name);
            String::push_str(&mut (*e).buffer, &String::new(" = alloca i32\n"));
            
            if init_idx > 0 {
                let val: String = LlvmEmitter::emit_expr(e, arena, init_idx - 1);
                String::push_str(&mut (*e).buffer, &String::new("  store i32 "));
                String::push_str(&mut (*e).buffer, &val);
                String::push_str(&mut (*e).buffer, &String::new(", ptr %"));
                String::push_str(&mut (*e).buffer, &var_name);
                String::push_str(&mut (*e).buffer, &String::new("\n"));
            }
        } else if stmt.tag == Stmt_TAG_Assign {
            let target_idx: usize = stmt.data.Assign._0;
            let value_idx: usize = stmt.data.Assign._1;
            
            let val: String = LlvmEmitter::emit_expr(e, arena, value_idx - 1);
            let target_addr: String = LlvmEmitter::emit_lvalue(e, arena, target_idx - 1);
            
            String::push_str(&mut (*e).buffer, &String::new("  store i32 "));
            String::push_str(&mut (*e).buffer, &val);
            String::push_str(&mut (*e).buffer, &String::new(", ptr "));
            String::push_str(&mut (*e).buffer, &target_addr);
            String::push_str(&mut (*e).buffer, &String::new("\n"));
        } else if stmt.tag == Stmt_TAG_Return {
            let ret_idx: usize = stmt.data.Return._0;
            if ret_idx > 0 {
                let val: String = LlvmEmitter::emit_expr(e, arena, ret_idx - 1);
                String::push_str(&mut (*e).buffer, &String::new("  ret i32 "));
                String::push_str(&mut (*e).buffer, &val);
                String::push_str(&mut (*e).buffer, &String::new("\n"));
            } else {
                String::push_str(&mut (*e).buffer, &String::new("  ret void\n"));
            }
        } else if stmt.tag == Stmt_TAG_ExprStmt {
            let expr_idx: usize = stmt.data.ExprStmt._0;
            LlvmEmitter::emit_expr(e, arena, expr_idx - 1);
        } else if stmt.tag == Stmt_TAG_If {
            let cond_idx: usize = stmt.data.If._0;
            let then_start: usize = stmt.data.If._1;
            let then_count: usize = stmt.data.If._2;
            
            let cond: String = LlvmEmitter::emit_expr(e, arena, cond_idx - 1);
            let then_lbl: String = LlvmEmitter::fresh_label(e, &String::new("then"));
            let merge_lbl: String = LlvmEmitter::fresh_label(e, &String::new("merge"));
            
            String::push_str(&mut (*e).buffer, &String::new("  br i1 "));
            String::push_str(&mut (*e).buffer, &cond);
            String::push_str(&mut (*e).buffer, &String::new(", label %"));
            String::push_str(&mut (*e).buffer, &then_lbl);
            String::push_str(&mut (*e).buffer, &String::new(", label %"));
            String::push_str(&mut (*e).buffer, &merge_lbl);
            String::push_str(&mut (*e).buffer, &String::new("\n"));
            
            String::push_str(&mut (*e).buffer, &then_lbl);
            String::push_str(&mut (*e).buffer, &String::new(":\n"));
            let mut i: usize = 0;
            while i < then_count {
                LlvmEmitter::emit_stmt(e, arena, then_start + i);
                i += 1;
            }
            String::push_str(&mut (*e).buffer, &String::new("  br label %"));
            String::push_str(&mut (*e).buffer, &merge_lbl);
            String::push_str(&mut (*e).buffer, &String::new("\n"));
            
            String::push_str(&mut (*e).buffer, &merge_lbl);
            String::push_str(&mut (*e).buffer, &String::new(":\n"));
        }
    }

    @unsafe
    fn emit_lvalue(e: &mut LlvmEmitter, arena: &AstArena, expr_idx: usize) -> String {
        let expr: Expr = Vec::get_Expr(&(*arena).exprs, expr_idx);
        if expr.tag == Expr_TAG_Ident {
            let mut res: String = String::new("%");
            String::push_str(&mut res, &expr.data.Ident._0);
            return res;
        }
        return LlvmEmitter::emit_expr(e, arena, expr_idx);
    }

    @unsafe
    fn emit_expr(e: &mut LlvmEmitter, arena: &AstArena, expr_idx: usize) -> String {
        let expr: Expr = Vec::get_Expr(&(*arena).exprs, expr_idx);
        
        if expr.tag == Expr_TAG_IntLit {
            return String::new("0");
        } else if expr.tag == Expr_TAG_Ident {
            let tmp: String = LlvmEmitter::fresh_tmp(e);
            String::push_str(&mut (*e).buffer, &String::new("  "));
            String::push_str(&mut (*e).buffer, &tmp);
            String::push_str(&mut (*e).buffer, &String::new(" = load i32, ptr %"));
            String::push_str(&mut (*e).buffer, &expr.data.Ident._0);
            String::push_str(&mut (*e).buffer, &String::new("\n"));
            return tmp;
        } else if expr.tag == Expr_TAG_BinaryExpr {
            let lhs_idx: usize = expr.data.BinaryExpr._0;
            let rhs_idx: usize = expr.data.BinaryExpr._2;
            let l: String = LlvmEmitter::emit_expr(e, arena, lhs_idx - 1);
            let r: String = LlvmEmitter::emit_expr(e, arena, rhs_idx - 1);
            let tmp: String = LlvmEmitter::fresh_tmp(e);
            
            String::push_str(&mut (*e).buffer, &String::new("  "));
            String::push_str(&mut (*e).buffer, &tmp);
            // Default to add for prototype
            String::push_str(&mut (*e).buffer, &String::new(" = add i32 "));
            String::push_str(&mut (*e).buffer, &l);
            String::push_str(&mut (*e).buffer, &String::new(", "));
            String::push_str(&mut (*e).buffer, &r);
            String::push_str(&mut (*e).buffer, &String::new("\n"));
            return tmp;
        } else if expr.tag == Expr_TAG_Call {
            let func_idx: usize = expr.data.Call._0;
            let func_expr: Expr = Vec::get_Expr(&(*arena).exprs, func_idx - 1);
            let mut func_name: String = String::new("unknown");
            if func_expr.tag == Expr_TAG_Ident {
                func_name = String::clone(&func_expr.data.Ident._0);
            }
            
            let tmp: String = LlvmEmitter::fresh_tmp(e);
            String::push_str(&mut (*e).buffer, &String::new("  "));
            String::push_str(&mut (*e).buffer, &tmp);
            String::push_str(&mut (*e).buffer, &String::new(" = call i32 @"));
            String::push_str(&mut (*e).buffer, &func_name);
            String::push_str(&mut (*e).buffer, &String::new("()\n"));
            return tmp;
        }
        return String::new("0");
    }
}
