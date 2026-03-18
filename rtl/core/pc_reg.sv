`include "micro.vh"
module pc_reg(
    input  logic        clk,
    input  logic        rst,
    input  logic [31:0] inst,
    input  logic [31:0] alu_dout,
    input  logic        alu_cond,
    input  logic [ 1:0] pc_sel,

    output logic [31:0] inst_addr,
    output logic [31:0] pc
);

wire [31:0] imm_J = $signed({inst[31], inst[19:12], inst[20], inst[30:21], 1'b0});
wire [31:0] imm_B = $signed({inst[31], inst[7], inst[30:25], inst[11:8], 1'b0});
wire [31:0] pc_jr = {alu_dout[31:1], 1'b0};

logic [31:0] next_pc;

always_comb begin
    case (pc_sel)
        `PC_N: next_pc = pc + 4;
        `PC_J: next_pc = pc + imm_J;
        `PC_B: next_pc = alu_cond? pc + imm_B : pc + 4;
        `PC_JR: next_pc = pc_jr;
    endcase
end

assign inst_addr = next_pc;

always_ff @(posedge clk) begin
    if (rst) begin
        pc <= -4;
    end else begin
        pc <= next_pc;
    end
end

endmodule