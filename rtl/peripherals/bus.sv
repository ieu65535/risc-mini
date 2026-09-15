module bus(
    input clk,
    input rst,
    input [31:0] inst_addr,//指令地址输入
    output [31:0] inst_dout,//指令输出
    
    input [31:0] mem_addr,//内存地址输入
    input [31:0] mem_din,   //数据输入
    input [ 3:0] mem_we,//数据写入使能
    output reg [31:0] mem_dout,//数据输出

    input rxd,
    output txd
);

localparam WIDTH = 10;//地址索引位数
// flash
wire [31:0] flash_dout;

flash u_flash(
    .clk        (clk        ),
    .inst_addr  (inst_addr  ),
    .inst_dout  (inst_dout  ),
    .flash_addr (mem_addr   ),
    .flash_dout (flash_dout )
);

// rom12 u_flash (
//   .clka(clk),    // input wire clka
//   .addra(inst_addr),  // input wire [31 : 0] addra
//   .douta(inst_dout),  // output wire [31 : 0] douta
//   .clkb(clk),    // input wire clkb
//   .addrb(mem_addr),  // input wire [31 : 0] addrb
//   .doutb(flash_dout)  // output wire [31 : 0] doutb
// );

// ram
wire [31:0] ram_dout;
reg [ 3:0] ram_we;

ram u_ram(
    .clk  (clk  ),
    .addr (mem_addr ),
    .din  (mem_din  ),
    .we   (ram_we   ),
    .dout (ram_dout )
);

// peripherals
reg wr;
wire [31:0] io_dout;
io u_io(
    .clk  (clk  ),
    .rst  (rst  ),
    .addr (mem_addr ),
    .din  (mem_din  ),
    .wr   (wr   ),
    .dout (io_dout ),
    .txd  (txd),
    .rxd  (rxd)
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
        default: mem_dout = 32'h0;
    endcase
end

// write data
always @(*) begin
    ram_we = 4'h0;
    wr = 1'b0;
    case (mem_addr[31:28])//decide which peripheral to write(选择设备)
        // flash
        4'h0: ;
        // ram
        4'h2: ram_we = mem_we;
        // peripherals
        4'h4: wr = mem_we[0];
    endcase
end

`ifdef SIMULATION
`ifdef DUMP_WAVES
initial begin
	$dumpvars(1, mem_we);
end
`endif
`endif

endmodule
