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
logic [31:0] id_inst_reg;

always_comb begin
    if (stall) begin
        next_pc = pc;
    end
    else begin
        if (pc_mis)
            next_pc = target_pc;
        else
            next_pc = pred_pc;
    end
end

//assign inst_addr = next_pc;
assign inst_addr = fetch_pc;

always_ff @(posedge clk) begin
    if (rst) begin
        pc <= -4;
    end else begin
        pc <= next_pc;
    end
    id_inst_reg <= mem_inst;
end

endmodule