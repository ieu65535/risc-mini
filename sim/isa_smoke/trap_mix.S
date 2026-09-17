#include "riscv_test.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
    la s1, counter
    la s2, timer_count
    la s3, ecall_count
    la s5, handler_scratch
    la t0, handler
    csrw mtvec, t0
    li t0, 0x80
    csrs mie, t0
    li t0, 0x08
    csrs mstatus, t0

    li s0, 64
main_loop:
    lw s4, 0(s1)
    addi s4, s4, 1
    sw s4, 0(s1)
    andi t0, s0, 7
    bnez t0, no_ecall
    ecall
no_ecall:
    addi s0, s0, -1
    bnez s0, main_loop

wait_for_timers:
    lw t0, 0(s2)
    li t1, 18
    bne t0, t1, wait_for_timers
    lw t0, 0(s1)
    li t1, 64
    bne t0, t1, fail
    lw t0, 0(s3)
    li t1, 8
    bne t0, t1, fail
    RVTEST_PASS

fail:
    li gp, 23
    RVTEST_FAIL

// MIE is automatically cleared on Trap entry; save every temporary used here.
handler:
    sw t0,  0(s5)
    sw t1,  4(s5)
    sw t2,  8(s5)
    csrr t0, mcause
    blt t0, zero, handle_timer

    li t1, 11
    bne t0, t1, fail
    lw t1, 0(s3)
    addi t1, t1, 1
    sw t1, 0(s3)
    csrr t2, mepc
    addi t2, t2, 4
    csrw mepc, t2
    j handler_return

handle_timer:
    li t1, 0x80000007
    bne t0, t1, fail
    lw t1, 0(s2)
    addi t1, t1, 1
    sw t1, 0(s2)

handler_return:
    lw t0,  0(s5)
    lw t1,  4(s5)
    lw t2,  8(s5)
    mret
RVTEST_CODE_END

    .data
RVTEST_DATA_BEGIN
counter:         .word 0
timer_count:     .word 0
ecall_count:     .word 0
handler_scratch: .word 0, 0, 0
RVTEST_DATA_END
