`timescale 1ns/1ps

module tb_fetch;

logic clk = 1'b0;
logic rst = 1'b1;
logic stall = 1'b0;
logic redirect_valid = 1'b0;
logic [31:0] redirect_addr = 32'b0;
logic [31:0] inst_addr;
logic [31:0] inst_rdata = 32'h0000_0013;
logic inst_ready = 1'b0;
logic [31:0] inst;
logic [31:0] pc;
logic valid;
logic fetch_wait;

always #5 clk = ~clk;

always @(posedge clk) begin
    if ($test$plusargs("FETCH_DEBUG"))
        $display("DBG t=%0t rst=%b stall=%b ready=%b addr=%08x in=%08x out=%08x valid=%b",
                 $time, rst, stall, inst_ready, inst_addr, inst_rdata, inst, valid);
end

fetch dut (
    .clk            (clk),
    .rst            (rst),
    .stall          (stall),
    .redirect_valid (redirect_valid),
    .redirect_addr  (redirect_addr),
    .inst_addr      (inst_addr),
    .inst_rdata     (inst_rdata),
    .inst_ready     (inst_ready),
    .inst           (inst),
    .pc             (pc),
    .valid          (valid),
    .fetch_wait     (fetch_wait)
);

task automatic expect32(
    input logic [31:0] actual,
    input logic [31:0] expected,
    input string name
);
    begin
        if (actual !== expected)
            $fatal(1, "%s: expected %08x, got %08x", name, expected, actual);
        $display("PASS: %-28s = %08x", name, actual);
    end
endtask

initial begin
    repeat (3) @(posedge clk);
    rst = 1'b0;

    // A memory miss must keep the request address fixed and produce no IF/ID entry.
    repeat (4) begin
        @(posedge clk);
        #1;
        expect32(inst_addr, 32'h0000_0000, "PC held during read wait");
        if (valid !== 1'b0 || fetch_wait !== 1'b1)
            $fatal(1, "fetch must remain invalid while inst_ready is low");
    end

    // Complete address 0. The instruction is committed exactly once and the
    // request advances to address 4.
    @(negedge clk);
    inst_rdata = 32'h0010_0093; // addi x1, x0, 1
    inst_ready = 1'b1;
    @(posedge clk);
    #1;
    expect32(inst, 32'h0010_0093, "returned instruction");
    expect32(pc, 32'h0000_0000, "returned instruction PC");
    expect32(inst_addr, 32'h0000_0004, "next sequential request");
    if (!valid)
        $fatal(1, "returned instruction was not marked valid");

    // A downstream hazard holds both the IF/ID register and request PC.
    @(negedge clk);
    stall = 1'b1;
    inst_rdata = 32'h0020_0113;
    repeat (2) begin
        @(posedge clk);
        #1;
        expect32(inst_addr, 32'h0000_0004, "PC held by downstream stall");
        expect32(inst, 32'h0010_0093, "IF/ID held by downstream stall");
    end

    // Once the previous entry can move forward, a pending read inserts a bubble.
    @(negedge clk);
    stall = 1'b0;
    inst_ready = 1'b0;
    @(posedge clk);
    #1;
    if (valid !== 1'b0)
        $fatal(1, "read wait must insert an invalid IF/ID bubble");
    expect32(inst_addr, 32'h0000_0004, "pending request remains stable");

    // Redirect has priority over that pending request and invalidates the old path.
    @(negedge clk);
    redirect_addr = 32'h0000_0100;
    redirect_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    redirect_valid = 1'b0;
    expect32(inst_addr, 32'h0000_0100, "redirect request address");
    if (valid !== 1'b0)
        $fatal(1, "redirect must flush the IF/ID entry");

    // JAL x0,+8 is predicted taken, preserving the original core policy.
    inst_rdata = 32'h0080_006f;
    inst_ready = 1'b1;
    @(posedge clk);
    #1;
    expect32(pc, 32'h0000_0100, "JAL instruction PC");
    expect32(inst_addr, 32'h0000_0108, "JAL predicted target");
    if (!valid)
        $fatal(1, "JAL response was not marked valid");

    $display("ALL FETCH TESTS PASSED");
    $finish;
end

initial begin
    #3000;
    $fatal(1, "Global fetch test timeout");
end

endmodule
