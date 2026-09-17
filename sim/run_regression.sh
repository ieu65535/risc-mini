#!/usr/bin/env bash

set -u -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
timeout_seconds="${TIMEOUT_SECONDS:-15}"
log_name="regression.log"
if [[ "${1:-}" == "--all" ]]; then
    log_name="regression-all.log"
fi
regression_log="${REGRESSION_LOG:-$script_dir/$log_name}"
exec > >(tee "$regression_log") 2>&1

tests=(
    tb_control.sv
    tb_dhazards.sv
    tb_pipeline.sv
    tb_csr.sv
    tb_soc.sv
)

if [[ "${1:-}" == "--all" ]]; then
    tests+=(tb_interrupt.sv tb_perf_counters.sv tb_mtvec.sv tb_csr_fields.sv tb_halfword.sv tb_fence.sv)
fi

failures=0

for testbench in "${tests[@]}"; do
    log_file="$(mktemp)"
    test_name="${testbench%.sv}"
    printf '\n[%s]\n' "$testbench"

    timeout "$timeout_seconds" make -s -B -C "$script_dir" \
        TB_MOUDLE="$testbench" >"$log_file" 2>&1
    status=$?
    cat "$log_file"

    failed=0
    if [[ $status -eq 124 ]]; then
        printf '[REGRESSION FAIL] timeout after %ss\n' "$timeout_seconds"
        failed=1
    elif [[ $status -ne 0 ]]; then
        printf '[REGRESSION FAIL] simulator exit code %s\n' "$status"
        failed=1
    elif grep -Eq '\[FAIL\]|ERROR:|ERROR!|Errors detected' "$log_file"; then
        printf '[REGRESSION FAIL] failure marker found in output\n'
        failed=1
    elif [[ "$testbench" == "tb_soc.sv" ]] && \
         ! grep -Fq 'Hello, World!' "$log_file"; then
        printf '[REGRESSION FAIL] expected UART output not found\n'
        failed=1
    elif [[ "$testbench" == "tb_soc.sv" ]] && \
         ! grep -Fq '[TB COMPLETE] tb_soc' "$log_file"; then
        printf '[REGRESSION FAIL] SoC test did not reach normal completion\n'
        failed=1
    elif [[ "$testbench" != "tb_soc.sv" ]] && \
         ! grep -Fq "[TB PASS] $test_name" "$log_file"; then
        printf '[REGRESSION FAIL] expected testbench completion marker not found\n'
        failed=1
    else
        printf '[REGRESSION PASS]\n'
    fi

    failures=$((failures + failed))
    rm -f "$log_file"
done

printf '\nRegression summary: %s passed, %s failed\n' \
    "$((${#tests[@]} - failures))" "$failures"

if [[ $failures -ne 0 ]]; then
    exit 1
fi
