// ============================================================
//  Y-Lang Standard Library Interfaces
//  lib.y
//
//  This file contains the forward declarations and standard
//  library wrappers that map Y-Lang standard types (Vec, String, File)
//  to the C11 runtime backend equivalents.
// ============================================================

// ── Array / Vector (Maps to YVec in C backend) ──────────────

@target(CPU_AVX512)
impl Vec {
    // Note: C-backend natively intercepts generic parameters for Vec
    
    // Allocates a new empty Vec.
    // In C: maps directly to yvec_new(sizeof(T))
    fn new(elem_size: I32) -> Vec {
        // Backend intercepts this or we use native C runtime name
        return yvec_new(elem_size);
    }
    
    // Pushes an element to the Vec.
    fn push(v: &mut Vec, elem: &char) {
        yvec_push(v, elem);
    }

    // Free the memory
    fn free(v: &mut Vec) {
        yvec_free(v);
    }
    
    // Returns length
    fn len(v: &Vec) -> usize {
        return yvec_len(v);
    }
    
    // Returns char element
    fn get_char(v: &Vec, i: usize) -> char {
        return yvec_get_char(v, i);
    }
}

// ── String (Maps to YStr in C backend) ──────────────────────

@target(CPU_AVX512)
impl String {
    // Length of string
    fn len(s: &String) -> usize {
        return ystr_len(s);
    }
    // Creates a copy of the string
    fn clone(s: &String) -> String {
        return ystr_clone(s);
    }

    // Appends a character
    fn push(s: &mut String, c: char) {
        ystr_push(s, c);
    }

    // Appends another string
    fn push_str(s: &mut String, other: &String) {
        ystr_push_str(s, other);
    }

    // Equivalency check
    fn eq(a: &String, b: &String) -> bool {
        return ystr_eq(a, b);
    }
    
    fn eq_cstr(a: &String, b: &char) -> bool {
        return ystr_eq_cstr(a, b);
    }

    // Returns character at index
    fn char_at(s: &String, i: usize) -> char {
        return ystr_char_at(s, i);
    }

    fn free(s: &mut String) {
        ystr_free(s);
    }
}

// ── File I/O ─────────────────────────────────────────────

@target(CPU_AVX512)
impl File {
    fn read_to_string(path: &String) -> String {
        return yfile_read_to_string(path);
    }
    
    fn write(path: &String, content: &String) {
        yfile_write(path, content);
    }
}
// ============================================================
//  Y-Lang  —  Lexer (Front-End Tokenizer) mapped to Y-Lang
//  lexer.y
// ============================================================

import lib;

// ── Token kinds ──────────────────────────────────────────────

enum TokenKind {
    // ── Keywords ─────────────────────────────────────────────
    Kernel,
    Let,
    Type,
    For,
    In,
    Step,
    Return,
    Const,
    Pub,
    Mut,
    Unsafe,
    Wait,
    Emit,
    Load,
    Store,
    Barrier,
    Struct,
    Enum,
    Fn,
    Match,
    Safe,
    Chisel,
    Import,
    While,
    Impl,
    SelfKw,
    If,
    Else,
    True,
    False,

    // ── Memory space types ───────────────────────────────────
    GlobalMemory,
    L2Memory,
    SharedMemory,
    RegisterFile,

    // ── Layout / transfer / fragment types ──────────────────
    SmemLayout,
    Swizzle,
    NoSwizzle,
    Pipeline,
    Transfer,
    Fragment,

    // ── MMA atom identifiers ─────────────────────────────────
    MmaMod(String), 

    // ── Fragment roles ───────────────────────────────────────
    RoleA, RoleB, RoleC, RoleD,

    // ── Primitive / scalar dtypes ────────────────────────────
    F16, BF16, TF32, F32, F64,
    I8, I16, I32, I64,
    U3, U8, U16, U32, U64,
    Bool, StringTy, CharTy, VecTy, File, OptionTy,

    // ── Transfer policies ────────────────────────────────────
    Async, Sync,

    // ── Cache policies ───────────────────────────────────────
    L2Persist, L2EvictFirst, L2EvictLast, L2Stream,

    // ── Hardware targets ─────────────────────────────────────
    HardwareTarget(String),

    // ── Built-in functions ───────────────────────────────────
    CpAsync, LdMatrix, MmaSync, BarrierSync,

    // ── Attributes (start with @) ────────────────────────────
    AtTarget, AtCachePolicy, AtPtxEmit, AtAvxEmit, AtInline,
    AtNoInline, AtAlign, AtSafe, AtUnsafe, AtGpuUncached,
    AtAtomic, AtStaticAssert, AtUnknown(String),

    // ── Operators ────────────────────────────────────────────
    Arrow, DotDot, ColonColon, Colon, Assign, FatArrow,
    EqEq, NotEq, Lt, Gt, LtEq, GtEq, Plus, Minus, Star,
    Slash, Percent, Ampersand, Pipe, Caret, Bang, AmpAmp,
    PipePipe, LtLt, GtGt, PlusAssign, MinusAssign,
    StarAssign, SlashAssign, Dot,

    // ── Delimiters ───────────────────────────────────────────
    LBrace, RBrace, LParen, RParen, LBracket, RBracket,
    Semicolon, Comma,

    // ── Literals ─────────────────────────────────────────────
    IntLit(I64), FloatLit(F64), StringLit(String),
    CharLit(char),

    // ── Identifiers ──────────────────────────────────────────
    Ident(String),

    // ── Special ──────────────────────────────────────────────
    Eof, Unknown(char)
}

struct Token {
    kind: TokenKind,
    line: usize,
    col: usize,
    lexeme: String
}

impl Token {
    @unsafe
    fn new(kind: TokenKind, line: usize, col: usize, lexeme: &String) -> Token {
        let tok: Token;
        tok.kind = kind;
        tok.line = line;
        tok.col = col;
        tok.lexeme = String::clone(lexeme);
        return tok;
    }
}

struct Lexer {
    input: Vec<char>,
    pos: usize,
    line: usize,
    col: usize,
}

impl Lexer {
    @unsafe
    fn new(source: &String) -> Lexer {
        let lx: Lexer;
        let mut input_vec: Vec<char> = Vec::new(1); // char element size is 1 byte in C, wait no sizeof(char)=1, wait we use `char` primitive which C emitter translates to char
        
        let len: usize = String::len(source);
        let mut i: usize = 0;
        
        while i < len {
            let ch: char = String::char_at(source, i);
            Vec::push(&mut input_vec, ch); // NOTE replaced &ch with ch since it takes char
            i += 1;
        }

        lx.input = input_vec;
        lx.pos = 0;
        lx.line = 1;
        lx.col = 1;
        return lx;
    }

    // Since Y-Lang doesn't have Option types perfectly mapped natively yet,
    // we return a null char '\0' to represent EOF for peek().
    @unsafe
    fn peek(lx: &Lexer) -> char {
        let max_len: usize = Vec::len(&(*lx).input);
        if (*lx).pos >= max_len {
            return '\0';
        }
        return Vec::get_char(&(*lx).input, (*lx).pos);
    }
    
    @unsafe
    fn peek2(lx: &Lexer) -> char {
        let max_len: usize = Vec::len(&(*lx).input);
        if (*lx).pos + 1 >= max_len {
            return '\0';
        }
        return Vec::get_char(&(*lx).input, (*lx).pos + 1);
    }

    @unsafe
    fn advance(lx: &mut Lexer) -> char {
        let ch: char = Lexer::peek(lx);
        if ch == '\0' {
            return ch;
        }
        
        (*lx).pos += 1;
        if ch == '\n' {
            (*lx).line += 1;
            (*lx).col = 1;
        } else {
            (*lx).col += 1;
        }
        
        return ch;
    }

    @unsafe
    fn matches_next(lx: &mut Lexer, expected: char) -> bool {
        let ch: char = Lexer::peek(lx);
        if ch == expected {
            Lexer::advance(lx);
            return true;
        }
        return false;
    }
}

impl Lexer {
    @unsafe
    fn classify_ident(s: &String) -> TokenKind {
        if String::eq_cstr(s, "enum") { return TokenKind::Enum; }
        if String::eq_cstr(s, "struct") { return TokenKind::Struct; }
        if String::eq_cstr(s, "impl") { return TokenKind::Impl; }
        if String::eq_cstr(s, "fn") { return TokenKind::Fn; }
        if String::eq_cstr(s, "let") { return TokenKind::Let; }
        if String::eq_cstr(s, "return") { return TokenKind::Return; }
        if String::eq_cstr(s, "if") { return TokenKind::If; }
        if String::eq_cstr(s, "else") { return TokenKind::Else; }
        if String::eq_cstr(s, "while") { return TokenKind::While; }
        if String::eq_cstr(s, "true") { return TokenKind::True; }
        if String::eq_cstr(s, "false") { return TokenKind::False; }
        if String::eq_cstr(s, "mut") { return TokenKind::Mut; }
        
        // Types
        if String::eq_cstr(s, "String") { return TokenKind::StringTy; }
        if String::eq_cstr(s, "Vec") { return TokenKind::VecTy; }
        if String::eq_cstr(s, "char") { return TokenKind::CharTy; }
        if String::eq_cstr(s, "usize") { return TokenKind::Ident(String::clone(s)); }
        if String::eq_cstr(s, "I32") { return TokenKind::I32; }
        if String::eq_cstr(s, "I64") { return TokenKind::I64; }
        if String::eq_cstr(s, "bool") { return TokenKind::Bool; }
        
        // Ident
        return TokenKind::Ident(String::clone(s));
    }
    
    @unsafe
    fn skip_whitespace(lx: &mut Lexer) {
        let mut parsing: bool = true;
        while parsing {
            let ch: char = Lexer::peek(lx);
            if ch == ' ' { Lexer::advance(lx); }
            else if ch == '\n' { Lexer::advance(lx); }
            else if ch == '\r' { Lexer::advance(lx); }
            else if ch == '\t' { Lexer::advance(lx); }
            else { parsing = false; }
        }
    }

    @unsafe
    fn scan_ident_or_keyword(lx: &mut Lexer, start_col: usize, first_char: char) -> Token {
        let line: usize = (*lx).line;
        let mut s: String = String::new("");
        String::push(&mut s, first_char);
        
        let mut parsing: bool = true;
        while parsing {
            let ch: char = Lexer::peek(lx);
            let mut is_alpha: bool = false;
            if ch >= 'a' { if ch <= 'z' { is_alpha = true; } }
            if ch >= 'A' { if ch <= 'Z' { is_alpha = true; } }
            if ch >= '0' { if ch <= '9' { is_alpha = true; } }
            if ch == '_' { is_alpha = true; }
            
            if is_alpha {
                String::push(&mut s, ch);
                Lexer::advance(lx);
            } else {
                parsing = false;
            }
        }
        
        let kind: TokenKind = Lexer::classify_ident(&s);
        return Token::new(kind, line, start_col, &s);
    }
}

impl Lexer {
    @unsafe
    fn scan_number(lx: &mut Lexer, start_col: usize, first_char: char) -> Token {
        let line: usize = (*lx).line;
        let mut s: String = String::new("");
        String::push(&mut s, first_char);
        
        let mut is_float: bool = false;
        let mut parsing: bool = true;
        
        while parsing {
            let ch: char = Lexer::peek(lx);
            let mut is_digit: bool = false;
            if ch >= '0' { if ch <= '9' { is_digit = true; } }
            
            if is_digit {
                String::push(&mut s, ch);
                Lexer::advance(lx);
            } else if ch == '.' {
                is_float = true;
                String::push(&mut s, ch);
                Lexer::advance(lx);
            } else {
                parsing = false;
            }
        }
        
        if is_float {
            return Token::new(TokenKind::FloatLit(0.0), line, start_col, &s);
        } else {
            return Token::new(TokenKind::IntLit(0), line, start_col, &s);
        }
    }

    @unsafe
    fn next_token(lx: &mut Lexer) -> Token {
        Lexer::skip_whitespace(lx);

        let line: usize = (*lx).line;
        let start_col: usize = (*lx).col;

        let ch: char = Lexer::advance(lx);
        
        if ch == '\0' {
            let empty: String = String::new("");
            return Token::new(TokenKind::Eof, line, start_col, &empty);
        }

        // Single-char operators
        if ch == '{' { let x: String = String::new("{"); return Token::new(TokenKind::LBrace, line, start_col, &x); }
        if ch == '}' { let x: String = String::new("}"); return Token::new(TokenKind::RBrace, line, start_col, &x); }
        if ch == '(' { let x: String = String::new("("); return Token::new(TokenKind::LParen, line, start_col, &x); }
        if ch == ')' { let x: String = String::new(")"); return Token::new(TokenKind::RParen, line, start_col, &x); }
        if ch == ';' { let x: String = String::new(";"); return Token::new(TokenKind::Semicolon, line, start_col, &x); }
        if ch == ':' { let x: String = String::new(":"); return Token::new(TokenKind::Colon, line, start_col, &x); }
        if ch == ',' { let x: String = String::new(","); return Token::new(TokenKind::Comma, line, start_col, &x); }
        if ch == '=' { let x: String = String::new("="); return Token::new(TokenKind::Assign, line, start_col, &x); }
        if ch == '+' { let x: String = String::new("+"); return Token::new(TokenKind::Plus, line, start_col, &x); }
        if ch == '*' { let x: String = String::new("*"); return Token::new(TokenKind::Star, line, start_col, &x); }
        if ch == '&' { let x: String = String::new("&"); return Token::new(TokenKind::Ampersand, line, start_col, &x); }
        if ch == '<' { let x: String = String::new("<"); return Token::new(TokenKind::Lt, line, start_col, &x); }
        if ch == '>' { let x: String = String::new(">"); return Token::new(TokenKind::Gt, line, start_col, &x); }

        let mut is_alpha: bool = false;
        if ch >= 'a' { if ch <= 'z' { is_alpha = true; } }
        if ch >= 'A' { if ch <= 'Z' { is_alpha = true; } }
        if ch == '_' { is_alpha = true; }

        if is_alpha {
            return Lexer::scan_ident_or_keyword(lx, start_col, ch);
        }

        let mut is_digit: bool = false;
        if ch >= '0' { if ch <= '9' { is_digit = true; } }
        
        if is_digit {
            return Lexer::scan_number(lx, start_col, ch);
        }

        let other: String = String::new("?");
        return Token::new(TokenKind::Unknown(ch), line, start_col, &other);
    }
}

impl Lexer {
    @unsafe
    fn tokenize(lx: &mut Lexer) -> Vec {
        let mut tokens: Vec = Vec::new(32);
        let mut parsing: bool = true;
        
        while parsing {
            let tok: Token = Lexer::next_token(lx);
            
            let len: usize = String::len(&tok.lexeme);
            if len == 0 {
                parsing = false;
            } else {
                Vec::push(&mut tokens, tok);
            }
        }
        
        return tokens;
    }
}

@unsafe
fn main() {
    println("--- Y-Lang Self-Hosted Lexer Bootstrapping ---");
    let source: String = String::new("fn test() ; let x = 123 }");
    
    let mut lexer: Lexer = Lexer::new(&source);
    
    let mut parsing: bool = true;
    while parsing {
        let tok: Token = Lexer::next_token(&mut lexer);
        
        let len: usize = String::len(&tok.lexeme);
        if len == 0 {
            println("[EOF]");
            parsing = false;
        } else {
            print("Token: ");
            println(&tok.lexeme); // Fixed print arg to reference
        }
    }
    
    return;
}
// ============================================================
//  Y-Lang  —  Self-Hosted Parser (Recursive Descent)
//  parser.yy
//
//  Translates a Vec<Token> stream into a flattened AST using
//  Data-Oriented Arena Allocation. All recursive tree nodes
//  use `usize` indices into central AstArena vectors instead
//  of heap-allocated pointers, guaranteeing clean C emission.
// ============================================================

import lib;

// ── Span ────────────────────────────────────────────────────
struct Span {
    line: usize,
    col: usize
}

// Removed duplicate Token and TokenKind, they are loaded from lexer.yy

// ── Operators ───────────────────────────────────────────────
enum BinaryOp {
    Add, Sub, Mul, Div, Mod,
    Eq, NotEq, Lt, Gt, Le, Ge,
    And, Or,
    BitAnd, BitOr, BitXor, Shl, Shr
}

enum UnaryOp {
    Neg, Not, Ref, Deref
}

// ════════════════════════════════════════════════════════════
//  FLATTENED AST (Data-Oriented Design)
//
//  Every recursive node (Expr containing Expr, Stmt containing
//  Expr/Block, etc.) uses `usize` indices into an AstArena.
//  The value `0` as a "null index" means "no node" (None).
//  Valid indices start at 1 so we offset by -1 when accessing.
// ════════════════════════════════════════════════════════════

// ── Expressions ─────────────────────────────────────────────
// Flattened: all child Expr references are `usize` arena indices.

enum Expr {
    Ident(String),
    IntLit(I64),
    FloatLit(I64),
    StringLit(String),
    CharLit(char),
    BoolLit(I32),
    SelfLit,

    // func_idx points to an Expr in the arena (Ident/Path/MemberAccess)
    // args_start / args_count index into a parallel args array
    Call(usize, usize, usize),

    // base_idx[index_idx]
    Index(usize, usize),

    // base_idx.member
    MemberAccess(usize, String),

    // Namespace::member
    Path(String, String),

    // left_idx op right_idx
    BinaryExpr(usize, BinaryOp, usize),

    // op operand_idx
    UnaryExpr(UnaryOp, usize)
}

// ── Statements ──────────────────────────────────────────────

enum Stmt {
    // let name: ty = init;  (ty_idx=0 means no type, init_idx=0 means no init)
    Let(String, usize, usize),

    // return expr; (expr_idx=0 means bare return)
    Return(usize),

    // if cond_idx { then_start..then_count } else { else_start..else_count }
    If(usize, usize, usize, usize, usize),

    // while cond_idx { body_start..body_count }
    While(usize, usize, usize),

    // target_idx = value_idx;
    Assign(usize, usize),

    // target_idx op= value_idx;
    CompoundAssign(usize, BinaryOp, usize),

    // A standalone expression statement (expr_idx)
    ExprStmt(usize)
}

// ── Declarations ────────────────────────────────────────────

struct FuncDecl {
    name: String,
    is_safe: I32,
    param_start: usize,
    param_count: usize,
    body_start: usize,
    body_count: usize,
    line: usize,
    col: usize
}

struct ParamDecl {
    name: String,
    type_str: String
}

impl Vec {
    fn get_Token(v: &Vec, i: usize) -> Token { let d: Token; return d; }
    fn get_Expr(v: &Vec, i: usize) -> Expr { let d: Expr; return d; }
    fn get_Stmt(v: &Vec, i: usize) -> Stmt { let d: Stmt; return d; }
    fn get_FuncDecl(v: &Vec, i: usize) -> FuncDecl { let d: FuncDecl; return d; }
    fn get_ParamDecl(v: &Vec, i: usize) -> ParamDecl { let d: ParamDecl; return d; }
    fn get_usize(v: &Vec, i: usize) -> usize { return 0; }
}

// ════════════════════════════════════════════════════════════
//  AST ARENA — The Heart of Data-Oriented Design
// ════════════════════════════════════════════════════════════

struct AstArena {
    exprs: Vec,
    stmts: Vec,
    params: Vec,
    funcs: Vec,
    // Auxiliary: expression argument lists stored flat
    arg_indices: Vec
}

impl AstArena {
    @unsafe
    fn new() -> AstArena {
        let arena: AstArena;
        // sizeof(Expr)  — We use a generous estimate for tagged union size
        arena.exprs = Vec::new(64);
        arena.stmts = Vec::new(64);
        arena.params = Vec::new(32);
        arena.funcs = Vec::new(32);
        arena.arg_indices = Vec::new(8);
        return arena;
    }
}

// ════════════════════════════════════════════════════════════
//  PARSER — Recursive Descent
// ════════════════════════════════════════════════════════════

struct Parser {
    tokens: Vec,
    pos: usize,
    token_count: usize
}

// ── Core Helpers ────────────────────────────────────────────

impl Parser {
    @unsafe
    fn new(tokens: Vec, count: usize) -> Parser {
        let p: Parser;
        p.tokens = tokens;
        p.pos = 0;
        p.token_count = count;
        return p;
    }

    @unsafe
    fn peek(p: &Parser) -> Token {
        if (*p).pos < (*p).token_count {
            return Vec::get_Token(&(*p).tokens, (*p).pos);
        }
        let eof: Token;
        eof.kind = TokenKind::Eof;
        eof.line = 0;
        eof.col = 0;
        eof.lexeme = String::new("");
        return eof;
    }

    @unsafe
    fn advance(p: &mut Parser) -> Token {
        let tok: Token = Parser::peek(p);
        if (*p).pos < (*p).token_count {
            (*p).pos += 1;
        }
        return tok;
    }

    @unsafe
    fn check_eof(p: &Parser) -> bool {
        if (*p).pos >= (*p).token_count {
            return true;
        }
        return false;
    }

    @unsafe
    fn match_ident(p: &mut Parser) -> String {
        // If current token is Ident, consume and return its lexeme.
        // Otherwise return empty string (caller checks).
        let tok: Token = Parser::peek(p);
        let lex: String = String::clone(&tok.lexeme);
        let len: usize = String::len(&lex);
        if len > 0 {
            // Check first char is alphabetic
            let ch: char = String::char_at(&lex, 0);
            let mut is_ident: bool = false;
            if ch >= 'a' { if ch <= 'z' { is_ident = true; } }
            if ch >= 'A' { if ch <= 'Z' { is_ident = true; } }
            if ch == '_' { is_ident = true; }

            if is_ident {
                Parser::advance(p);
                return lex;
            }
        }
        return String::new("");
    }

    @unsafe
    fn expect_token(p: &mut Parser, expected: &String) {
        // Consume current token and verify its lexeme matches.
        // On mismatch, print error and exit.
        let tok: Token = Parser::advance(p);
        let matches: bool = String::eq_cstr(&tok.lexeme, expected);
        if matches {
            return;
        }
        print("Syntax Error: Expected '");
        print(expected);
        print("' but found '");
        print(&tok.lexeme);
        print("' at line ");
        print_int(tok.line);
        println("");
        // exit(1) — mapped to C stdlib
        return;
    }
}

// ── Expression Parsing ──────────────────────────────────────

impl Parser {
    @unsafe
    fn parse_primary(p: &mut Parser, arena: &mut AstArena) -> usize {
        let tok: Token = Parser::peek(p);
        let lex: String = String::clone(&tok.lexeme);
        let line: usize = tok.line;
        let col: usize = tok.col;

        // Integer literal
        let len: usize = String::len(&lex);
        if len > 0 {
            let ch: char = String::char_at(&lex, 0);
            let mut is_digit: bool = false;
            if ch >= '0' { if ch <= '9' { is_digit = true; } }

            if is_digit {
                Parser::advance(p);
                let expr: Expr = Expr::IntLit(0);
                Vec::push(&mut (*arena).exprs, expr);
                let idx: usize = Vec::len(&(*arena).exprs);
                return idx;
            }

            // String literal: starts with '"'
            if ch == '"' {
                Parser::advance(p);
                let expr: Expr = Expr::StringLit(String::clone(&lex));
                Vec::push(&mut (*arena).exprs, expr);
                let idx: usize = Vec::len(&(*arena).exprs);
                return idx;
            }

            // Bool: "true" / "false"
            if String::eq_cstr(&lex, "true") {
                Parser::advance(p);
                let expr: Expr = Expr::BoolLit(1);
                Vec::push(&mut (*arena).exprs, expr);
                let idx: usize = Vec::len(&(*arena).exprs);
                return idx;
            }
            if String::eq_cstr(&lex, "false") {
                Parser::advance(p);
                let expr: Expr = Expr::BoolLit(0);
                Vec::push(&mut (*arena).exprs, expr);
                let idx: usize = Vec::len(&(*arena).exprs);
                return idx;
            }

            // Identifier (could be start of Path or standalone)
            let mut is_ident: bool = false;
            if ch >= 'a' { if ch <= 'z' { is_ident = true; } }
            if ch >= 'A' { if ch <= 'Z' { is_ident = true; } }
            if ch == '_' { is_ident = true; }

            if is_ident {
                Parser::advance(p);

                // Check for Namespace::member path
                let next: Token = Parser::peek(p);
                if String::eq_cstr(&next.lexeme, "::") {
                    Parser::advance(p);
                    let member_tok: Token = Parser::advance(p);
                    let member_lex: String = String::clone(&member_tok.lexeme);
                    let expr: Expr = Expr::Path(String::clone(&lex), member_lex);
                    Vec::push(&mut (*arena).exprs, expr);
                    let idx: usize = Vec::len(&(*arena).exprs);
                    return idx;
                }

                let expr: Expr = Expr::Ident(String::clone(&lex));
                Vec::push(&mut (*arena).exprs, expr);
                let idx: usize = Vec::len(&(*arena).exprs);
                return idx;
            }
        }

        // Parenthesized expression
        if String::eq_cstr(&lex, "(") {
            Parser::advance(p);
            let inner_idx: usize = Parser::parse_expr(p, arena);
            Parser::expect_token(p, &String::new(")"));
            return inner_idx;
        }

        // Unary operators: &, *, -, !
        if String::eq_cstr(&lex, "&") {
            Parser::advance(p);
            let operand_idx: usize = Parser::parse_primary(p, arena);
            let expr: Expr = Expr::UnaryExpr(UnaryOp::Ref, operand_idx);
            Vec::push(&mut (*arena).exprs, expr);
            let idx: usize = Vec::len(&(*arena).exprs);
            return idx;
        }
        if String::eq_cstr(&lex, "*") {
            Parser::advance(p);
            let operand_idx: usize = Parser::parse_primary(p, arena);
            let expr: Expr = Expr::UnaryExpr(UnaryOp::Deref, operand_idx);
            Vec::push(&mut (*arena).exprs, expr);
            let idx: usize = Vec::len(&(*arena).exprs);
            return idx;
        }
        if String::eq_cstr(&lex, "-") {
            Parser::advance(p);
            let operand_idx: usize = Parser::parse_primary(p, arena);
            let expr: Expr = Expr::UnaryExpr(UnaryOp::Neg, operand_idx);
            Vec::push(&mut (*arena).exprs, expr);
            let idx: usize = Vec::len(&(*arena).exprs);
            return idx;
        }
        if String::eq_cstr(&lex, "!") {
            Parser::advance(p);
            let operand_idx: usize = Parser::parse_primary(p, arena);
            let expr: Expr = Expr::UnaryExpr(UnaryOp::Not, operand_idx);
            Vec::push(&mut (*arena).exprs, expr);
            let idx: usize = Vec::len(&(*arena).exprs);
            return idx;
        }

        // Fallback: unknown token
        print("[!] Parse error: unexpected token '");
        print(&lex);
        print("' at line ");
        print_int(tok.line);
        println("");
        // Push a dummy node to prevent crash
        let dummy: Expr = Expr::IntLit(0);
        Vec::push(&mut (*arena).exprs, dummy);
        let idx: usize = Vec::len(&(*arena).exprs);
        return idx;
    }

    @unsafe
    fn parse_postfix(p: &mut Parser, arena: &mut AstArena, lhs_idx: usize) -> usize {
        let mut current: usize = lhs_idx;

        let mut running: bool = true;
        while running {
            let tok: Token = Parser::peek(p);
            let lex: String = String::clone(&tok.lexeme);

            // Function call: (
            if String::eq_cstr(&lex, "(") {
                Parser::advance(p);
                let args_start: usize = Vec::len(&(*arena).arg_indices);
                let mut arg_count: usize = 0;

                let mut parsing_args: bool = true;
                while parsing_args {
                    let check: Token = Parser::peek(p);
                    if String::eq_cstr(&check.lexeme, ")") {
                        parsing_args = false;
                    } else {
                        let arg_idx: usize = Parser::parse_expr(p, arena);
                        Vec::push(&mut (*arena).arg_indices, arg_idx);
                        arg_count += 1;

                        let comma_check: Token = Parser::peek(p);
                        if String::eq_cstr(&comma_check.lexeme, ",") {
                            Parser::advance(p);
                        } else {
                            parsing_args = false;
                        }
                    }
                }
                Parser::expect_token(p, &String::new(")"));

                let call_expr: Expr = Expr::Call(current, args_start, arg_count);
                Vec::push(&mut (*arena).exprs, call_expr);
                current = Vec::len(&(*arena).exprs);
            }
            // Member access: .
            else if String::eq_cstr(&lex, ".") {
                Parser::advance(p);
                let member_tok: Token = Parser::advance(p);
                let member_name: String = String::clone(&member_tok.lexeme);
                let acc_expr: Expr = Expr::MemberAccess(current, member_name);
                Vec::push(&mut (*arena).exprs, acc_expr);
                current = Vec::len(&(*arena).exprs);
            }
            // Indexing: [
            else if String::eq_cstr(&lex, "[") {
                Parser::advance(p);
                let index_idx: usize = Parser::parse_expr(p, arena);
                Parser::expect_token(p, &String::new("]"));
                let idx_expr: Expr = Expr::Index(current, index_idx);
                Vec::push(&mut (*arena).exprs, idx_expr);
                current = Vec::len(&(*arena).exprs);
            }
            else {
                running = false;
            }
        }
        return current;
    }

    @unsafe
    fn get_binop_precedence(lex: &String) -> usize {
        // Returns precedence (0 = not a binop)
        if String::eq_cstr(lex, "||") { return 1; }
        if String::eq_cstr(lex, "&&") { return 3; }
        if String::eq_cstr(lex, "==") { return 5; }
        if String::eq_cstr(lex, "!=") { return 5; }
        if String::eq_cstr(lex, "<") { return 7; }
        if String::eq_cstr(lex, ">") { return 7; }
        if String::eq_cstr(lex, "<=") { return 7; }
        if String::eq_cstr(lex, ">=") { return 7; }
        if String::eq_cstr(lex, "|") { return 9; }
        if String::eq_cstr(lex, "^") { return 9; }
        if String::eq_cstr(lex, "&") { return 11; }
        if String::eq_cstr(lex, "+") { return 15; }
        if String::eq_cstr(lex, "-") { return 15; }
        if String::eq_cstr(lex, "*") { return 17; }
        if String::eq_cstr(lex, "/") { return 17; }
        if String::eq_cstr(lex, "%") { return 17; }
        return 0;
    }

    @unsafe
    fn lex_to_binop(lex: &String) -> BinaryOp {
        if String::eq_cstr(lex, "+") { return BinaryOp::Add; }
        if String::eq_cstr(lex, "-") { return BinaryOp::Sub; }
        if String::eq_cstr(lex, "*") { return BinaryOp::Mul; }
        if String::eq_cstr(lex, "/") { return BinaryOp::Div; }
        if String::eq_cstr(lex, "%") { return BinaryOp::Mod; }
        if String::eq_cstr(lex, "==") { return BinaryOp::Eq; }
        if String::eq_cstr(lex, "!=") { return BinaryOp::NotEq; }
        if String::eq_cstr(lex, "<") { return BinaryOp::Lt; }
        if String::eq_cstr(lex, ">") { return BinaryOp::Gt; }
        if String::eq_cstr(lex, "<=") { return BinaryOp::Le; }
        if String::eq_cstr(lex, ">=") { return BinaryOp::Ge; }
        if String::eq_cstr(lex, "&&") { return BinaryOp::And; }
        if String::eq_cstr(lex, "||") { return BinaryOp::Or; }
        if String::eq_cstr(lex, "&") { return BinaryOp::BitAnd; }
        if String::eq_cstr(lex, "|") { return BinaryOp::BitOr; }
        if String::eq_cstr(lex, "^") { return BinaryOp::BitXor; }
        // Default fallback
        return BinaryOp::Add;
    }

    @unsafe
    fn parse_expr_bp(p: &mut Parser, arena: &mut AstArena, min_bp: usize) -> usize {
        // Pratt parser: parse an expression with minimum binding power
        let mut lhs: usize = Parser::parse_primary(p, arena);
        lhs = Parser::parse_postfix(p, arena, lhs);

        let mut looping: bool = true;
        while looping {
            let tok: Token = Parser::peek(p);
            let lex: String = String::clone(&tok.lexeme);

            let prec: usize = Parser::get_binop_precedence(&lex);
            if prec == 0 {
                looping = false;
            } else if prec < min_bp {
                looping = false;
            } else {
                Parser::advance(p);
                let op: BinaryOp = Parser::lex_to_binop(&lex);
                let rhs: usize = Parser::parse_expr_bp(p, arena, prec + 1);

                let bin_expr: Expr = Expr::BinaryExpr(lhs, op, rhs);
                Vec::push(&mut (*arena).exprs, bin_expr);
                lhs = Vec::len(&(*arena).exprs);

                // Try postfix on the new combined expression
                lhs = Parser::parse_postfix(p, arena, lhs);
            }
        }
        return lhs;
    }

    @unsafe
    fn parse_expr(p: &mut Parser, arena: &mut AstArena) -> usize {
        return Parser::parse_expr_bp(p, arena, 0);
    }
}

// ── Statement Parsing ───────────────────────────────────────

impl Parser {
    @unsafe
    fn parse_stmt(p: &mut Parser, arena: &mut AstArena) -> usize {
        let tok: Token = Parser::peek(p);
        let lex: String = String::clone(&tok.lexeme);

        // ── let statement ──
        if String::eq_cstr(&lex, "let") {
            Parser::advance(p);
            // optional: mut
            let mut_check: Token = Parser::peek(p);
            if String::eq_cstr(&mut_check.lexeme, "mut") {
                Parser::advance(p);
            }
            // variable name
            let name_tok: Token = Parser::advance(p);
            let var_name: String = String::clone(&name_tok.lexeme);

            // optional type annotation
            let mut type_idx: usize = 0;
            let colon_check: Token = Parser::peek(p);
            if String::eq_cstr(&colon_check.lexeme, ":") {
                Parser::advance(p);
                // For bootstrap, skip type tokens until = or ;
                let mut skipping_type: bool = true;
                while skipping_type {
                    let t: Token = Parser::peek(p);
                    if String::eq_cstr(&t.lexeme, "=") {
                        skipping_type = false;
                    } else if String::eq_cstr(&t.lexeme, ";") {
                        skipping_type = false;
                    } else {
                        Parser::advance(p);
                    }
                }
            }

            // optional initializer
            let mut init_idx: usize = 0;
            let eq_check: Token = Parser::peek(p);
            if String::eq_cstr(&eq_check.lexeme, "=") {
                Parser::advance(p);
                init_idx = Parser::parse_expr(p, arena);
            }

            Parser::expect_token(p, &String::new(";"));
            let stmt: Stmt = Stmt::Let(var_name, type_idx, init_idx);
            Vec::push(&mut (*arena).stmts, stmt);
            let idx: usize = Vec::len(&(*arena).stmts);
            return idx;
        }

        // ── return statement ──
        if String::eq_cstr(&lex, "return") {
            Parser::advance(p);
            let mut ret_idx: usize = 0;
            let semi_check: Token = Parser::peek(p);
            if String::eq_cstr(&semi_check.lexeme, ";") {
                // bare return
            } else {
                ret_idx = Parser::parse_expr(p, arena);
            }
            Parser::expect_token(p, &String::new(";"));
            let stmt: Stmt = Stmt::Return(ret_idx);
            Vec::push(&mut (*arena).stmts, stmt);
            let idx: usize = Vec::len(&(*arena).stmts);
            return idx;
        }

        // ── if statement ──
        if String::eq_cstr(&lex, "if") {
            Parser::advance(p);
            let cond_idx: usize = Parser::parse_expr(p, arena);

            // Parse then block
            Parser::expect_token(p, &String::new("{"));
            let then_start: usize = Vec::len(&(*arena).stmts);
            let mut then_count: usize = 0;
            let mut parsing_then: bool = true;
            while parsing_then {
                let check: Token = Parser::peek(p);
                if String::eq_cstr(&check.lexeme, "}") {
                    parsing_then = false;
                } else {
                    Parser::parse_stmt(p, arena);
                    then_count += 1;
                }
            }
            Parser::expect_token(p, &String::new("}"));

            // Optional else block
            let mut else_start: usize = 0;
            let mut else_count: usize = 0;
            let else_check: Token = Parser::peek(p);
            if String::eq_cstr(&else_check.lexeme, "else") {
                Parser::advance(p);
                Parser::expect_token(p, &String::new("{"));
                else_start = Vec::len(&(*arena).stmts);
                let mut parsing_else: bool = true;
                while parsing_else {
                    let check2: Token = Parser::peek(p);
                    if String::eq_cstr(&check2.lexeme, "}") {
                        parsing_else = false;
                    } else {
                        Parser::parse_stmt(p, arena);
                        else_count += 1;
                    }
                }
                Parser::expect_token(p, &String::new("}"));
            }

            let stmt: Stmt = Stmt::If(cond_idx, then_start, then_count, else_start, else_count);
            Vec::push(&mut (*arena).stmts, stmt);
            let idx: usize = Vec::len(&(*arena).stmts);
            return idx;
        }

        // ── while statement ──
        if String::eq_cstr(&lex, "while") {
            Parser::advance(p);
            let cond_idx: usize = Parser::parse_expr(p, arena);
            Parser::expect_token(p, &String::new("{"));

            let body_start: usize = Vec::len(&(*arena).stmts);
            let mut body_count: usize = 0;
            let mut parsing_body: bool = true;
            while parsing_body {
                let check: Token = Parser::peek(p);
                if String::eq_cstr(&check.lexeme, "}") {
                    parsing_body = false;
                } else {
                    Parser::parse_stmt(p, arena);
                    body_count += 1;
                }
            }
            Parser::expect_token(p, &String::new("}"));

            let stmt: Stmt = Stmt::While(cond_idx, body_start, body_count);
            Vec::push(&mut (*arena).stmts, stmt);
            let idx: usize = Vec::len(&(*arena).stmts);
            return idx;
        }

        // ── Expression statement / Assignment ──
        let expr_idx: usize = Parser::parse_expr(p, arena);

        // Check for assignment: =
        let assign_check: Token = Parser::peek(p);
        if String::eq_cstr(&assign_check.lexeme, "=") {
            Parser::advance(p);
            let value_idx: usize = Parser::parse_expr(p, arena);
            Parser::expect_token(p, &String::new(";"));
            let stmt: Stmt = Stmt::Assign(expr_idx, value_idx);
            Vec::push(&mut (*arena).stmts, stmt);
            let idx: usize = Vec::len(&(*arena).stmts);
            return idx;
        }

        // Check for compound assignment: +=, -=, *=, /=
        if String::eq_cstr(&assign_check.lexeme, "+=") {
            Parser::advance(p);
            let val_idx: usize = Parser::parse_expr(p, arena);
            Parser::expect_token(p, &String::new(";"));
            let stmt: Stmt = Stmt::CompoundAssign(expr_idx, BinaryOp::Add, val_idx);
            Vec::push(&mut (*arena).stmts, stmt);
            let idx: usize = Vec::len(&(*arena).stmts);
            return idx;
        }
        if String::eq_cstr(&assign_check.lexeme, "-=") {
            Parser::advance(p);
            let val_idx: usize = Parser::parse_expr(p, arena);
            Parser::expect_token(p, &String::new(";"));
            let stmt: Stmt = Stmt::CompoundAssign(expr_idx, BinaryOp::Sub, val_idx);
            Vec::push(&mut (*arena).stmts, stmt);
            let idx: usize = Vec::len(&(*arena).stmts);
            return idx;
        }

        // Default: expression statement
        Parser::expect_token(p, &String::new(";"));
        let stmt: Stmt = Stmt::ExprStmt(expr_idx);
        Vec::push(&mut (*arena).stmts, stmt);
        let idx: usize = Vec::len(&(*arena).stmts);
        return idx;
    }
}

// ── Function Declaration Parsing ────────────────────────────

impl Parser {
    @unsafe
    fn parse_func_decl(p: &mut Parser, arena: &mut AstArena, is_safe: I32) -> usize {
        let name_tok: Token = Parser::advance(p);
        let fn_name: String = String::clone(&name_tok.lexeme);
        let line: usize = name_tok.line;
        let col: usize = name_tok.col;

        Parser::expect_token(p, &String::new("("));
        let param_start: usize = Vec::len(&(*arena).params);
        let mut param_count: usize = 0;

        // Parse parameters
        let mut parsing_params: bool = true;
        while parsing_params {
            let check: Token = Parser::peek(p);
            if String::eq_cstr(&check.lexeme, ")") {
                parsing_params = false;
            } else {
                let pname_tok: Token = Parser::advance(p);
                let pname: String = String::clone(&pname_tok.lexeme);
                Parser::expect_token(p, &String::new(":"));

                // Skip type tokens until , or )
                let mut type_str: String = String::new("");
                let mut skipping: bool = true;
                while skipping {
                    let t: Token = Parser::peek(p);
                    if String::eq_cstr(&t.lexeme, ",") {
                        skipping = false;
                    } else if String::eq_cstr(&t.lexeme, ")") {
                        skipping = false;
                    } else {
                        let tlex: String = String::clone(&t.lexeme);
                        String::push(&mut type_str, ' ');
                        // Append type token to type_str for debug
                        Parser::advance(p);
                    }
                }

                let param: ParamDecl;
                param.name = pname;
                param.type_str = type_str;
                Vec::push(&mut (*arena).params, param);
                param_count += 1;

                let comma_check: Token = Parser::peek(p);
                if String::eq_cstr(&comma_check.lexeme, ",") {
                    Parser::advance(p);
                }
            }
        }
        Parser::expect_token(p, &String::new(")"));

        // Optional return type: -> Type
        let arrow_check: Token = Parser::peek(p);
        if String::eq_cstr(&arrow_check.lexeme, "->") {
            Parser::advance(p);
            // Skip return type tokens until {
            let mut skip_ret: bool = true;
            while skip_ret {
                let t: Token = Parser::peek(p);
                if String::eq_cstr(&t.lexeme, "{") {
                    skip_ret = false;
                } else {
                    Parser::advance(p);
                }
            }
        }

        // Parse body block
        Parser::expect_token(p, &String::new("{"));
        let body_start: usize = Vec::len(&(*arena).stmts);
        let mut body_count: usize = 0;
        let mut parsing_body: bool = true;
        while parsing_body {
            let check: Token = Parser::peek(p);
            if String::eq_cstr(&check.lexeme, "}") {
                parsing_body = false;
            } else {
                Parser::parse_stmt(p, arena);
                body_count += 1;
            }
        }
        Parser::expect_token(p, &String::new("}"));

        let fdecl: FuncDecl;
        fdecl.name = fn_name;
        fdecl.is_safe = is_safe;
        fdecl.param_start = param_start;
        fdecl.param_count = param_count;
        fdecl.body_start = body_start;
        fdecl.body_count = body_count;
        fdecl.line = line;
        fdecl.col = col;
        Vec::push(&mut (*arena).funcs, fdecl);
        let idx: usize = Vec::len(&(*arena).funcs);
        return idx;
    }
}

// ── Top-Level Item Parsing ──────────────────────────────────

impl Parser {
    @unsafe
    fn parse_item(p: &mut Parser, arena: &mut AstArena) -> bool {
        let tok: Token = Parser::peek(p);
        let lex: String = String::clone(&tok.lexeme);

        // fn declaration
        if String::eq_cstr(&lex, "fn") {
            Parser::advance(p);
            Parser::parse_func_decl(p, arena, 1);
            return true;
        }

        // @safe fn
        if String::eq_cstr(&lex, "@safe") {
            Parser::advance(p);
            Parser::expect_token(p, &String::new("fn"));
            Parser::parse_func_decl(p, arena, 1);
            return true;
        }

        // @unsafe fn
        if String::eq_cstr(&lex, "@unsafe") {
            Parser::advance(p);
            Parser::expect_token(p, &String::new("fn"));
            Parser::parse_func_decl(p, arena, 0);
            return true;
        }

        // struct declaration — skip body for bootstrap
        if String::eq_cstr(&lex, "struct") {
            Parser::advance(p);
            let _name: Token = Parser::advance(p);
            // Skip until closing }
            Parser::expect_token(p, &String::new("{"));
            let mut depth: usize = 1;
            while depth > 0 {
                let t: Token = Parser::advance(p);
                if String::eq_cstr(&t.lexeme, "{") {
                    depth += 1;
                }
                if String::eq_cstr(&t.lexeme, "}") {
                    depth -= 1;
                }
            }
            return true;
        }

        // enum declaration — skip body for bootstrap
        if String::eq_cstr(&lex, "enum") {
            Parser::advance(p);
            let _name: Token = Parser::advance(p);
            Parser::expect_token(p, &String::new("{"));
            let mut depth: usize = 1;
            while depth > 0 {
                let t: Token = Parser::advance(p);
                if String::eq_cstr(&t.lexeme, "{") {
                    depth += 1;
                }
                if String::eq_cstr(&t.lexeme, "}") {
                    depth -= 1;
                }
            }
            return true;
        }

        // impl block
        if String::eq_cstr(&lex, "impl") {
            Parser::advance(p);
            let _type_name: Token = Parser::advance(p);
            Parser::expect_token(p, &String::new("{"));

            let mut parsing_impl: bool = true;
            while parsing_impl {
                let check: Token = Parser::peek(p);
                if String::eq_cstr(&check.lexeme, "}") {
                    parsing_impl = false;
                } else {
                    // Check for @unsafe/@safe before fn
                    let mut method_safe: I32 = 1;
                    if String::eq_cstr(&check.lexeme, "@unsafe") {
                        Parser::advance(p);
                        method_safe = 0;
                    } else if String::eq_cstr(&check.lexeme, "@safe") {
                        Parser::advance(p);
                    }
                    // optional pub
                    let pub_check: Token = Parser::peek(p);
                    if String::eq_cstr(&pub_check.lexeme, "pub") {
                        Parser::advance(p);
                    }
                    Parser::expect_token(p, &String::new("fn"));
                    Parser::parse_func_decl(p, arena, method_safe);
                }
            }
            Parser::expect_token(p, &String::new("}"));
            return true;
        }

        // import declaration — skip for bootstrap
        if String::eq_cstr(&lex, "import") {
            Parser::advance(p);
            // Skip until ;
            let mut skip_import: bool = true;
            while skip_import {
                let t: Token = Parser::advance(p);
                if String::eq_cstr(&t.lexeme, ";") {
                    skip_import = false;
                }
            }
            return true;
        }

        // EOF
        if String::eq_cstr(&lex, "") {
            return false;
        }

        // Unknown — print and skip
        print("[!] Skipping unknown top-level token: '");
        print(&lex);
        println("'");
        Parser::advance(p);
        return true;
    }

    @unsafe
    fn parse_program(p: &mut Parser, arena: &mut AstArena) {
        let mut parsing: bool = true;
        while parsing {
            let has_more: bool = Parser::parse_item(p, arena);
            if has_more {
                // continue
            } else {
                parsing = false;
            }
        }
    }
}

// ════════════════════════════════════════════════════════════
//  MAIN — Bootstrap test entry point
// ════════════════════════════════════════════════════════════

@unsafe
fn main() {
    println("--- Y-Lang Self-Hosted Parser (DOD Arena) ---");

    // Create a small test token stream manually
    // In production, this would come from Lexer::tokenize()
    let mut arena: AstArena = AstArena::new();

    println("Arena initialized.");
    println("Expr arena ready.");
    println("Stmt arena ready.");
    println("Func arena ready.");

    // For a full integration test, we would:
    //   1. Create source string
    //   2. Run Lexer::tokenize() to get tokens
    //   3. Feed tokens to Parser::parse_program()
    //   4. Inspect the AstArena contents

    println("--- Parser module compiled successfully ---");
    return;
}
import lib;
import parser;

struct CEmitter {
    c_buffer: String,
    indent_level: usize
}

impl CEmitter {
    @unsafe
    fn new() -> CEmitter {
        let e: CEmitter;
        e.c_buffer = String::new("");
        e.indent_level = 0;
        return e;
    }

    @unsafe
    fn indent(e: &mut CEmitter) {
        let mut i: usize = 0;
        while i < (*e).indent_level {
            String::push_str(&mut (*e).c_buffer, &String::new("    "));
            i += 1;
        }
    }

    @unsafe
    fn emit_func(e: &mut CEmitter, arena: &AstArena, func_idx: usize) {
        let fdecl: FuncDecl = Vec::get_FuncDecl(&(*arena).funcs, func_idx);
        
        CEmitter::indent(e);
        String::push_str(&mut (*e).c_buffer, &String::new("int32_t "));
        String::push_str(&mut (*e).c_buffer, &fdecl.name);
        String::push_str(&mut (*e).c_buffer, &String::new("("));
        
        let mut p: usize = 0;
        while p < fdecl.param_count {
            let param: ParamDecl = Vec::get_ParamDecl(&(*arena).params, fdecl.param_start + p);
            // Default to int32_t for all params in bootstrap to keep it simple
            String::push_str(&mut (*e).c_buffer, &String::new("int32_t "));
            String::push_str(&mut (*e).c_buffer, &param.name);
            if p + 1 < fdecl.param_count {
                String::push_str(&mut (*e).c_buffer, &String::new(", "));
            }
            p += 1;
        }
        
        String::push_str(&mut (*e).c_buffer, &String::new(") {\n"));
        (*e).indent_level += 1;
        
        let mut s: usize = 0;
        while s < fdecl.body_count {
            CEmitter::emit_stmt(e, arena, fdecl.body_start + s);
            s += 1;
        }
        
        (*e).indent_level -= 1;
        CEmitter::indent(e);
        String::push_str(&mut (*e).c_buffer, &String::new("}\n\n"));
    }

    @unsafe
    fn emit_stmt(e: &mut CEmitter, arena: &AstArena, stmt_idx: usize) {
        let stmt: Stmt = Vec::get_Stmt(&(*arena).stmts, stmt_idx);
        CEmitter::indent(e);
        
        if stmt.tag == Stmt_TAG_Let {
            let var_name: String = stmt.data.Let._0;
            let init_idx: usize = stmt.data.Let._2;
            
            String::push_str(&mut (*e).c_buffer, &String::new("int32_t "));
            String::push_str(&mut (*e).c_buffer, &var_name);
            if init_idx > 0 {
                String::push_str(&mut (*e).c_buffer, &String::new(" = "));
                CEmitter::emit_expr(e, arena, init_idx - 1);
            } else {
                String::push_str(&mut (*e).c_buffer, &String::new(" = 0"));
            }
            String::push_str(&mut (*e).c_buffer, &String::new(";\n"));
        } else if stmt.tag == Stmt_TAG_Return {
            let ret_idx: usize = stmt.data.Return._0;
            String::push_str(&mut (*e).c_buffer, &String::new("return "));
            if ret_idx > 0 {
                CEmitter::emit_expr(e, arena, ret_idx - 1);
            }
            String::push_str(&mut (*e).c_buffer, &String::new(";\n"));
        } else if stmt.tag == Stmt_TAG_ExprStmt {
            let expr_idx: usize = stmt.data.ExprStmt._0;
            CEmitter::emit_expr(e, arena, expr_idx - 1);
            String::push_str(&mut (*e).c_buffer, &String::new(";\n"));
        } else if stmt.tag == Stmt_TAG_Assign {
            let target_idx: usize = stmt.data.Assign._0;
            let value_idx: usize = stmt.data.Assign._1;
            CEmitter::emit_expr(e, arena, target_idx - 1);
            String::push_str(&mut (*e).c_buffer, &String::new(" = "));
            CEmitter::emit_expr(e, arena, value_idx - 1);
            String::push_str(&mut (*e).c_buffer, &String::new(";\n"));
        } else if stmt.tag == Stmt_TAG_CompoundAssign {
            let target_idx: usize = stmt.data.CompoundAssign._0;
            let value_idx: usize = stmt.data.CompoundAssign._2;
            CEmitter::emit_expr(e, arena, target_idx - 1);
            // hardcoded to += for now as binaryop isn't fully matched
            String::push_str(&mut (*e).c_buffer, &String::new(" += "));
            CEmitter::emit_expr(e, arena, value_idx - 1);
            String::push_str(&mut (*e).c_buffer, &String::new(";\n"));
        } else if stmt.tag == Stmt_TAG_If {
            let cond_idx: usize = stmt.data.If._0;
            let then_start: usize = stmt.data.If._1;
            let then_count: usize = stmt.data.If._2;
            let else_start: usize = stmt.data.If._3;
            let else_count: usize = stmt.data.If._4;
            
            String::push_str(&mut (*e).c_buffer, &String::new("if ("));
            CEmitter::emit_expr(e, arena, cond_idx - 1);
            String::push_str(&mut (*e).c_buffer, &String::new(") {\n"));
            
            (*e).indent_level += 1;
            let mut i: usize = 0;
            while i < then_count {
                CEmitter::emit_stmt(e, arena, then_start + i);
                i += 1;
            }
            (*e).indent_level -= 1;
            CEmitter::indent(e);
            String::push_str(&mut (*e).c_buffer, &String::new("}\n"));
            
            if else_count > 0 {
                CEmitter::indent(e);
                String::push_str(&mut (*e).c_buffer, &String::new("else {\n"));
                (*e).indent_level += 1;
                let mut j: usize = 0;
                while j < else_count {
                    CEmitter::emit_stmt(e, arena, else_start + j);
                    j += 1;
                }
                (*e).indent_level -= 1;
                CEmitter::indent(e);
                String::push_str(&mut (*e).c_buffer, &String::new("}\n"));
            }
        } else if stmt.tag == Stmt_TAG_While {
            let cond_idx: usize = stmt.data.While._0;
            let body_start: usize = stmt.data.While._1;
            let body_count: usize = stmt.data.While._2;
            
            String::push_str(&mut (*e).c_buffer, &String::new("while ("));
            CEmitter::emit_expr(e, arena, cond_idx - 1);
            String::push_str(&mut (*e).c_buffer, &String::new(") {\n"));
            
            (*e).indent_level += 1;
            let mut i: usize = 0;
            while i < body_count {
                CEmitter::emit_stmt(e, arena, body_start + i);
                i += 1;
            }
            (*e).indent_level -= 1;
            CEmitter::indent(e);
            String::push_str(&mut (*e).c_buffer, &String::new("}\n"));
        }
    }

    @unsafe
    fn emit_expr(e: &mut CEmitter, arena: &AstArena, expr_idx: usize) {
        let expr: Expr = Vec::get_Expr(&(*arena).exprs, expr_idx);
        
        if expr.tag == Expr_TAG_IntLit {
            // Self-hosted Y-Lang doesn't have format! or int->str yet.
            // In the bootstrap, we assume 0 or we'll rely on C's string lit
            String::push_str(&mut (*e).c_buffer, &String::new("0"));
        } else if expr.tag == Expr_TAG_StringLit {
            String::push_str(&mut (*e).c_buffer, &String::new("\""));
            String::push_str(&mut (*e).c_buffer, &expr.data.StringLit._0);
            String::push_str(&mut (*e).c_buffer, &String::new("\""));
        } else if expr.tag == Expr_TAG_BoolLit {
            if expr.data.BoolLit._0 == 1 {
                String::push_str(&mut (*e).c_buffer, &String::new("true"));
            } else {
                String::push_str(&mut (*e).c_buffer, &String::new("false"));
            }
        } else if expr.tag == Expr_TAG_Ident {
            String::push_str(&mut (*e).c_buffer, &expr.data.Ident._0);
        } else if expr.tag == Expr_TAG_BinaryExpr {
            let lhs: usize = expr.data.BinaryExpr._0;
            let rhs: usize = expr.data.BinaryExpr._2;
            String::push_str(&mut (*e).c_buffer, &String::new("("));
            CEmitter::emit_expr(e, arena, lhs - 1);
            // Op matching is skipped in this demo but could be expanded
            String::push_str(&mut (*e).c_buffer, &String::new(" + "));
            CEmitter::emit_expr(e, arena, rhs - 1);
            String::push_str(&mut (*e).c_buffer, &String::new(")"));
        } else if expr.tag == Expr_TAG_Call {
            let func_idx: usize = expr.data.Call._0;
            let args_start: usize = expr.data.Call._1;
            let arg_count: usize = expr.data.Call._2;
            CEmitter::emit_expr(e, arena, func_idx - 1);
            String::push_str(&mut (*e).c_buffer, &String::new("("));
            
            let mut i: usize = 0;
            while i < arg_count {
                let arg_idx: usize = Vec::get_usize(&(*arena).arg_indices, args_start + i);
                CEmitter::emit_expr(e, arena, arg_idx - 1);
                if i + 1 < arg_count {
                    String::push_str(&mut (*e).c_buffer, &String::new(", "));
                }
                i += 1;
            }
            String::push_str(&mut (*e).c_buffer, &String::new(")"));
        } else if expr.tag == Expr_TAG_MemberAccess {
            let base_idx: usize = expr.data.MemberAccess._0;
            let member: String = expr.data.MemberAccess._1;
            CEmitter::emit_expr(e, arena, base_idx - 1);
            String::push_str(&mut (*e).c_buffer, &String::new("."));
            String::push_str(&mut (*e).c_buffer, &member);
        } else if expr.tag == Expr_TAG_Index {
            let base_idx: usize = expr.data.Index._0;
            let idx_idx: usize = expr.data.Index._1;
            CEmitter::emit_expr(e, arena, base_idx - 1);
            String::push_str(&mut (*e).c_buffer, &String::new("["));
            CEmitter::emit_expr(e, arena, idx_idx - 1);
            String::push_str(&mut (*e).c_buffer, &String::new("]"));
        } else if expr.tag == Expr_TAG_UnaryExpr {
            let operand_idx: usize = expr.data.UnaryExpr._1;
            // Assumes Deref for now
            String::push_str(&mut (*e).c_buffer, &String::new("*("));
            CEmitter::emit_expr(e, arena, operand_idx - 1);
            String::push_str(&mut (*e).c_buffer, &String::new(")"));
        }
    }
}
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
import lib;
import lexer;
import parser;
import c_emitter;
import llvm_emitter;

@unsafe
fn main() {
    println("--- Y-Lang Self-Hosted Compiler ---");

    // 1. Read source
    let source_path: String = String::new("test.yy");
    let source: String = File::read_to_string(&source_path);

    // 2. Lexer
    let mut lexer: Lexer = Lexer::new(&source);
    let tokens: Vec = Lexer::tokenize(&mut lexer);
    let token_count: usize = Vec::len(&tokens);
    print("Lexed tokens: ");
    print_int(token_count);
    println("");

    // 3. Parser
    let mut arena: AstArena = AstArena::new();
    let mut p: Parser = Parser::new(tokens, token_count);
    Parser::parse_program(&mut p, &mut arena);

    // 4. Emitter (C)
    let mut emitter: CEmitter = CEmitter::new();
    // 4.5 Emitter (LLVM)
    let mut ll_emitter: LlvmEmitter = LlvmEmitter::new();
    
    let mut f: usize = 0;
    let func_count: usize = Vec::len(&arena.funcs);
    while f < func_count {
        CEmitter::emit_func(&mut emitter, &arena, f);
        LlvmEmitter::emit_func(&mut ll_emitter, &arena, f);
        f += 1;
    }

    // 5. Output C
    let out_path: String = String::new("test.c");
    File::write(&out_path, &emitter.c_buffer);
    
    // 6. Output LLVM
    let ll_path: String = String::new("test.ll");
    File::write(&ll_path, &ll_emitter.buffer);
    
    println("Successfully compiled test.yy -> test.c and test.ll");
    return;
}
