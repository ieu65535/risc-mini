module reg_file (
    input clk,

    input [4:0] waddr,
    input [31:0] wdata,

    input [4:0] rs1_addr,
    input [4:0] rs2_addr,
    output reg [31:0] rs1_data,
    output reg [31:0] rs2_data
);

reg [31:0] regs [1:31];

always @(posedge clk) begin
    if (waddr!= 0) begin
        regs[waddr] <= wdata;
    end
end

always @(*) begin
    if (rs1_addr == 0) rs1_data = 0;
    else if (rs1_addr == waddr)
        rs1_data = wdata;
    else
        rs1_data = regs[rs1_addr];
end

always @(*) begin
    if (rs2_addr == 0) rs2_data = 0;
    else if (rs2_addr == waddr)
        rs2_data = wdata;
    else
        rs2_data = regs[rs2_addr];
end

endmodule