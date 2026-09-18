`timescale 1ns/1ps

module tb_mtvec;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic timer_int = 1'b0;
    logic [31:0] inst_addr;
    logic [31:0] inst;
    logic [31:0] inst_mem [0:255];
    integer cycles = 0;
    integer direct_traps = 0;
    integer vector_traps = 0;
    integer vector_visits = 0;
    integer i;

    assign inst = inst_mem[inst_addr[9:2]];

    pipeline dut (
        .clk(clk), .rst(rst), .timer_int(timer_int),
        .inst(inst), .inst_ready(1'b1), .inst_addr(inst_addr),
        .mem_dout(32'b0), .mem_ready(1'b1), .mem_en(),
        .mem_din(), .mem_addr(), .mem_we()
    );

    always #5 clk = ~clk;

    function automatic [31:0] jal_x0(input integer offset);
        logic [20:0] imm;
        begin
            imm = offset[20:0];
            jal_x0 = {imm[20], imm[10:1], imm[11], imm[19:12], 5'd0, 7'h6f};
        end
    endfunction

    function automatic [31:0] csrw(input [11:0] addr, input [4:0] rs1);
        csrw = {addr, rs1, 3'b001, 5'd0, 7'h73};
    endfunction

    function automatic [31:0] csrr(input [11:0] addr, input [4:0] rd);
        csrr = {addr, 5'd0, 3'b010, rd, 7'h73};
    endfunction

    function automatic [31:0] csrs(input [11:0] addr, input [4:0] rs1);
        csrs = {addr, rs1, 3'b010, 5'd0, 7'h73};
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            cycles <= 0;
            direct_traps <= 0;
            vector_traps <= 0;
            vector_visits <= 0;
        end else begin
            cycles <= cycles + 1;
            if (cycles >= 250)
                $fatal(1, "[TB TIMEOUT] tb_mtvec exceeded 250 cycles");
            if (dut.trap_valid) begin
                if (dut.trap_cause == 32'd11) begin
                    direct_traps <= direct_traps + 1;
                    if (dut.target_pc !== 32'h40)
                        $fatal(1, "[FAIL] ECALL target=%h", dut.target_pc);
                end else if (dut.trap_cause == 32'h80000007) begin
                    vector_traps <= vector_traps + 1;
                    if (dut.target_pc !== 32'h5c)
                        $fatal(1, "[FAIL] Timer target=%h", dut.target_pc);
                end else
                    $fatal(1, "[FAIL] unexpected trap cause=%h", dut.trap_cause);
            end
            if (dut.pc == 32'h5c)
                vector_visits <= vector_visits + 1;
        end
    end

    initial begin
        for (i = 0; i < 256; i = i + 1)
            inst_mem[i] = 32'h00000013;

        // Direct 模式：同步异常跳到 BASE。
        inst_mem[0]  = 32'h04000093;
        inst_mem[1]  = csrw(12'h305, 5'd1);
        inst_mem[2]  = 32'h00000073;
        inst_mem[3]  = 32'h00100113;
        inst_mem[4]  = jal_x0(0);

        // Vectored 模式：同步异常仍跳 BASE。
        inst_mem[8]  = 32'h04100093;
        inst_mem[9]  = csrw(12'h305, 5'd1);
        inst_mem[10] = csrr(12'h305, 5'd6);
        inst_mem[11] = 32'h00000073;
        inst_mem[12] = 32'h00200393;
        inst_mem[13] = jal_x0(0);

        // 共用 Handler；Timer 向量槽 0x5c 跳回 BASE。
        inst_mem[16] = csrr(12'h342, 5'd4);
        inst_mem[17] = csrr(12'h341, 5'd5);
        inst_mem[18] = 32'h00024463;
        inst_mem[19] = 32'h00428293;
        inst_mem[20] = csrw(12'h341, 5'd5);
        inst_mem[21] = 32'h30200073;
        inst_mem[23] = jal_x0(-28);

        // 开启 MIE/MTIE 并等待 Timer。
        inst_mem[28] = 32'h00800413;
        inst_mem[29] = csrs(12'h300, 5'd8);
        inst_mem[30] = 32'h08000413;
        inst_mem[31] = csrs(12'h304, 5'd8);
        inst_mem[32] = jal_x0(0);

        // MODE=2/3 按 WARL 收敛到 Direct。
        inst_mem[36] = 32'h04200093;
        inst_mem[37] = csrw(12'h305, 5'd1);
        inst_mem[38] = csrr(12'h305, 5'd9);
        inst_mem[39] = 32'h04300093;
        inst_mem[40] = csrw(12'h305, 5'd1);
        inst_mem[41] = csrr(12'h305, 5'd10);
        inst_mem[42] = 32'h00000073;
        inst_mem[43] = 32'h00100593;
        inst_mem[44] = jal_x0(0);

        repeat (3) @(negedge clk);
        rst = 1'b0;

        wait (dut.u_reg_file.regs[2] === 32'd1);
        @(negedge clk);
        if (direct_traps != 1 || vector_visits != 0)
            $fatal(1, "[FAIL] Direct ECALL");
        inst_mem[4] = jal_x0(16);

        wait (dut.u_reg_file.regs[7] === 32'd2);
        @(negedge clk);
        if (dut.u_reg_file.regs[6] !== 32'h41 || direct_traps != 2 || vector_visits != 0)
            $fatal(1, "[FAIL] Vectored ECALL");
        inst_mem[13] = jal_x0(60);

        wait (dut.csr_mstatus_mie && dut.csr_mie_mtie && inst_addr == 32'h80);
        repeat (3) @(negedge clk);
        timer_int = 1'b1;
        @(negedge clk);
        timer_int = 1'b0;
        wait (vector_traps == 1 && vector_visits == 1);
        repeat (12) @(negedge clk);
        if (dut.u_reg_file.regs[4] !== 32'h80000007 || dut.csr_mip_mtip ||
            !dut.u_csr_file.mstatus[3])
            $fatal(1, "[FAIL] Timer return");
        inst_mem[32] = jal_x0(16);

        wait (dut.u_reg_file.regs[11] === 32'd1);
        @(negedge clk);
        if (dut.u_reg_file.regs[9] !== 32'h40 || dut.u_reg_file.regs[10] !== 32'h40 ||
            direct_traps != 3 || vector_traps != 1 || vector_visits < 1)
            $fatal(1, "[FAIL] mtvec WARL result: x9=%h x10=%h direct=%0d vector=%0d visits=%0d",
                   dut.u_reg_file.regs[9], dut.u_reg_file.regs[10],
                   direct_traps, vector_traps, vector_visits);

        $display("[TB PASS] tb_mtvec");
        $finish;
    end
endmodule
