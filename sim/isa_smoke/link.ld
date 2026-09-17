OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
    . = 0x00000000;
    .text.init : { *(.text.init) *(.text .text.*) }
    . = 0x20000000;
    .data : { *(.data .data.*) *(.sdata .sdata.*) }
    .bss : { *(.bss .bss.*) *(COMMON) }
    ASSERT(. <= 0x20000ffc, "ISA test data overlaps result word")
}
