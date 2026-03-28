`timescale 1ns / 1ns

module tb_soc;

    parameter CLK_PERIOD = 20;

    reg sys_clk ;
    reg rst_n ;
    wire [7:0] led ;
    wire txd;
    reg rxd;

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
        rxd = 1;
        # 1e3    rst_n = 1;
        #750   rxd = 0;
        # 2e6    $finish();
    end

    

    soc u_soc(
        .clk   (sys_clk   ),
        .rst_n (rst_n ),
        .txd   (txd   ),
        .rxd   (rxd )
    );

endmodule