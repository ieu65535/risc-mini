`include "micro.vh"
module ctrl(
    input  logic [ 4:0] rs1_addr,
    input  logic [ 4:0] rs2_addr,
    input  logic [ 4:0] rd_addr_ex,
    input  logic [ 1:0] wb_sel_ex,
    input  logic [ 1:0] pc_sel_ex,
    input  logic        alu_cond,
    input  logic [31:0] alu_dout,
    input  logic [31:0] pc_ex,
    output logic        stall,
    output logic        pc_mis,
    output logic [31:0] target_pc
);

assign stall = (wb_sel_ex == `WB_MEM) && (rd_addr_ex != 5'b0) && ((rs1_addr == rd_addr_ex) || (rs2_addr == rd_addr_ex));

always_comb begin
    pc_mis = 0;
    case (pc_sel_ex)
        `PC_N: pc_mis = 0;
        `PC_J: pc_mis = 0;
        `PC_B: pc_mis = !alu_cond;
        `PC_JR: pc_mis = 1;
        default: pc_mis = 1'b0;
    endcase
end

wire [31:0] jr_addr = {alu_dout[31:1], 1'b0};
always_comb begin
    target_pc = 0;
    case (pc_sel_ex)
        `PC_N: target_pc = 0;
        `PC_J: target_pc = 0;
        `PC_B: target_pc = pc_ex + 4;
        `PC_JR: target_pc = jr_addr;
        default: target_pc = 0;
    endcase
end

endmodule