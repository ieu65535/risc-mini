`timescale 1ns/1ps

module tb_perf_counters();
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [31:0] inst = 32'h00000013;
    logic [31:0] inst_addr;
    logic [31:0] mem_din;
    logic [31:0] mem_addr;
    logic [3:0] mem_we;
    logic [31:0] inst_mem [0:63];
    integer cycle_expected = 0;
    integer retire_expected = 0;
    integer stall_expected = 0;
    integer store_retired = 0;
    integer branch_retired = 0;
    integer errors = 0;

    pipeline dut (
        .clk(clk), .rst(rst), .inst(inst), .inst_addr(inst_addr),
        .mem_dout(32'd7), .mem_din(mem_din), .mem_addr(mem_addr),
        .mem_we(mem_we), .timer_int(1'b0)
    );

    always #5 clk = ~clk;
    always @(posedge clk)
        inst <= inst_mem[inst_addr[7:2]];

    // 独立的边沿计分板：退休按有效指令，不按通用寄存器写使能。
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
            if (dut.stall && !dut.pc_mis)
                stall_expected <= stall_expected + 1;
        end
    end

    function automatic [31:0] csrr(input [4:0] rd, input [11:0] addr);
        csrr = {addr, 5'd0, 3'b010, rd, 7'h73};
    endfunction

    initial begin
        for (integer i = 0; i < 64; i = i + 1)
            inst_mem[i] = 32'h00000013;
        inst_mem[0]  = 32'h00002083;             // lw x1, 0(x0)
        inst_mem[1]  = 32'h00108133;             // add x2, x1, x1: 一次 load-use 暂停
        inst_mem[2]  = csrr(5'd3, 12'hc00);     // cycle
        inst_mem[3]  = csrr(5'd4, 12'hc02);     // instret
        inst_mem[4]  = csrr(5'd5, 12'hcc0);     // 自定义 stall_cycles
        inst_mem[5]  = csrr(5'd6, 12'hc80);     // cycleh
        inst_mem[6]  = csrr(5'd7, 12'hc82);     // instreth
        inst_mem[7]  = csrr(5'd8, 12'hcc1);     // stall_cyclesh
        inst_mem[8]  = csrr(5'd9, 12'hb00);     // mcycle 与 cycle 同源
        inst_mem[9]  = csrr(5'd10, 12'hb02);    // minstret 与 instret 同源
        inst_mem[10] = 32'h00900593;             // addi x11, x0, 9
        inst_mem[11] = 32'h00b02023;             // sw x11, 0(x0)，不写通用寄存器
        inst_mem[12] = 32'h0000006f;             // jal x0, 0，不写通用寄存器

        repeat (2) @(negedge clk);
        rst = 1'b0;
        repeat (55) @(negedge clk);

        if (dut.u_csr_file.mcycle !== cycle_expected) begin
            $display("[FAIL] cycle: got=%0d expected=%0d",
                     dut.u_csr_file.mcycle, cycle_expected);
            errors = errors + 1;
        end
        if (dut.u_csr_file.minstret !== retire_expected) begin
            $display("[FAIL] instret: got=%0d expected=%0d",
                     dut.u_csr_file.minstret, retire_expected);
            errors = errors + 1;
        end
        if (dut.u_csr_file.stall_cycles !== stall_expected) begin
            $display("[FAIL] stall: got=%0d expected=%0d",
                     dut.u_csr_file.stall_cycles, stall_expected);
            errors = errors + 1;
        end
        if (stall_expected != 1 || store_retired != 1 || branch_retired == 0) begin
            $display("[FAIL] stimulus: stall=%0d store=%0d branch=%0d",
                     stall_expected, store_retired, branch_retired);
            errors = errors + 1;
        end
        if ((^dut.u_reg_file.regs[3]) === 1'bx ||
            (^dut.u_reg_file.regs[4]) === 1'bx ||
            (^dut.u_reg_file.regs[9]) === 1'bx ||
            (^dut.u_reg_file.regs[10]) === 1'bx ||
            dut.u_reg_file.regs[3] === 32'd0 ||
            dut.u_reg_file.regs[4] === 32'd0 ||
            dut.u_reg_file.regs[5] !== 32'd1 ||
            dut.u_reg_file.regs[6] !== 32'd0 ||
            dut.u_reg_file.regs[7] !== 32'd0 ||
            dut.u_reg_file.regs[8] !== 32'd0 ||
            dut.u_reg_file.regs[9] < dut.u_reg_file.regs[3] ||
            dut.u_reg_file.regs[10] < dut.u_reg_file.regs[4]) begin
            $display("[FAIL] software-visible counter CSR reads");
            errors = errors + 1;
        end

        // 第二段独立复位：验证机器态写高/低半字与只读别名共用同一计数值。
        @(negedge clk);
        rst = 1'b1;
        for (integer i = 0; i < 64; i = i + 1)
            inst_mem[i] = 32'h00000013;
        inst_mem[0] = 32'h00100093; // addi x1, x0, 1
        inst_mem[1] = {12'hb80, 5'd1, 3'b001, 5'd0, 7'h73}; // csrw mcycleh, x1
        inst_mem[2] = csrr(5'd2, 12'hc80); // cycleh
        inst_mem[3] = {12'hb82, 5'd1, 3'b001, 5'd0, 7'h73}; // csrw minstreth, x1
        inst_mem[4] = csrr(5'd3, 12'hc82); // instreth
        inst_mem[5] = {12'hb00, 5'd0, 3'b001, 5'd0, 7'h73}; // csrw mcycle, x0
        inst_mem[6] = csrr(5'd4, 12'hc00); // cycle
        inst_mem[7] = {12'hb02, 5'd0, 3'b001, 5'd0, 7'h73}; // csrw minstret, x0
        inst_mem[8] = csrr(5'd5, 12'hc02); // instret
        inst_mem[9]  = 32'hfff00093; // addi x1, x0, -1
        inst_mem[10] = {12'hb00, 5'd1, 3'b001, 5'd0, 7'h73}; // mcycle 低半写全 1
        inst_mem[11] = csrr(5'd6, 12'hc80); // 写入后的高半仍为 1
        inst_mem[12] = csrr(5'd7, 12'hc80); // 自增进位后高半为 2
        inst_mem[13] = {12'hb00, 5'd1, 3'b001, 5'd0, 7'h73}; // 再写低半全 1
        inst_mem[14] = {12'hb00, 5'd0, 3'b001, 5'd0, 7'h73}; // 紧邻写 0，旧值不应进位
        inst_mem[15] = csrr(5'd8, 12'hc80);
        inst_mem[16] = 32'h0000006f;
        repeat (2) @(negedge clk);
        rst = 1'b0;
        repeat (40) @(negedge clk);
        if (dut.u_reg_file.regs[2] !== 32'd1 ||
            dut.u_reg_file.regs[3] !== 32'd1 ||
            dut.u_reg_file.regs[6] !== 32'd1 ||
            dut.u_reg_file.regs[7] !== 32'd2 ||
            dut.u_reg_file.regs[8] !== 32'd2 ||
            dut.u_csr_file.mcycle[63:32] !== 32'd2 ||
            dut.u_csr_file.minstret[63:32] !== 32'd1 ||
            dut.u_reg_file.regs[4] !== 32'd0 ||
            dut.u_reg_file.regs[5] !== 32'd0 ||
            dut.u_csr_file.mcycle[31:0] >= cycle_expected ||
            dut.u_csr_file.minstret[31:0] >= retire_expected) begin
            $display("[FAIL] writable machine counters: x2=%h x3=%h x4=%h x5=%h cycle=%h instret=%h expected=(%0d,%0d)",
                     dut.u_reg_file.regs[2], dut.u_reg_file.regs[3],
                     dut.u_reg_file.regs[4], dut.u_reg_file.regs[5],
                     dut.u_csr_file.mcycle, dut.u_csr_file.minstret,
                     cycle_expected, retire_expected);
            errors = errors + 1;
        end
        if (errors == 0) begin
            $display("[TB PASS] tb_perf_counters");
            $finish;
        end else
            $fatal(1, "[TB FAIL] tb_perf_counters: %0d checks failed", errors);
    end
endmodule
