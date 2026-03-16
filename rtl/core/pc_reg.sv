module pc_reg(
    input  logic        clk,
    input  logic        rst,
    input  logic        pc_en,
    input  logic [31:0] pc_target,

    output logic [31:0] inst_addr,
    output logic [31:0] pc
);

logic [31:0] next_pc;

always_comb begin
    if (pc_en) begin
        next_pc = pc_target;
    end
    else begin
        next_pc = pc + 4;
    end
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