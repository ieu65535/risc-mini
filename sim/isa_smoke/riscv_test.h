// Minimal M-only environment for unmodified upstream riscv-tests/isa/rv32ui sources.
// This is a local test adapter, not the upstream p environment or an ACT4 certification run.
#ifndef RISC_MINI_ISA_SMOKE_ENV_H
#define RISC_MINI_ISA_SMOKE_ENV_H

#define RVTEST_RV32U
#define RVTEST_RV64U RVTEST_RV32U
#define TESTNUM gp

#define RVTEST_CODE_BEGIN                 \
    .section .text.init,"ax",@progbits; \
    .globl _start;                       \
_start:                                  \
    li gp, 0;

// The test body uses TEST_PASSFAIL from upstream test_macros.h. The encoded
// result is written once to the last word of the 4 KiB RAM: 1=pass, odd !=1=fail.
#define RVTEST_PASS                      \
    li gp, 1;                            \
    j riscv_mini_report;

#define RVTEST_FAIL                      \
    bnez gp, 1f;                         \
    li gp, 2;                            \
1:  slli gp, gp, 1;                      \
    ori gp, gp, 1;                       \
    j riscv_mini_report;

#define RVTEST_CODE_END                  \
riscv_mini_report:                       \
    li t0, 0x20000ffc;                   \
    sw gp, 0(t0);                        \
1:  j 1b;

#define RVTEST_DATA_BEGIN
#define RVTEST_DATA_END

#endif
