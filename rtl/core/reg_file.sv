module reg_file (
    input  logic        clk,

    input  logic [ 4:0] rd_addr,
    input  logic [31:0] rd_data,

    input  logic [ 4:0] rs1_addr,
    input  logic [ 4:0] rs2_addr,
    output logic [31:0] rs1_data,
    output logic [31:0] rs2_data
);

reg [31:0] regs [0:31];

always_ff @(posedge clk) begin
    regs[rd_addr] <= rd_data;
end

assign rs1_data = regs[rs1_addr];
assign rs2_data = regs[rs2_addr];

endmodule