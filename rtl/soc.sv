`include "config.vh"
module soc(
    input  logic clk,
    input  logic rst_n,

    input  logic rxd,
    output logic txd,
    output logic [1:0] led
);
logic [31:0] pout;
assign led = pout[1:0];

logic rst;
reset_sync u_reset_sync(
    .clk   (clk   ),
    .rst_n (rst_n ),
    .rst   (rst   )
);

logic [31:0] inst;
logic [31:0] inst_addr;
logic [31:0] mem_addr;
logic [31:0] mem_din;
logic [31:0] mem_dout;
logic [ 3:0] mem_we;

bus u_bus(
    .clk       (clk       ),
    .rst       (rst       ),
    .inst_addr (inst_addr ),
    .inst_dout (inst      ),
    .mem_addr  (mem_addr  ),
    .mem_din   (mem_din   ),
    .mem_we    (mem_we    ),
    .mem_dout  (mem_dout  ),
    .txd       (txd       ),
    .rxd       (rxd       ),
    .pout      (pout      )
);

pipeline u_cpu(
    .clk       (clk       ),
    .rst       (rst       ),
    .inst      (inst      ),
    .inst_addr (inst_addr ),
    .mem_addr  (mem_addr  ),
    .mem_din   (mem_din   ),
    .mem_dout  (mem_dout  ),
    .mem_we    (mem_we    )
);

`ifdef SIMULATION
initial begin
	$dumpvars(1, inst_addr, inst);
end
`endif

endmodule