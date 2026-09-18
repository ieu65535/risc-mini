`timescale 1ns / 1ns

module tb_soc;

    parameter CLK_PERIOD = 20;

    reg sys_clk ;
    reg rst_n ;
    wire [7:0] led ;

    initial begin
        sys_clk = 1'b0 ;
        forever begin
            # (CLK_PERIOD/2) sys_clk = ~sys_clk ;
        end
    end

    initial begin
`ifdef __ICARUS__
        // $dumpfile("risc-mini.vcd");
        // $dumpvars();
`endif
        $display("reset (startup)");
        rst_n = 1'b0;
        # 1e3    rst_n = 1;
        # 2e6;
        $display("\n[TB COMPLETE] tb_soc");
        $finish();
    end

    wire txd;

    soc u_soc(
        .clk   (sys_clk   ),
        .rst_n (rst_n ),
        .rxd   (1'b1  ),
        .txd   (txd   )
    );

endmodule
