module bus(
    input clk,
    input rst,
    input ddr_init_done,
    input [31:0] inst_addr,//指令地址输入
    output [31:0] inst_dout,//指令输出
    output        inst_ready,
    
    input [31:0] mem_addr,//内存地址输入
    input [31:0] mem_din,   //数据输入
    input [ 3:0] mem_we,//数据写入使能
    output reg [31:0] mem_dout,//数据输出

    input rxd,
    output txd,

    output [27:0] axi_awaddr,
    output        axi_awuser_ap,
    output [ 3:0] axi_awuser_id,
    output [ 3:0] axi_awlen,
    input         axi_awready,
    output        axi_awvalid,
    output [255:0] axi_wdata,
    output [31:0]  axi_wstrb,
    input          axi_wready,
    input  [ 3:0]  axi_wusero_id,
    input           axi_wusero_last,
    output [27:0]  axi_araddr,
    output         axi_aruser_ap,
    output [ 3:0]  axi_aruser_id,
    output [ 3:0]  axi_arlen,
    input          axi_arready,
    output         axi_arvalid,
    input  [255:0] axi_rdata,
    input  [ 3:0]  axi_rid,
    input           axi_rlast,
    input           axi_rvalid,
    output          ddr_busy
);

localparam WIDTH = 10;//地址索引位数
// DDR replaces the old on-chip flash interface.  Keep the flash source file in
// the project so it can still be used for simulation or bring-up if required.
wire [31:0] flash_dout;

// flash u_flash(
//     .clk        (clk        ),
//     .inst_addr  (inst_addr  ),
//     .inst_dout  (inst_dout  ),
//     .flash_addr (mem_addr   ),
//     .flash_dout (flash_dout )
// );

ddr_interface u_ddr_interface (
    .clk             (clk             ),
    .rst             (rst             ),
    .ddr_init_done   (ddr_init_done   ),
    .inst_addr       (inst_addr       ),
    .inst_dout       (inst_dout       ),
    .inst_ready      (inst_ready      ),
    .data_addr       (mem_addr        ),
    .data_din        (mem_din         ),
    .data_we         (mem_we          ),
    .data_en         (mem_addr[31:28] == 4'h0),
    .data_dout       (flash_dout      ),
    .busy            (ddr_busy        ),
    .axi_awaddr      (axi_awaddr      ),
    .axi_awuser_ap   (axi_awuser_ap   ),
    .axi_awuser_id   (axi_awuser_id   ),
    .axi_awlen       (axi_awlen       ),
    .axi_awready     (axi_awready     ),
    .axi_awvalid     (axi_awvalid     ),
    .axi_wdata       (axi_wdata       ),
    .axi_wstrb       (axi_wstrb       ),
    .axi_wready      (axi_wready      ),
    .axi_wusero_id   (axi_wusero_id   ),
    .axi_wusero_last (axi_wusero_last ),
    .axi_araddr      (axi_araddr      ),
    .axi_aruser_ap   (axi_aruser_ap   ),
    .axi_aruser_id   (axi_aruser_id   ),
    .axi_arlen       (axi_arlen       ),
    .axi_arready     (axi_arready     ),
    .axi_arvalid     (axi_arvalid     ),
    .axi_rdata       (axi_rdata       ),
    .axi_rid         (axi_rid         ),
    .axi_rlast       (axi_rlast       ),
    .axi_rvalid      (axi_rvalid      )
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
