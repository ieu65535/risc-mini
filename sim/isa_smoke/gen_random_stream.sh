#!/usr/bin/env bash
set -euo pipefail

if (( $# != 3 )) || [[ ! "$1" =~ ^0[xX][0-9a-fA-F]{1,8}$ ]]; then
    echo 'usage: gen_random_stream.sh <32-bit-hex-seed> <assembly-path> <expected-hex-path>' >&2
    exit 1
fi

seed="$1"
assembly_path="$2"
expected_path="$3"
rng=$((seed))
state=$rng
other=$((0x9e3779b9))
declare -a op_counts=()

next_random() {
    rng=$(((rng * 1664525 + 1013904223) & 0xffffffff))
}

{
    printf '#include "riscv_test.h"\nRVTEST_RV32U\nRVTEST_CODE_BEGIN\n'
    printf '    li s0, 0x%08x\n    li s1, 0x%08x\n    la s2, result_word\n' "$state" "$other"

    for ((step = 0; step < 96; step++)); do
        next_random
        op=$(((rng >> 16) % 10))
        op_counts[$op]=$((${op_counts[$op]:-0} + 1))
        next_random
        imm=$(((rng & 0x7ff) - 1024))
        shift=$((rng & 31))

        case "$op" in
            0)
                printf '    addi s0, s0, %d\n' "$imm"
                state=$(((state + imm) & 0xffffffff)) ;;
            1)
                printf '    xori s0, s0, %d\n' "$imm"
                state=$(((state ^ imm) & 0xffffffff)) ;;
            2)
                printf '    andi s0, s0, %d\n' "$imm"
                state=$(((state & imm) & 0xffffffff)) ;;
            3)
                printf '    ori s0, s0, %d\n' "$imm"
                state=$(((state | imm) & 0xffffffff)) ;;
            4)
                printf '    slli s0, s0, %d\n' "$shift"
                state=$(((state << shift) & 0xffffffff)) ;;
            5)
                printf '    srli s0, s0, %d\n' "$shift"
                state=$((state >> shift)) ;;
            6)
                printf '    srai s0, s0, %d\n' "$shift"
                signed_state=$state
                if (( state & 0x80000000 )); then
                    signed_state=$((state - 0x100000000))
                fi
                state=$(((signed_state >> shift) & 0xffffffff)) ;;
            7)
                printf '    add s0, s0, s1\n'
                state=$(((state + other) & 0xffffffff)) ;;
            8)
                printf '    sub s0, s0, s1\n'
                state=$(((state - other) & 0xffffffff)) ;;
            9)
                printf '    xor s0, s0, s1\n'
                state=$(((state ^ other) & 0xffffffff)) ;;
        esac

        if (( (step + 1) % 8 == 0 )); then
            checkpoint=$(((step + 1) / 8))
            printf '    li gp, %d\n' "$((checkpoint + 1))"
            printf '    sw s0, 0(s2)\n    lw t0, 0(s2)\n'
            printf '    bne t0, s0, fail\n    beq t0, s0, checkpoint_%d\n' "$checkpoint"
            printf '    j fail\ncheckpoint_%d:\n' "$checkpoint"
        fi
    done

    printf '    sw s0, 0(s2)\n    RVTEST_PASS\nfail:\n    RVTEST_FAIL\n'
    printf 'RVTEST_CODE_END\n    .data\nRVTEST_DATA_BEGIN\n'
    printf 'result_word:\n    .word 0\nRVTEST_DATA_END\n'
} > "$assembly_path"

for ((op = 0; op < 10; op++)); do
    if (( ${op_counts[$op]:-0} == 0 )); then
        echo "[ISA ERROR] seed $seed omitted operation class $op" >&2
        exit 1
    fi
done

printf '%08x\n' "$state" > "$expected_path"
