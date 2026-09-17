#include "riscv_test.h"

// 256 deterministic xorshift32 rounds. The final state and all 16 RAM words
// were computed independently by a host-side 32-bit model.
#define CHECK_WORD(num, offset, expected) \
    li gp, num;                          \
    lw t3, offset(s2);                   \
    li t4, expected;                     \
    bne t3, t4, fail;

RVTEST_RV32U
RVTEST_CODE_BEGIN
    li s0, 0x12345678
    li s1, 256
    la s2, words

stress_loop:
    slli t0, s0, 13
    xor  s0, s0, t0
    srli t0, s0, 17
    xor  s0, s0, t0
    slli t0, s0, 5
    xor  s0, s0, t0

    andi t1, s1, 15
    slli t1, t1, 2
    add  t2, s2, t1

    li gp, 2
    sw s0, 0(t2)
    lw t3, 0(t2)
    bne t3, s0, fail

    li gp, 3
    sw zero, 0(t2)
    sh s0, 0(t2)
    srli t4, s0, 16
    sh t4, 2(t2)
    lw t3, 0(t2)
    bne t3, s0, fail
    lh t5, 2(t2)
    srai t6, s0, 16
    bne t5, t6, fail

    li gp, 4
    sw zero, 0(t2)
    sb s0, 0(t2)
    srli t4, s0, 8
    sb t4, 1(t2)
    srli t4, s0, 16
    sb t4, 2(t2)
    srli t4, s0, 24
    sb t4, 3(t2)
    lw t3, 0(t2)
    bne t3, s0, fail

    li gp, 5
    lb t5, 3(t2)
    srai t6, s0, 24
    bne t5, t6, fail

    addi s1, s1, -1
    bnez s1, stress_loop

    li gp, 6
    li t0, 0x0a872ce9
    bne s0, t0, fail

    CHECK_WORD( 7,  0, 0x669be252)
    CHECK_WORD( 8,  4, 0x0a872ce9)
    CHECK_WORD( 9,  8, 0x7a4fb3d3)
    CHECK_WORD(10, 12, 0xf7e3c264)
    CHECK_WORD(11, 16, 0xd082db14)
    CHECK_WORD(12, 20, 0x6dba962b)
    CHECK_WORD(13, 24, 0x2c0d18c1)
    CHECK_WORD(14, 28, 0x129a493f)
    CHECK_WORD(15, 32, 0x6dda6213)
    CHECK_WORD(16, 36, 0x303bc8e0)
    CHECK_WORD(17, 40, 0xffac6de8)
    CHECK_WORD(18, 44, 0xa1c11119)
    CHECK_WORD(19, 48, 0x9b176d64)
    CHECK_WORD(20, 52, 0x4e4a17ba)
    CHECK_WORD(21, 56, 0xf486fd6f)
    CHECK_WORD(22, 60, 0x40e4487a)

    RVTEST_PASS

fail:
    RVTEST_FAIL

RVTEST_CODE_END

    .data
RVTEST_DATA_BEGIN
words:
    .rept 16
    .word 0
    .endr
RVTEST_DATA_END
