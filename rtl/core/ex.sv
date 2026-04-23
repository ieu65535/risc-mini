`include "instructions.vh"
`include "micro.vh"
`include "../config.vh"

module ex(
    input  logic [31:0] pc,
    input  logic [31:0] inst,

    output logic [31:0] alu_dout,
    output logic        alu_cond,

    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,

    input  logic [1:0] op1_sel,
    input  logic [1:0] op2_sel,
    input  logic [2:0] alu_ctrl,
    input  logic       is_sub,
    input  logic       is_sra,

    input  logic [31:0] csr_rdata, // 从 CSR 文件读出的旧数据
    output logic [31:0] csr_wdata  // 计算后要写入 CSR 的新数据
);

wire [31:0] imm_I = $signed(inst[31:20]);
wire [31:0] imm_S = $signed({inst[31:25], inst[11:7]});
wire [31:0] imm_U = $signed({inst[31:12], 12'd0});

// CSR 指令处理
wire [2:0] csr_funct3 = inst[14:12];
// 如果 inst[14] 为 1，操作数是 5位立即数 (Zero-extended)；否则是 rs1_data
wire [31:0] csr_op_data = inst[14] ? {27'b0, inst[19:15]} : rs1_data;

logic [31:0] alu_dina;
logic [31:0] alu_dinb;

always_comb begin
    case (op1_sel)
        `OP1_RS1: alu_dina = rs1_data;
        `OP1_IMU: alu_dina = imm_U;
        default: alu_dina = rs1_data;
    endcase
end

always_comb begin
    case (op2_sel)
        `OP2_RS2: alu_dinb = rs2_data;
        `OP2_IMI: alu_dinb = imm_I;
        `OP2_IMS: alu_dinb = imm_S;
        `OP2_PC:  alu_dinb = pc;
    endcase
end

always@(*) begin
    csr_wdata = csr_rdata; // 默认保持不变
    case (csr_funct3[1:0]) // 看 funct3 的低两位
        2'b01: csr_wdata = csr_op_data;                 // CSRRW: 直接写入
        2'b10: csr_wdata = csr_rdata | csr_op_data;     // CSRRS: 置位 (OR)
        2'b11: csr_wdata = csr_rdata & (~csr_op_data);  // CSRRC: 清零 (AND NOT)
    endcase
end

alu u_alu(
    .dina   (alu_dina   ),
    .dinb   (alu_dinb   ),
    .funct3 (alu_ctrl ),
    .is_sub (is_sub ),
    .is_sra (is_sra ),
    .cond   (alu_cond   ),
    .dout   (alu_dout   )
);

endmodule