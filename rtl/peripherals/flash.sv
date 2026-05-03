`include "../config.vh"
module flash(
    input clk,
    input [31:0] inst_addr,
    output reg [31:0] inst_dout,
    
    input [31:0] flash_addr,
    output reg [31:0] flash_dout
);

localparam WIDTH = 12;
reg [31:0] flash [0:(1<<WIDTH)-1];

always @(posedge clk) begin
    inst_dout <= flash[inst_addr[WIDTH+1:2]];
end

always @(posedge clk) begin
    flash_dout <= flash[flash_addr[WIDTH+1:2]];
end

initial begin
	`ifdef XILINX_SIMULATOR
        $readmemh("risc-mini.mem", flash);//在这里加载指令
    `else
        $readmemh("../src/risc-mini.mem", flash);
    `endif
end

endmodule