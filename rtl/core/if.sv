module fetch (
    input clk,
    input rst,
    input [31:0] pc,

    output mem_addr,
    input [31:0] mem_data,

    output [31:0] inst,
    output [31:0] inst_addr
);

reg [31:0] addr_r;

always @(posedge clk) begin
    if (rst) begin
        addr_r <= 0;
    end
    else begin
        addr_r <= pc;
    end
end
assign inst_addr = addr_r;
assign mem_addr = pc;

assign inst = mem_data;

endmodule