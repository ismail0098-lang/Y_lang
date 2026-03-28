; ysu_boot.asm - The Genesis for MSYS2/Windows
section .multiboot
align 4
    dd 0x1BADB002             ; Magic number for Multiboot
    dd 0x00                   ; Flags
    dd - (0x1BADB002 + 0x00)  ; Checksum

section .text
global _start
extern _ysu_main              ; MSYS2 GCC adds an underscore to C symbols

_start:
    ; The Pulse: Jumping from Assembly to C
    call _ysu_main            
    
    ; The Shield: If the kernel returns, halt the CPU
    cli                       
.halt:
    hlt
    jmp .halt