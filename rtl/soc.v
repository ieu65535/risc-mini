module soc(
    input clk,
    input rst_n,

    input rxd,
    output txd
);

wire rst;
reset_sync u_reset_sync(
    .clk   (clk   ),
    .rst_n (rst_n ),
    .rst   (rst   )
);

wire [31:0] inst_addr, inst, mem_addr, mem_din, mem_dout;
wire [ 3:0] mem_we;

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
    .rxd       (rxd       )
);

cpu u_cpu(
    .clk      (clk      ),
    .rst      (rst      ),
    .inst     (inst     ),
    .next_pc  (inst_addr),
    .mem_dout (mem_dout ),
    .mem_din  (mem_din  ),
    .mem_addr (mem_addr ),
    .mem_we   (mem_we   )
);

`ifdef SIMULATION
initial begin
	$dumpvars(1, inst_addr, inst);
end
`endif

endmodule