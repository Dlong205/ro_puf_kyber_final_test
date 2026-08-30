MEMORY
{
    BRAM (rwx) : ORIGIN = 0x00000000, LENGTH = 0x4000 /* 16KB */
}

SECTIONS
{
    .text : {
        . = ALIGN(4);
        *(.text.start) /* Startup code */
        *(.text*)      /* C code */
        *(.rodata*)    /* Read-only data */
        *(.srodata*)
        . = ALIGN(4);
    } > BRAM

    .data : {
        . = ALIGN(4);
        *(.data*)
        *(.sdata*)
        . = ALIGN(4);
    } > BRAM

    .bss : {
        . = ALIGN(4);
        _sbss = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > BRAM

    _stack_top = ORIGIN(BRAM) + LENGTH(BRAM);
}
