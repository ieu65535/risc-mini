`timescale 1ns/1ps
`include "config.vh"
module soc(
    input  wire clk,
    input  wire rst_n,

    input  wire ref_clk_p,
    input  wire ref_clk_n,

    input  wire rxd,
    output wire txd,

    output wire         mem_cs_n,
    output wire         mem_rst_n,
    output wire         mem_ck,
    output wire         mem_ck_n,
    output wire         mem_cke,
    output wire         mem_ras_n,
    output wire         mem_cas_n,
    output wire         mem_we_n,
    output wire         mem_odt,
    output wire  [14:0] mem_a,
    output wire  [ 2:0] mem_ba,
    output wire  [ 3:0] mem_dm,
    inout  wire  [ 3:0] mem_dqs,
    inout  wire  [ 3:0] mem_dqs_n,
    inout  wire  [31:0] mem_dq
);

wire ref_clk;
wire core_clk;
wire ddr_init_done;

GTP_INBUFGDS u_ref_clk_ibufg (
    .O  (ref_clk   ),
    .I  (ref_clk_p ),
    .IB (ref_clk_n )
);

wire rst;
reset_sync u_reset_sync(
    .clk   (core_clk            ),
    .rst_n (rst_n & ddr_init_done),
    .rst   (rst   )
);

wire [31:0] inst;
wire        inst_ready;
wire [31:0] inst_addr;
wire [31:0] mem_addr;
wire [31:0] mem_din;
wire [31:0] mem_dout;
wire [ 3:0] mem_we;

wire [27:0]  axi_awaddr;
wire         axi_awuser_ap;
wire [ 3:0]  axi_awuser_id;
wire [ 3:0]  axi_awlen;
wire         axi_awready;
wire         axi_awvalid;
wire [255:0] axi_wdata;
wire [31:0]  axi_wstrb;
wire         axi_wready;
wire [ 3:0]  axi_wusero_id;
wire         axi_wusero_last;
wire [27:0]  axi_araddr;
wire         axi_aruser_ap;
wire [ 3:0]  axi_aruser_id;
wire [ 3:0]  axi_arlen;
wire         axi_arready;
wire         axi_arvalid;
wire [255:0] axi_rdata;
wire [ 3:0]  axi_rid;
wire         axi_rlast;
wire         axi_rvalid;
wire         ddr_busy;

bus u_bus(
    .clk       (core_clk  ),
    .rst       (rst       ),
    .ddr_init_done(ddr_init_done),
    .inst_addr (inst_addr ),
    .inst_dout (inst      ),
    .inst_ready(inst_ready),
    .mem_addr  (mem_addr  ),
    .mem_din   (mem_din   ),
    .mem_we    (mem_we    ),
    .mem_dout  (mem_dout  ),
    .txd       (txd       ),
    .rxd       (rxd       ),
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
    .axi_rvalid      (axi_rvalid      ),
    .ddr_busy        (ddr_busy        )
);

pipeline u_cpu(
    .clk       (core_clk  ),
    .rst       (rst       ),
    .inst      (inst      ),
    .inst_ready(inst_ready),
    .inst_addr (inst_addr ),
    .mem_addr  (mem_addr  ),
    .mem_din   (mem_din   ),
    .mem_dout  (mem_dout  ),
    .mem_we    (mem_we    ),
    .timer_int (1'b0      )
);

u_ddr I_ips_ddr_top (
    .ref_clk                    (ref_clk                      ),
    .resetn                     (rst_n                        ),
    .core_clk                   (core_clk                     ),
    .pll_lock                   (                             ),
    .phy_pll_lock               (                             ),
    .gpll_lock                  (                             ),
    .rst_gpll_lock              (                             ),
    .ddrphy_cpd_lock            (                             ),
    .ddr_init_done              (ddr_init_done                ),

    .axi_awaddr                 (axi_awaddr                   ),
    .axi_awuser_ap              (axi_awuser_ap                ),
    .axi_awuser_id              (axi_awuser_id                ),
    .axi_awlen                  (axi_awlen                    ),
    .axi_awready                (axi_awready                  ),
    .axi_awvalid                (axi_awvalid                  ),
    .axi_wdata                  (axi_wdata                    ),
    .axi_wstrb                  (axi_wstrb                    ),
    .axi_wready                 (axi_wready                   ),
    .axi_wusero_id              (axi_wusero_id                ),
    .axi_wusero_last            (axi_wusero_last              ),
    .axi_araddr                 (axi_araddr                   ),
    .axi_aruser_ap              (axi_aruser_ap                ),
    .axi_aruser_id              (axi_aruser_id                ),
    .axi_arlen                  (axi_arlen                    ),
    .axi_arready                (axi_arready                  ),
    .axi_arvalid                (axi_arvalid                  ),
    .axi_rdata                  (axi_rdata                    ),
    .axi_rid                    (axi_rid                      ),
    .axi_rlast                  (axi_rlast                    ),
    .axi_rvalid                 (axi_rvalid                   ),

    .apb_clk                    (1'b0                         ),
    .apb_rst_n                  (1'b0                         ),
    .apb_sel                    (1'b0                         ),
    .apb_enable                 (1'b0                         ),
    .apb_addr                   (8'b0                         ),
    .apb_write                  (1'b0                         ),
    .apb_ready                  (                             ),
    .apb_wdata                  (16'b0                        ),
    .apb_rdata                  (                             ),

    .mem_cs_n                   (mem_cs_n                     ),
    .mem_rst_n                  (mem_rst_n                    ),
    .mem_ck                     (mem_ck                       ),
    .mem_ck_n                   (mem_ck_n                     ),
    .mem_cke                    (mem_cke                      ),
    .mem_ras_n                  (mem_ras_n                    ),
    .mem_cas_n                  (mem_cas_n                    ),
    .mem_we_n                   (mem_we_n                     ),
    .mem_odt                    (mem_odt                      ),
    .mem_a                      (mem_a                        ),
    .mem_ba                     (mem_ba                       ),
    .mem_dqs                    (mem_dqs                      ),
    .mem_dqs_n                  (mem_dqs_n                    ),
    .mem_dq                     (mem_dq                       ),
    .mem_dm                     (mem_dm                       ),

    // Defaults copied from the generated ddr3_test example design.
    .dbg_gate_start             (1'b0                         ),
    .dbg_cpd_start              (1'b0                         ),
    .dbg_ddrphy_rst_n           (1'b1                         ),
    .dbg_gpll_scan_rst          (1'b0                         ),
    .samp_position_dyn_adj      (1'b0                         ),
    .init_samp_position_even    (32'b0                        ),
    .init_samp_position_odd     (32'b0                        ),
    .wrcal_position_dyn_adj     (1'b0                         ),
    .init_wrcal_position        (32'b0                        ),
    .force_read_clk_ctrl        (1'b0                         ),
    .init_slip_step             (16'b0                        ),
    .init_read_clk_ctrl         (12'b0                        ),
    .debug_calib_ctrl           (                             ),
    .dbg_slice_status           (                             ),
    .dbg_slice_state            (                             ),
    .debug_data                 (                             ),
    .dbg_dll_upd_state          (                             ),
    .debug_gpll_dps_phase       (                             ),
    .dbg_rst_dps_state          (                             ),
    .dbg_tran_err_rst_cnt       (                             ),
    .dbg_ddrphy_init_fail       (                             ),
    .debug_cpd_offset_adj       (1'b0                         ),
    .debug_cpd_offset_dir       (1'b0                         ),
    .debug_cpd_offset           (10'b0                        ),
    .debug_dps_cnt_dir0         (                             ),
    .debug_dps_cnt_dir1         (                             ),
    .ck_dly_en                  (1'b1                         ),
    .init_ck_dly_step           (8'b0                         ),
    .ck_dly_set_bin             (                             ),
    .align_error                (                             ),
    .debug_rst_state            (                             ),
    .debug_cpd_state            (                             )
);

`ifdef SIMULATION
`ifdef DUMP_WAVES
initial begin
	$dumpvars(1, inst_addr, inst);
end
`endif
`endif

endmodule
