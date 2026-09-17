#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
upstream_url="https://github.com/riscv-software-src/riscv-tests.git"
upstream_commit="2ebecad997fa58cd9e5724340ba75aa4b59bd1d0"
tests=(
    simple add addi and andi auipc
    beq bge bgeu blt bltu bne
    jal jalr lui or ori
    sll slli slt slti sltiu sltu
    sra srai srl srli sub xor xori
    lb lbu lh lhu lw sb sh sw ld_st st_ld
)

for tool in git riscv64-unknown-elf-gcc riscv64-unknown-elf-objcopy iverilog vvp od; do
    command -v "$tool" >/dev/null || { echo "[ISA ERROR] missing $tool" >&2; exit 1; }
done

run_dir="$(mktemp -d -t risc-mini-isa-XXXXXXXX)"
cleanup() {
    case "$run_dir" in
        /tmp/risc-mini-isa-*) rm -rf -- "$run_dir" ;;
        *) echo "[ISA ERROR] refusing to remove unexpected temporary path: $run_dir" >&2 ;;
    esac
}
trap cleanup EXIT

if [[ -n "${RISCV_TESTS_DIR:-}" ]]; then
    upstream="$(cd "$RISCV_TESTS_DIR" && pwd)"
else
    upstream="$run_dir/upstream"
    git init -q "$upstream"
    git -C "$upstream" remote add origin "$upstream_url"
    git -C "$upstream" fetch -q --depth 1 origin "$upstream_commit"
    git -C "$upstream" checkout -q --detach FETCH_HEAD
fi

actual_commit="$(git -C "$upstream" rev-parse HEAD)"
if [[ "$actual_commit" != "$upstream_commit" ]]; then
    echo "[ISA ERROR] upstream commit $actual_commit != pinned $upstream_commit" >&2
    exit 1
fi

rtl_files=("$repo_root"/rtl/*.sv "$repo_root"/rtl/core/*.sv "$repo_root"/rtl/peripherals/*.sv)
iverilog -g2005-sv -I "$repo_root/rtl" -I "$repo_root/rtl/core" \
    -s tb_isa_smoke -o "$run_dir/tb_isa_smoke.vvp" \
    "$repo_root/sim/tb_isa_smoke.sv" "${rtl_files[@]}"

for test in "${tests[@]}"; do
    elf="$run_dir/$test.elf"
    bin="$run_dir/$test.bin"
    hex="$run_dir/$test.hex"
    data_bin="$run_dir/$test.data.bin"
    data_hex="$run_dir/$test.data.hex"
    riscv64-unknown-elf-gcc -march=rv32i_zicsr -mabi=ilp32 \
        -nostdlib -nostartfiles -static -Wl,--no-relax -Wl,--build-id=none \
        -I "$repo_root/sim/isa_smoke" -I "$upstream/isa/macros/scalar" \
        -T "$repo_root/sim/isa_smoke/link.ld" \
        "$upstream/isa/rv32ui/$test.S" -o "$elf"
    riscv64-unknown-elf-objcopy -O binary -j .text.init "$elf" "$bin"
    bytes="$(wc -c < "$bin")"
    if (( bytes == 0 || bytes > 4096 || bytes % 4 != 0 )); then
        echo "[ISA ERROR] $test ROM size $bytes is not a nonempty 4-byte-aligned image <= 4 KiB" >&2
        exit 1
    fi
    od -An -v -tx4 -w4 "$bin" > "$hex"
    riscv64-unknown-elf-objcopy -O binary -j .data "$elf" "$data_bin"
    data_bytes="$(wc -c < "$data_bin")"
    if (( data_bytes > 4092 )); then
        echo "[ISA ERROR] $test data size $data_bytes overlaps the result word" >&2
        exit 1
    fi
    data_words=$(((data_bytes + 3) / 4))
    if (( data_words > 0 )); then
        od -An -v -tx4 -w4 "$data_bin" > "$data_hex"
    fi
    vvp "$run_dir/tb_isa_smoke.vvp" "+ROM=$hex" "+TEST=$test" \
        "+WORDS=$((bytes / 4))" "+DATA=$data_hex" "+DATA_WORDS=$data_words"
done

stress_elf="$run_dir/long_mem_stress.elf"
stress_bin="$run_dir/long_mem_stress.bin"
stress_hex="$run_dir/long_mem_stress.hex"
stress_data_bin="$run_dir/long_mem_stress.data.bin"
stress_data_hex="$run_dir/long_mem_stress.data.hex"
stress_expected_hex="$run_dir/long_mem_stress.expected.hex"
riscv64-unknown-elf-gcc -march=rv32i_zicsr -mabi=ilp32 \
    -nostdlib -nostartfiles -static -Wl,--no-relax -Wl,--build-id=none \
    -I "$repo_root/sim/isa_smoke" -T "$repo_root/sim/isa_smoke/link.ld" \
    "$repo_root/sim/isa_smoke/long_mem_stress.S" -o "$stress_elf"
riscv64-unknown-elf-objcopy -O binary -j .text.init "$stress_elf" "$stress_bin"
stress_bytes="$(wc -c < "$stress_bin")"
if (( stress_bytes == 0 || stress_bytes > 4096 || stress_bytes % 4 != 0 )); then
    echo "[ISA ERROR] stress ROM size $stress_bytes is invalid" >&2
    exit 1
fi
od -An -v -tx4 -w4 "$stress_bin" > "$stress_hex"
riscv64-unknown-elf-objcopy -O binary -j .data "$stress_elf" "$stress_data_bin"
stress_data_bytes="$(wc -c < "$stress_data_bin")"
if (( stress_data_bytes != 64 )); then
    echo "[ISA ERROR] stress data size $stress_data_bytes != 64" >&2
    exit 1
fi
od -An -v -tx4 -w4 "$stress_data_bin" > "$stress_data_hex"

# Host-side 32-bit xorshift32 oracle, separate from CPU execution.
state=$((0x12345678))
declare -a expected=()
for ((round = 256; round > 0; round--)); do
    state=$(((state ^ (state << 13)) & 0xffffffff))
    state=$(((state ^ (state >> 17)) & 0xffffffff))
    state=$(((state ^ (state << 5)) & 0xffffffff))
    index=$((round & 15))
    expected[$index]="$state"
done
if (( state != 0x0a872ce9 )); then
    echo '[ISA ERROR] host stress oracle disagrees with fixed final-state constant' >&2
    exit 1
fi
{
    for ((index = 0; index < 16; index++)); do
        printf '%08x\n' "${expected[$index]}"
    done
} > "$stress_expected_hex"
vvp "$run_dir/tb_isa_smoke.vvp" "+ROM=$stress_hex" "+TEST=long_mem_stress" \
    "+WORDS=$((stress_bytes / 4))" "+DATA=$stress_data_hex" "+DATA_WORDS=16" \
    "+EXPECTED_RAM=$stress_expected_hex" "+EXPECTED_WORDS=16" "+MAX_CYCLES=50000"
echo '[ISA STRESS PASS] 256 seeded rounds, 16 final RAM words checked by host oracle'

random_seeds=(0x13579bdf 0x2468ace0 0xdeadbeef 0x0badc0de)
for seed in "${random_seeds[@]}"; do
    name="random_${seed#0x}"
    random_asm="$run_dir/$name.S"
    random_elf="$run_dir/$name.elf"
    random_bin="$run_dir/$name.bin"
    random_hex="$run_dir/$name.hex"
    random_data_bin="$run_dir/$name.data.bin"
    random_data_hex="$run_dir/$name.data.hex"
    random_expected_hex="$run_dir/$name.expected.hex"
    bash "$repo_root/sim/isa_smoke/gen_random_stream.sh" \
        "$seed" "$random_asm" "$random_expected_hex"
    riscv64-unknown-elf-gcc -march=rv32i_zicsr -mabi=ilp32 \
        -nostdlib -nostartfiles -static -Wl,--no-relax -Wl,--build-id=none \
        -I "$repo_root/sim/isa_smoke" -T "$repo_root/sim/isa_smoke/link.ld" \
        "$random_asm" -o "$random_elf"
    riscv64-unknown-elf-objcopy -O binary -j .text.init "$random_elf" "$random_bin"
    random_bytes="$(wc -c < "$random_bin")"
    if (( random_bytes == 0 || random_bytes > 4096 || random_bytes % 4 != 0 )); then
        echo "[ISA ERROR] $name ROM size $random_bytes is invalid" >&2
        exit 1
    fi
    od -An -v -tx4 -w4 "$random_bin" > "$random_hex"
    riscv64-unknown-elf-objcopy -O binary -j .data "$random_elf" "$random_data_bin"
    random_data_bytes="$(wc -c < "$random_data_bin")"
    if (( random_data_bytes != 4 )); then
        echo "[ISA ERROR] $name data size $random_data_bytes != 4" >&2
        exit 1
    fi
    od -An -v -tx4 -w4 "$random_data_bin" > "$random_data_hex"
    vvp "$run_dir/tb_isa_smoke.vvp" "+ROM=$random_hex" "+TEST=$name" \
        "+WORDS=$((random_bytes / 4))" "+DATA=$random_data_hex" "+DATA_WORDS=1" \
        "+EXPECTED_RAM=$random_expected_hex" "+EXPECTED_WORDS=1"
done
printf '[ISA RANDOM PASS] %s reproducible seeds x 96 generated instructions\n' \
    "${#random_seeds[@]}"

printf '00000001\n' > "$run_dir/wrong.expected.hex"
simple_bytes="$(wc -c < "$run_dir/simple.bin")"
if vvp "$run_dir/tb_isa_smoke.vvp" "+ROM=$run_dir/simple.hex" "+TEST=wrong_oracle" \
    "+WORDS=$((simple_bytes / 4))" "+DATA_WORDS=0" \
    "+EXPECTED_RAM=$run_dir/wrong.expected.hex" "+EXPECTED_WORDS=1" \
    > "$run_dir/wrong_oracle.log" 2>&1; then
    echo '[ISA ERROR] intentional wrong RAM oracle was incorrectly accepted' >&2
    exit 1
fi
if ! grep -Fq '[ISA FAIL] wrong_oracle RAM[0]=00000000 expected=00000001' \
    "$run_dir/wrong_oracle.log"; then
    echo '[ISA ERROR] wrong RAM oracle did not produce its expected failure' >&2
    sed -n '1,30p' "$run_dir/wrong_oracle.log" >&2
    exit 1
fi
echo '[ISA HARNESS PASS] intentional wrong RAM oracle rejected'

probe_elf="$run_dir/fail_probe.elf"
probe_bin="$run_dir/fail_probe.bin"
probe_hex="$run_dir/fail_probe.hex"
riscv64-unknown-elf-gcc -march=rv32i_zicsr -mabi=ilp32 \
    -nostdlib -nostartfiles -static -Wl,--no-relax -Wl,--build-id=none \
    -I "$repo_root/sim/isa_smoke" -T "$repo_root/sim/isa_smoke/link.ld" \
    "$repo_root/sim/isa_smoke/fail_probe.S" -o "$probe_elf"
riscv64-unknown-elf-objcopy -O binary -j .text.init "$probe_elf" "$probe_bin"
probe_bytes="$(wc -c < "$probe_bin")"
od -An -v -tx4 -w4 "$probe_bin" > "$probe_hex"
if vvp "$run_dir/tb_isa_smoke.vvp" "+ROM=$probe_hex" "+TEST=fail_probe" \
    "+WORDS=$((probe_bytes / 4))" "+DATA_WORDS=0" > "$run_dir/fail_probe.log" 2>&1; then
    echo '[ISA ERROR] intentional failing probe was incorrectly accepted' >&2
    exit 1
fi
if ! grep -Fq '[ISA FAIL] fail_probe upstream subtest encoded failure=0000000f' \
    "$run_dir/fail_probe.log"; then
    echo '[ISA ERROR] failing probe did not report its expected encoded failure' >&2
    sed -n '1,30p' "$run_dir/fail_probe.log" >&2
    exit 1
fi
echo '[ISA HARNESS PASS] intentional failure returned nonzero with subtest code 7'

printf '[ISA SMOKE PASS] %s upstream RV32UI tests at %s\n' "${#tests[@]}" "$upstream_commit"
