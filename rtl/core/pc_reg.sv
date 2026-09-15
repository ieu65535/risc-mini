`include "micro.vh"
module pc_reg(
    input  logic        clk,
    input  logic        rst,
    input  logic        stall,
    
    input  logic [31:0] inst,
    input  logic        pc_mis,
    input  logic [31:0] target_pc,
    input  logic [ 1:0] pc_sel,

    output logic [31:0] inst_addr,
    output logic [31:0] pc
);

wire [31:0] imm_J = $signed({inst[31], inst[19:12], inst[20], inst[30:21], 1'b0});
wire [31:0] imm_B = $signed({inst[31], inst[7], inst[30:25], inst[11:8], 1'b0});

logic [31:0] pred_pc;

always_comb begin
    case (pc_sel)
        `PC_N: pred_pc = pc + 4;
        `PC_J: pred_pc = pc + imm_J;
        `PC_B: pred_pc = pc + imm_B;
        `PC_JR: pred_pc = pc + 4;
    endcase
end

logic [31:0] next_pc;

always_comb begin
    // 重定向必须高于普通暂停，否则 Trap 与 load-use stall 同周期发生时
    // CSR 会记录 Trap，但 PC 会被锁住并丢失唯一一次 mtvec 跳转。
    if (pc_mis)
        next_pc = target_pc;
    else if (stall)
        next_pc = pc;
    else
        next_pc = pred_pc;
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
