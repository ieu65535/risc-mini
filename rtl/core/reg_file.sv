module reg_file (
    input clk,

    input [4:0] rd_addr,
    input [31:0] rd_data,

    input [4:0] rs1_addr,
    input [4:0] rs2_addr,
    output reg [31:0] rs1_data,
    output reg [31:0] rs2_data
);

reg [31:0] regs [0:31];

always_ff @(posedge clk) begin
    regs[rd_addr] <= rd_data;
end

always @(*) begin
    if (rs1_addr == 0)
        rs1_data = 0;
    else 
        rs1_data = regs[rs1_addr];
end

always @(*) begin
    if (rs2_addr == 0)
        rs2_data = 0;
    else
        rs2_data = regs[rs2_addr];
end

endmodule