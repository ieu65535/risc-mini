`timescale 1ns/1ps

module tb_perf_counters;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [31:0] inst;
    logic [31:0] inst_addr;
    logic [31:0] mem_din;
    logic [31:0] mem_addr;
    logic [3:0] mem_we;
    logic mem_en;
    logic [31:0] inst_mem [0:63];
    integer cycle_expected = 0;
    integer retire_expected = 0;
    integer stall_expected = 0;
    integer store_retired = 0;
    integer branch_retired = 0;
    integer errors = 0;

    assign inst = inst_mem[inst_addr[7:2]];

    pipeline dut (
        .clk(clk), .rst(rst), .timer_int(1'b0),
        .inst(inst), .inst_ready(1'b1), .inst_addr(inst_addr),
        .mem_dout(32'd7), .mem_ready(1'b1), .mem_en(mem_en),
        .mem_din(mem_din), .mem_addr(mem_addr), .mem_we(mem_we)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rst) begin
            cycle_expected <= 0;
            retire_expected <= 0;
            stall_expected <= 0;
            store_retired <= 0;
            branch_retired <= 0;
        end else begin
            cycle_expected <= cycle_expected + 1;
            if (dut.valid_wb) begin
                retire_expected <= retire_expected + 1;
                if (dut.pc_wb == 32'd44) store_retired <= store_retired + 1;
                if (dut.pc_wb == 32'd48) branch_retired <= branch_retired + 1;
            end
            if (dut.stall && !dut.commit_redirect)
                stall_expected <= stall_expected + 1;
        end
    end

    function automatic [31:0] csrr(input [4:0] rd, input [11:0] addr);
        csrr = {addr, 5'd0, 3'b010, rd, 7'h73};
    endfunction

    initial begin
        for (integer i = 0; i < 64; i = i + 1)
            inst_mem[i] = 32'h00000013;
        inst_mem[0]  = 32'h00002083;
        inst_mem[1]  = 32'h00108133;
        inst_mem[2]  = csrr(5'd3, 12'hc00);
        inst_mem[3]  = csrr(5'd4, 12'hc02);
        inst_mem[4]  = csrr(5'd5, 12'hcc0);
        inst_mem[5]  = csrr(5'd6, 12'hc80);
        inst_mem[6]  = csrr(5'd7, 12'hc82);
        inst_mem[7]  = csrr(5'd8, 12'hcc1);
        inst_mem[8]  = csrr(5'd9, 12'hb00);
        inst_mem[9]  = csrr(5'd10, 12'hb02);
        inst_mem[10] = 32'h00900593;
        inst_mem[11] = 32'h00b02023;
        inst_mem[12] = 32'h0000006f;

        repeat (3) @(negedge clk);
        rst = 1'b0;
        repeat (55) @(negedge clk);

        if (dut.u_csr_file.mcycle !== cycle_expected) begin
            $display("[FAIL] cycle got=%0d expected=%0d", dut.u_csr_file.mcycle, cycle_expected);
            errors = errors + 1;
        end
        if (dut.u_csr_file.minstret !== retire_expected) begin
            $display("[FAIL] instret got=%0d expected=%0d", dut.u_csr_file.minstret, retire_expected);
            errors = errors + 1;
        end
        if (dut.u_csr_file.stall_cycles !== stall_expected) begin
            $display("[FAIL] stall got=%0d expected=%0d", dut.u_csr_file.stall_cycles, stall_expected);
            errors = errors + 1;
        end
        if (stall_expected != 1 || store_retired != 1 || branch_retired == 0) begin
            $display("[FAIL] stimulus stall=%0d store=%0d branch=%0d",
                     stall_expected, store_retired, branch_retired);
            errors = errors + 1;
        end
        if (dut.u_reg_file.regs[3] === 32'd0 || dut.u_reg_file.regs[4] === 32'd0 ||
            dut.u_reg_file.regs[5] !== 32'd1 || dut.u_reg_file.regs[6] !== 32'd0 ||
            dut.u_reg_file.regs[7] !== 32'd0 || dut.u_reg_file.regs[8] !== 32'd0 ||
            dut.u_reg_file.regs[9] < dut.u_reg_file.regs[3] ||
            dut.u_reg_file.regs[10] < dut.u_reg_file.regs[4]) begin
            $display("[FAIL] software-visible counter reads");
            errors = errors + 1;
        end

        if (errors != 0)
            $fatal(1, "[TB FAIL] tb_perf_counters: %0d checks failed", errors);
        $display("[TB PASS] tb_perf_counters");
        $finish;
    end
endmodule
