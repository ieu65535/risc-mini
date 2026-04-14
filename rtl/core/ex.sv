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
    input  logic       is_sra
);

wire [31:0] imm_I = $signed(inst[31:20]);
wire [31:0] imm_S = $signed({inst[31:25], inst[11:7]});
wire [31:0] imm_U = $signed({inst[31:12], 12'd0});

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