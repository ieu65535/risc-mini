`timescale 1ns/1ps

module tb_ddr_interface;

logic clk = 1'b0;
logic rst = 1'b1;
logic ddr_init_done = 1'b0;

logic [31:0] inst_addr = 32'b0;
logic [31:0] inst_dout;
logic        inst_ready;
logic [31:0] data_addr = 32'b0;
logic [31:0] data_din = 32'b0;
logic [ 3:0] data_we = 4'b0;
logic        data_en = 1'b0;
logic [31:0] data_dout;
logic        data_ready;
logic        busy;

logic [27:0]  axi_awaddr;
logic         axi_awuser_ap;
logic [ 3:0]  axi_awuser_id;
logic [ 3:0]  axi_awlen;
logic         axi_awready;
logic         axi_awvalid;
logic [255:0] axi_wdata;
logic [31:0]  axi_wstrb;
logic         axi_wready;
logic [ 3:0]  axi_wusero_id;
logic         axi_wusero_last;
logic [27:0]  axi_araddr;
logic         axi_aruser_ap;
logic [ 3:0]  axi_aruser_id;
logic [ 3:0]  axi_arlen;
logic         axi_arready;
logic         axi_arvalid;
logic [255:0] axi_rdata;
logic [ 3:0]  axi_rid;
logic         axi_rlast;
logic         axi_rvalid;

// Each entry models one 256-bit/32-byte DDR user-interface beat.
logic [255:0] memory [0:255];

always #5 clk = ~clk;

ddr_interface dut (
    .clk             (clk),
    .rst             (rst),
    .ddr_init_done   (ddr_init_done),
    .inst_addr       (inst_addr),
    .inst_dout       (inst_dout),
    .inst_ready      (inst_ready),
    .data_addr       (data_addr),
    .data_din        (data_din),
    .data_we         (data_we),
    .data_en         (data_en),
    .data_dout       (data_dout),
    .data_ready      (data_ready),
    .busy            (busy),
    .axi_awaddr      (axi_awaddr),
    .axi_awuser_ap   (axi_awuser_ap),
    .axi_awuser_id   (axi_awuser_id),
    .axi_awlen       (axi_awlen),
    .axi_awready     (axi_awready),
    .axi_awvalid     (axi_awvalid),
    .axi_wdata       (axi_wdata),
    .axi_wstrb       (axi_wstrb),
    .axi_wready      (axi_wready),
    .axi_wusero_id   (axi_wusero_id),
    .axi_wusero_last (axi_wusero_last),
    .axi_araddr      (axi_araddr),
    .axi_aruser_ap   (axi_aruser_ap),
    .axi_aruser_id   (axi_aruser_id),
    .axi_arlen       (axi_arlen),
    .axi_arready     (axi_arready),
    .axi_arvalid     (axi_arvalid),
    .axi_rdata       (axi_rdata),
    .axi_rid         (axi_rid),
    .axi_rlast       (axi_rlast),
    .axi_rvalid      (axi_rvalid)
);

// --------------------------------------------------------------------------
// Minimal behavioral model of the Pango DDR AXI-like user interface.
// Address units are 32-bit words, so address[...:3] selects a 32-byte line.
// --------------------------------------------------------------------------
assign axi_awready = 1'b1;
assign axi_arready = 1'b1;
assign axi_wready  = write_address_pending;

logic       write_address_pending = 1'b0;
logic [7:0] write_line_index = 8'b0;
logic [7:0] read_line_index = 8'b0;
logic [2:0] read_delay = 3'b0;

integer byte_number;
always_ff @(posedge clk) begin
    axi_rvalid      <= 1'b0;
    axi_rlast       <= 1'b0;
    axi_rid         <= 4'b0;
    axi_wusero_id   <= 4'b0;
    axi_wusero_last <= 1'b0;

    if (rst) begin
        write_address_pending <= 1'b0;
        write_line_index      <= 8'b0;
        read_line_index       <= 8'b0;
        read_delay            <= 3'b0;
        axi_rdata             <= 256'b0;
    end else begin
        if (axi_awvalid && axi_awready) begin
            write_address_pending <= 1'b1;
            write_line_index      <= axi_awaddr[10:3];
        end

        if (write_address_pending) begin
            for (byte_number = 0; byte_number < 32; byte_number = byte_number + 1)
                if (axi_wstrb[byte_number])
                    memory[write_line_index][byte_number*8 +: 8] <=
                        axi_wdata[byte_number*8 +: 8];
            write_address_pending <= 1'b0;
            axi_wusero_last       <= 1'b1;
        end

        if (axi_arvalid && axi_arready) begin
            read_line_index <= axi_araddr[10:3];
            read_delay      <= 3'd2;
        end else if (read_delay != 0) begin
            read_delay <= read_delay - 1'b1;
            if (read_delay == 1) begin
                axi_rdata  <= memory[read_line_index];
                axi_rvalid <= 1'b1;
                axi_rlast  <= 1'b1;
            end
        end
    end
end

task automatic wait_until_ready;
    integer timeout;
    begin
        timeout = 0;
        // Allow nonblocking stimulus assignments and combinational hit/busy
        // detection to settle before deciding whether a transaction is needed.
        #1;
        while (busy) begin
            @(posedge clk);
            timeout = timeout + 1;
            if (timeout > 100)
                $fatal(1, "Timeout waiting for ddr_interface busy to clear");
        end
        #1;
    end
endtask

task automatic expect32(
    input logic [31:0] actual,
    input logic [31:0] expected,
    input string       test_name
);
    begin
        if (actual !== expected)
            $fatal(1, "%s failed: expected %08x, got %08x", test_name,
                   expected, actual);
        $display("PASS: %-30s = %08x", test_name, actual);
    end
endtask

initial begin
    // Line 0: byte addresses 0x00-0x1f.
    memory[0] = {
        32'h1000_0007, 32'h1000_0006, 32'h1000_0005, 32'h1000_0004,
        32'h1000_0003, 32'h1000_0002, 32'h1000_0001, 32'h1000_0000
    };
    // Line 1: byte addresses 0x20-0x3f.
    memory[1] = {
        32'h2000_0007, 32'h2000_0006, 32'h2000_0005, 32'h2000_0004,
        32'h2000_0003, 32'h2000_0002, 32'h2000_0001, 32'h2000_0000
    };
    // Line 2: byte addresses 0x40-0x5f.
    memory[2] = {
        32'h3000_0007, 32'h3000_0006, 32'h3000_0005, 32'h3000_0004,
        32'h3000_0003, 32'h3000_0002, 32'h3000_0001, 32'h3000_0000
    };

    repeat (4) @(posedge clk);
    rst <= 1'b0;
    repeat (2) @(posedge clk);

    if (!busy)
        $fatal(1, "busy must remain asserted before DDR initialization");

    ddr_init_done <= 1'b1;

    // First instruction line fill and all eight lane selections.
    inst_addr <= 32'h0000_0000;
    wait_until_ready();
    expect32(inst_dout, 32'h1000_0000, "instruction word 0");

    inst_addr <= 32'h0000_001c;
    #1;
    if (busy)
        $fatal(1, "Instruction access within a cached line should be a hit");
    expect32(inst_dout, 32'h1000_0007, "instruction word 7");

    // Crossing a 32-byte boundary must issue another AXI read.
    inst_addr <= 32'h0000_0028;
    wait_until_ready();
    expect32(inst_dout, 32'h2000_0002, "instruction next line");

    // Data read from word lane 3 of line 2 (byte address 0x4c).
    data_addr <= 32'h0000_004c;
    data_en   <= 1'b1;
    data_we   <= 4'b0000;
    wait_until_ready();
    expect32(data_dout, 32'h3000_0003, "data read");
    data_en <= 1'b0;

    // Full-word write.  data_we is a one-cycle request pulse.
    @(negedge clk);
    data_addr <= 32'h0000_0048;
    data_din  <= 32'hdead_beef;
    data_we   <= 4'b1111;
    data_en   <= 1'b1;
    @(negedge clk);
    data_we   <= 4'b0000;
    data_en   <= 1'b0;
    wait_until_ready();
    expect32(memory[2][95:64], 32'hdead_beef, "full-word DDR write");

    // Byte write as produced by lmb for address offset 1:
    // shifted data 0x0000aa00 with byte strobe 0010.
    @(negedge clk);
    data_addr <= 32'h0000_0049;
    data_din  <= 32'h0000_aa00;
    data_we   <= 4'b0010;
    data_en   <= 1'b1;
    @(negedge clk);
    data_we   <= 4'b0000;
    data_en   <= 1'b0;
    wait_until_ready();
    expect32(memory[2][95:64], 32'hdead_aaef, "byte-strobe DDR write");

    // Re-read the modified word through the data-side line buffer.
    data_addr <= 32'h0000_0048;
    data_en   <= 1'b1;
    wait_until_ready();
    expect32(data_dout, 32'hdead_aaef, "read after write");
    data_en <= 1'b0;

    $display("ALL DDR INTERFACE TESTS PASSED");
    $finish;
end

initial begin
    #5000;
    $fatal(1, "Global simulation timeout");
end

endmodule
