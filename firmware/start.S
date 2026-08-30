.section .text.start
.global _start

_start:
    /* Setup stack pointer */
    lui sp, %hi(_stack_top)
    addi sp, sp, %lo(_stack_top)

    /* Clear BSS */
    lui a0, %hi(_sbss)
    addi a0, a0, %lo(_sbss)
    lui a1, %hi(_ebss)
    addi a1, a1, %lo(_ebss)
    bge a0, a1, end_clear_bss
clear_bss:
    sw zero, 0(a0)
    addi a0, a0, 4
    blt a0, a1, clear_bss
end_clear_bss:

    /* Jump to main */
    call main

    /* Trap on return from main */
trap:
    j trap
