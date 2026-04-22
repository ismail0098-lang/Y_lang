# Y Compiler
Y-Lang is a systems programming language and self-hosted compiler infrastructure. Initially designed to support the YSU-Engine (a secure OS and GPU kernel engine), Y-Lang is evolving into a full-featured, general-purpose systems language.
## Features
- **Multi-Backend Emitters:**
  - **LLVM IR (`llvm_emitter.rs`):** Direct translation of the Y-Lang AST into SSA-form LLVM IR.
  - **C Backend (`c_emitter.rs`):** Generates C code for broad platform compatibility. (doesnt work at the moment)
  - **Hardware Targets (`ptx_emitter.rs`, `cpu_emitter.rs`):** Built-in targeting for GPUs (Ada Lovelace, Hopper) and CPU fallbacks.
- **Data-Oriented Design:** The parser and AST are built with performance and memory safety in mind.
- **Self-Hosting Objective:** The ultimate goal of the project is to rewrite the Rust-based compiler modules into Y-Lang itself (`.yy` files) to close the compilation loop.
## Project Structure
- `lexer.rs` & `parser.rs`: Source code tokenization and AST generation.
- `ast.rs`: Abstract Syntax Tree definitions, handling everything from structs and enums to hardware-specific cache policies.
- `type_checker.rs`: Semantic analysis, variable scoping, and type inference.
- `llvm_emitter.rs`: The LLVM Intermediate Representation backend.
- `*.yy`: Y-Lang source files (e.g., testing self-hosted parser logic).
## Building
To compile the Y-Lang bootstrap compiler using Rust:
```bash
# If using Cargo
cargo build
# If compiling directly via rustc
rustc main.rs --edition 2021
