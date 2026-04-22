/* linker.ld - The Memory Map for YSU OS */
ENTRY(_start)                /* Tells the linker the entry point is in boot.asm */

SECTIONS
{
    /* We start putting code at 1MB (0x100000) */
    /* This is a standard "Safe Zone" for Multiboot kernels */
    . = 1M;

    /* First: The executable code */
    .text BLOCK(4K) : ALIGN(4K)
    {
        *(.multiboot)       /* Ensure the Multiboot header is at the very top */
        *(.text)            /* Then all other code */
    }

    /* Second: Read-only data (like your "YSU OS" string) */
    .rodata BLOCK(4K) : ALIGN(4K)
    {
        *(.rodata)
    }

    /* Third: Initialized data */
    .data BLOCK(4K) : ALIGN(4K)
    {
        *(.data)
    }

    /* Fourth: Uninitialized data (Stack and heap space) */
    .bss BLOCK(4K) : ALIGN(4K)
    {
        *(COMMON)
        *(.bss)
    }
}
