`timescale 1ns/1ps

module tb_mem_stall;

logic        clk = 1'b0;
logic        rst = 1'b1;
logic [31:0] inst;
logic [31:0] inst_addr;
logic [31:0] mem_dout = 32'b0;
logic        mem_ready = 1'b0;
logic        mem_en;
logic [31:0] mem_din;
logic [31:0] mem_addr;
logic [ 3:0] mem_we;

logic [31:0] inst_mem [0:255];
logic [31:0] data_mem [0:255];

logic        pending = 1'b0;
logic [ 2:0] delay_count = 3'b0;
logic [31:0] saved_addr = 32'b0;
logic [31:0] saved_din = 32'b0;
logic [ 3:0] saved_we = 4'b0;
integer      request_count = 0;
integer      wait_cycles = 0;
integer      i;

always #5 clk = ~clk;
assign inst = inst_mem[inst_addr[9:2]];

pipeline dut (
    .clk        (clk),
    .rst        (rst),
    .inst       (inst),
    .inst_ready (1'b1),
    .inst_addr  (inst_addr),
    .mem_dout   (mem_dout),
    .mem_ready  (mem_ready),
    .mem_en     (mem_en),
    .mem_din    (mem_din),
    .mem_addr   (mem_addr),
    .mem_we     (mem_we),
    .timer_int  (1'b0)
);

// A memory slave that takes four clocks from request acceptance to response.
// mem_ready remains high for one cycle, and the CPU must hold the request stable.
always_ff @(posedge clk) begin
    mem_ready <= 1'b0;

    if (rst) begin
        pending      <= 1'b0;
        delay_count  <= 3'b0;
        request_count <= 0;
    end else if (mem_ready) begin
        // Response is consumed on this edge; do not re-accept the held request.
    end else if (!pending && mem_en) begin
        pending      <= 1'b1;
        delay_count  <= 3'd3;
        saved_addr   <= mem_addr;
        saved_din    <= mem_din;
        saved_we     <= mem_we;
        request_count <= request_count + 1;
    end else if (pending && (delay_count != 0)) begin
        delay_count <= delay_count - 1'b1;
    end else if (pending) begin
        if (saved_we == 4'b0) begin
            mem_dout <= data_mem[saved_addr[9:2]];
        end else begin
            if (saved_we[0]) data_mem[saved_addr[9:2]][ 7: 0] <= saved_din[ 7: 0];
            if (saved_we[1]) data_mem[saved_addr[9:2]][15: 8] <= saved_din[15: 8];
            if (saved_we[2]) data_mem[saved_addr[9:2]][23:16] <= saved_din[23:16];
            if (saved_we[3]) data_mem[saved_addr[9:2]][31:24] <= saved_din[31:24];
        end
        pending   <= 1'b0;
        mem_ready <= 1'b1;
    end
end

logic        checking_hold = 1'b0;
logic [31:0] held_inst_addr;
logic [31:0] held_ex_pc;
logic [31:0] held_ex_inst;
logic [31:0] held_mem_addr;
logic [ 3:0] held_mem_we;

always @(posedge clk) begin
    if (!rst && dut.mem_wait) begin
        wait_cycles = wait_cycles + 1;
        if (!checking_hold) begin
            checking_hold = 1'b1;
            held_inst_addr = inst_addr;
            held_ex_pc     = dut.pc_ex;
            held_ex_inst   = dut.inst_ex;
            held_mem_addr  = mem_addr;
            held_mem_we    = mem_we;
        end else if ((inst_addr !== held_inst_addr) ||
                     (dut.pc_ex !== held_ex_pc) ||
                     (dut.inst_ex !== held_ex_inst) ||
                     (mem_addr !== held_mem_addr) ||
                     (mem_we !== held_mem_we)) begin
            $fatal(1, "Pipeline/request changed while mem_wait was asserted");
        end
    end else begin
        checking_hold = 1'b0;
    end
end

initial begin
    for (i = 0; i < 256; i = i + 1) begin
        inst_mem[i] = 32'h0000_0013;
        data_mem[i] = 32'b0;
    end

    // x1=64; x2=[64]; x3=x2+1; [68]=x3; x4=[68]; x5=x4+1.
    inst_mem[0] = 32'h0400_0093;
    inst_mem[1] = 32'h0000_a103;
    inst_mem[2] = 32'h0011_0193;
    inst_mem[3] = 32'h0030_a223;
    inst_mem[4] = 32'h0040_a203;
    inst_mem[5] = 32'h0012_0293;
    inst_mem[6] = 32'h0000_006f;
    data_mem[16] = 32'h1234_5678;

    repeat (4) @(posedge clk);
    rst <= 1'b0;
    repeat (80) @(posedge clk);

    if (dut.u_reg_file.regs[2] !== 32'h1234_5678)
        $fatal(1, "Delayed load failed: x2=%08x", dut.u_reg_file.regs[2]);
    if (dut.u_reg_file.regs[3] !== 32'h1234_5679)
        $fatal(1, "Load-use result failed: x3=%08x", dut.u_reg_file.regs[3]);
    if (data_mem[17] !== 32'h1234_5679)
        $fatal(1, "Delayed store failed: mem[68]=%08x", data_mem[17]);
    if (dut.u_reg_file.regs[4] !== 32'h1234_5679)
        $fatal(1, "Read-after-write failed: x4=%08x", dut.u_reg_file.regs[4]);
    if (dut.u_reg_file.regs[5] !== 32'h1234_567a)
        $fatal(1, "Post-stall execution failed: x5=%08x", dut.u_reg_file.regs[5]);
    if (request_count != 3)
        $fatal(1, "Expected exactly 3 memory requests, got %0d", request_count);
    if (wait_cycles < 9)
        $fatal(1, "Global stall was not exercised long enough: %0d cycles", wait_cycles);

    $display("ALL GLOBAL MEMORY STALL TESTS PASSED (%0d wait cycles)", wait_cycles);
    $finish;
end

initial begin
    #5000;
    $fatal(1, "Global memory stall test timeout");
end

endmodule
