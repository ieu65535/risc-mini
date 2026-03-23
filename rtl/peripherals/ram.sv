module ram(
    input clk,
    input [31:0] addr,
    input [31:0] din,
    input [3:0] we,
    output reg [31:0] dout
);

localparam WIDTH = 10;
reg [31:0] ram [0:(1<<WIDTH)-1];

always @(posedge clk) begin
    dout <= ram[addr[WIDTH+1:2]];
end

always @(posedge clk) begin
    if (we[0]) ram[addr[WIDTH+1:2]][ 7: 0] <= din[ 7: 0];
    if (we[1]) ram[addr[WIDTH+1:2]][15: 8] <= din[15: 8];
    if (we[2]) ram[addr[WIDTH+1:2]][23:16] <= din[23:16];
    if (we[3]) ram[addr[WIDTH+1:2]][31:24] <= din[31:24];
end

endmodule