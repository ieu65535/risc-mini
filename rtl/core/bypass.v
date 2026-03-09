module bypass (
    input [4:0] rd_addr,
    input [4:0] rs1_addr,
    input [4:0] rs2_addr,
    input [31:0] rd_data,
    input [31:0] rs1_data,
    input [31:0] rs2_data,
    output reg [31:0] douta,
    output reg [31:0] doutb
);

always @(*) begin
    if (rs1_addr == 0) douta = 0;
    else if (rs1_addr == rd_addr)
        douta = rd_data;
    else
        douta = rs1_data;
end

always @(*) begin
    if (rs2_addr == 0) doutb = 0;
    else if (rs2_addr == rd_addr)
        doutb = rd_data;
    else
        doutb = rs2_data;
end

endmodule