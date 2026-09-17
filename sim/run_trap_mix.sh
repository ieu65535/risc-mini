#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for tool in riscv64-unknown-elf-gcc riscv64-unknown-elf-objcopy iverilog vvp od; do
    command -v "$tool" >/dev/null || { echo "[TRAP ERROR] missing $tool" >&2; exit 1; }
done

run_dir="$(mktemp -d -t risc-mini-trap-XXXXXXXX)"
cleanup() {
    case "$run_dir" in
        /tmp/risc-mini-trap-*) rm -rf -- "$run_dir" ;;
        *) echo "[TRAP ERROR] refusing to remove unexpected path: $run_dir" >&2 ;;
    esac
}
trap cleanup EXIT

elf="$run_dir/trap_mix.elf"
rom_bin="$run_dir/trap_mix.bin"
rom_hex="$run_dir/trap_mix.hex"
data_bin="$run_dir/trap_mix.data.bin"
data_hex="$run_dir/trap_mix.data.hex"
riscv64-unknown-elf-gcc -march=rv32i_zicsr -mabi=ilp32 \
    -nostdlib -nostartfiles -static -Wl,--no-relax -Wl,--build-id=none \
    -I "$repo_root/sim/isa_smoke" -T "$repo_root/sim/isa_smoke/link.ld" \
    "$repo_root/sim/isa_smoke/trap_mix.S" -o "$elf"
riscv64-unknown-elf-objcopy -O binary -j .text.init "$elf" "$rom_bin"
riscv64-unknown-elf-objcopy -O binary -j .data "$elf" "$data_bin"
rom_bytes="$(wc -c < "$rom_bin")"
data_bytes="$(wc -c < "$data_bin")"
if (( rom_bytes == 0 || rom_bytes > 4096 || rom_bytes % 4 != 0 ||
      data_bytes != 24 )); then
    echo "[TRAP ERROR] invalid image sizes ROM=$rom_bytes DATA=$data_bytes" >&2
    exit 1
fi
od -An -v -tx4 -w4 "$rom_bin" > "$rom_hex"
od -An -v -tx4 -w4 "$data_bin" > "$data_hex"

rtl_files=("$repo_root"/rtl/*.sv "$repo_root"/rtl/core/*.sv "$repo_root"/rtl/peripherals/*.sv)
iverilog -g2005-sv -I "$repo_root/rtl" -I "$repo_root/rtl/core" \
    -s tb_trap_mix -o "$run_dir/tb_trap_mix.vvp" \
    "$repo_root/sim/tb_trap_mix.sv" "${rtl_files[@]}"
seeds=(2468ace0 13579bdf deadbeef 0badc0de)
for seed in "${seeds[@]}"; do
    vvp "$run_dir/tb_trap_mix.vvp" "+ROM=$rom_hex" "+DATA=$data_hex" \
        "+WORDS=$((rom_bytes / 4))" "+DATA_WORDS=$((data_bytes / 4))" \
        "+SEED=$seed"
done
printf '[TRAP MIX PASS] %s pulse-timing seeds\n' "${#seeds[@]}"
