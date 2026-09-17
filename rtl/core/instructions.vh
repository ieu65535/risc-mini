
// inst type 
`define TYPE_R 7'b0110011
`define TYPE_I 7'b0010011
`define TYPE_B 7'b1100011
`define TYPE_L 7'b0000011
`define TYPE_S 7'b0100011

`define JAL    7'b1101111
`define JALR   7'b1100111

`define LUI    7'b0110111
`define AUIPC  7'b0010111

// R and I type inst
`define ADD    3'b000
`define SLL    3'b001
`define SLT    3'b010
`define SLTU   3'b011
`define XOR    3'b100
`define SR     3'b101
`define OR     3'b110
`define AND    3'b111

// B type inst
`define BEQ    3'b000
`define BNE    3'b001
`define BLT    3'b100
`define BGE    3'b101
`define BLTU   3'b110
`define BGEU   3'b111

// L type inst
`define LB     3'b000
`define LH     3'b001
`define LW     3'b010
`define LBU    3'b100
`define LHU    3'b101

// S type inst
`define SB     3'b000
`define SH     3'b001
`define SW     3'b010


`define FENCE  7'b0001111
`define ECALL  32'h73
`define EBREAK 32'h00100073

// CSR inst
`define SYSTEM    7'b1110011
`define INST_CSRRW  3'b001
`define INST_CSRRS  3'b010
`define INST_CSRRC  3'b011
`define INST_CSRRWI 3'b101
`define INST_CSRRSI 3'b110
`define INST_CSRRCI 3'b111

// CSR reg addr
`define CSR_CYCLE   12'hc00
`define CSR_INSTRET 12'hc02
`define CSR_CYCLEH  12'hc80
`define CSR_INSTRETH 12'hc82
`define CSR_MCYCLE  12'hb00
`define CSR_MINSTRET 12'hb02
`define CSR_MCYCLEH 12'hb80
`define CSR_MINSTRETH 12'hb82
// 自定义只读 CSR（0xCC0–0xCFF）：流水线实际保持的暂停周期。
`define CSR_STALL_CYCLES  12'hcc0
`define CSR_STALL_CYCLESH 12'hcc1
`define CSR_MTVEC   12'h305
`define CSR_MCAUSE  12'h342
`define CSR_MTVAL   12'h343
`define CSR_MEPC    12'h341
`define CSR_MIE     12'h304
`define CSR_MIP     12'h344
`define CSR_MSTATUS 12'h300
`define CSR_MSCRATCH 12'h340

`define CSR_MHARTID 12'hf14
