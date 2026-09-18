`timescale 1ns/1ps

// Hello World system testbench.
// It keeps the real CPU, bus and ddr_interface, but replaces the slow DDR PHY
// and external DDR3 device with a small behavioral AXI memory.
module tb_hello;

    localparam integer DDR_WORDS = 8192;
    localparam integer TIMEOUT_CYCLES = 300000;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic ddr_init_done = 1'b0;

    logic [31:0] inst;
    logic        inst_ready;
    logic [31:0] inst_addr;
    logic [31:0] mem_addr;
    logic [31:0] mem_din;
    logic [31:0] mem_dout;
    logic [3:0]  mem_we;
    logic        mem_en;
    logic        mem_ready;
    logic        txd;

    logic [27:0]  axi_awaddr;
    logic         axi_awuser_ap;
    logic [3:0]   axi_awuser_id;
    logic [3:0]   axi_awlen;
    logic         axi_awready;
    logic         axi_awvalid;
    logic [255:0] axi_wdata;
    logic [31:0]  axi_wstrb;
    logic         axi_wready;
    logic [3:0]   axi_wusero_id;
    logic         axi_wusero_last;
    logic [27:0]  axi_araddr;
    logic         axi_aruser_ap;
    logic [3:0]   axi_aruser_id;
    logic [3:0]   axi_arlen;
    logic         axi_arready;
    logic         axi_arvalid;
    logic [255:0] axi_rdata;
    logic [3:0]   axi_rid;
    logic         axi_rlast;
    logic         axi_rvalid;
    logic         ddr_busy;

    logic [31:0] ddr_words [0:DDR_WORDS-1];
    logic        read_pending = 1'b0;
    logic [27:0] read_addr = 28'b0;
    logic        write_pending = 1'b0;
    logic [27:0] write_addr = 28'b0;
    integer      uart_char_count = 0;
    integer      cycle_count = 0;
    integer      init_index;
    integer      line_index;
    integer      byte_index;

    always #10 clk = ~clk; // 50 MHz

    pipeline u_cpu (
        .clk(clk), .rst(rst),
        .inst(inst), .inst_ready(inst_ready), .inst_addr(inst_addr),
        .mem_dout(mem_dout), .mem_ready(mem_ready), .mem_en(mem_en),
        .mem_din(mem_din), .mem_addr(mem_addr), .mem_we(mem_we),
        .timer_int(1'b0)
    );

    bus u_bus (
        .clk(clk), .rst(rst), .ddr_init_done(ddr_init_done),
        .inst_addr(inst_addr), .inst_dout(inst), .inst_ready(inst_ready),
        .mem_addr(mem_addr), .mem_din(mem_din), .mem_we(mem_we),
        .mem_en(mem_en), .mem_dout(mem_dout), .mem_ready(mem_ready),
        .rxd(1'b1), .txd(txd),
        .axi_awaddr(axi_awaddr), .axi_awuser_ap(axi_awuser_ap),
        .axi_awuser_id(axi_awuser_id), .axi_awlen(axi_awlen),
        .axi_awready(axi_awready), .axi_awvalid(axi_awvalid),
        .axi_wdata(axi_wdata), .axi_wstrb(axi_wstrb),
        .axi_wready(axi_wready), .axi_wusero_id(axi_wusero_id),
        .axi_wusero_last(axi_wusero_last),
        .axi_araddr(axi_araddr), .axi_aruser_ap(axi_aruser_ap),
        .axi_aruser_id(axi_aruser_id), .axi_arlen(axi_arlen),
        .axi_arready(axi_arready), .axi_arvalid(axi_arvalid),
        .axi_rdata(axi_rdata), .axi_rid(axi_rid),
        .axi_rlast(axi_rlast), .axi_rvalid(axi_rvalid),
        .ddr_busy(ddr_busy)
    );

    // The generated Pango DDR user address is a 32-bit-word address.
    // ddr_interface always requests one aligned 256-bit/eight-word line.
    assign axi_arready = 1'b1;
    assign axi_awready = 1'b1;
    assign axi_wready = 1'b1;
    assign axi_wusero_id = 4'b0;
    assign axi_wusero_last = 1'b1;
    assign axi_rid = 4'b0;
    assign axi_rlast = 1'b1;

    always @(posedge clk) begin
        axi_rvalid <= 1'b0;

        if (rst) begin
            read_pending <= 1'b0;
            write_pending <= 1'b0;
        end else begin
            if (axi_arvalid && axi_arready) begin
                read_pending <= 1'b1;
                read_addr <= axi_araddr;
            end

            if (read_pending) begin
                for (line_index = 0; line_index < 8; line_index = line_index + 1)
                    axi_rdata[line_index*32 +: 32] <=
                        ddr_words[read_addr + line_index];
                axi_rvalid <= 1'b1;
                read_pending <= 1'b0;
            end

            if (axi_awvalid && axi_awready) begin
                write_pending <= 1'b1;
                write_addr <= axi_awaddr;
            end else if (write_pending) begin
                for (byte_index = 0; byte_index < 32; byte_index = byte_index + 1)
                    if (axi_wstrb[byte_index])
                        ddr_words[write_addr + (byte_index >> 2)]
                                 [(byte_index & 3)*8 +: 8] <=
                            axi_wdata[byte_index*8 +: 8];
                write_pending <= 1'b0;
            end
        end
    end

    function automatic [7:0] expected_uart_char(input integer index);
        begin
            case (index)
                0: expected_uart_char = "H";
                1: expected_uart_char = "e";
                2: expected_uart_char = "l";
                3: expected_uart_char = "l";
                4: expected_uart_char = "o";
                5: expected_uart_char = ",";
                6: expected_uart_char = " ";
                7: expected_uart_char = "W";
                8: expected_uart_char = "o";
                9: expected_uart_char = "r";
                10: expected_uart_char = "l";
                11: expected_uart_char = "d";
                12: expected_uart_char = "!";
                13: expected_uart_char = 8'h0a;
                default: expected_uart_char = 8'h00;
            endcase
        end
    endfunction

    // Capture the same byte accepted by the UART transmitter.
    always @(posedge clk) begin
        if (!rst && u_bus.u_io.en) begin
            if (u_bus.u_io.UDR[7:0] !== expected_uart_char(uart_char_count))
                $fatal(1, "[TB FAIL] UART byte %0d got 0x%02h expected 0x%02h",
                       uart_char_count, u_bus.u_io.UDR[7:0],
                       expected_uart_char(uart_char_count));
            if (uart_char_count == 13) begin
                $display("[TB PASS] tb_hello received Hello, World!");
                $finish;
            end
            uart_char_count = uart_char_count + 1;
        end
    end

    always @(posedge clk) begin
        if (rst)
            cycle_count <= 0;
        else begin
            cycle_count <= cycle_count + 1;
            if (cycle_count >= TIMEOUT_CYCLES)
                $fatal(1, "[TB TIMEOUT] received %0d UART bytes", uart_char_count);
        end
    end

    initial begin
        axi_rdata = 256'b0;
        axi_rvalid = 1'b0;
        for (init_index = 0; init_index < DDR_WORDS; init_index = init_index + 1)
            ddr_words[init_index] = 32'h00000013;
        $readmemh("../src/risc-mini.mem", ddr_words, 0, 1023);

        repeat (8) @(posedge clk);
        ddr_init_done <= 1'b1;
        repeat (2) @(posedge clk);
        rst <= 1'b0;
    end

endmodule
