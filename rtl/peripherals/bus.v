module bus(
    input clk,
    input rst,
    input [31:0] inst_addr,
    output reg [31:0] inst,
    
    input [31:0] mem_addr,
    input [31:0] mem_din,
    input [ 3:0] mem_we,
    output reg [31:0] mem_dout
);

localparam WIDTH = 12;
// flash
reg [31:0] flash [0:(1<<WIDTH)-1];
reg [31:0] flash_dout;

always @(posedge clk) begin
    inst <= flash[inst_addr[WIDTH+1:2]];
end

always @(posedge clk) begin
    flash_dout <= flash[mem_addr[WIDTH+1:2]];
end

// ram
reg [31:0] ram [0:(1<<WIDTH)-1];
reg [31:0] ram_dout;
reg [ 3:0] ram_we;

always @(posedge clk) begin
    ram_dout <= ram[mem_addr[WIDTH+1:2]];
end

always @(posedge clk) begin
    ram[mem_addr[WIDTH+1:2]][ 7: 0] <= ram_we[0] ? mem_din[ 7: 0] : ram[mem_addr[WIDTH+1:2]][ 7: 0];
    ram[mem_addr[WIDTH+1:2]][15: 8] <= ram_we[1] ? mem_din[15: 8] : ram[mem_addr[WIDTH+1:2]][15: 8];
    ram[mem_addr[WIDTH+1:2]][23:16] <= ram_we[2] ? mem_din[23:16] : ram[mem_addr[WIDTH+1:2]][23:16];
    ram[mem_addr[WIDTH+1:2]][31:24] <= ram_we[3] ? mem_din[31:24] : ram[mem_addr[WIDTH+1:2]][31:24];
end

// peripherals
reg wr;
wire [31:0] io_dout;
io u_io(
    .clk  (clk  ),
    .rst  (rst  ),
    .addr (mem_addr ),
    .din  (mem_din  ),
    .wr   (wr   ),
    .dout (io_dout )
);

// multiplexer
reg [ 3:0] select;

always @(posedge clk) select <= mem_addr[31:28];

// read data
always @(*) begin
    case (select)
        // flash
        4'h0: mem_dout = flash_dout;
        // ram
        4'h2: mem_dout = ram_dout;
        // peripherals
        4'h4: mem_dout = io_dout;
    endcase
end

// write data
always @(*) begin
    ram_we = 4'h0;
    wr = 1'b0;
    case (mem_addr[31:28])
        // flash
        4'h0: ;
        // ram
        4'h2: ram_we = mem_we;
        // peripherals
        4'h4: wr = mem_we[0];
    endcase
end

initial begin
	`ifdef XILINX_SIMULATOR
        $readmemh("risc-mini.mem", flash);
    `else
        $readmemh("../src/risc-mini.mem", flash);
    `endif
end

`ifdef SIMULATION
initial begin
	$dumpvars(1, mem_we);
end
`endif

endmodule