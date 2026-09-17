`timescale 1ns/1ps

module tb_mtvec;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic timer_int = 1'b0;
    logic [31:0] inst_addr;
    logic [31:0] inst = 32'h00000013;
    logic [31:0] mem_din;
    logic [31:0] mem_addr;
    logic [3:0] mem_we;
    logic [31:0] inst_mem [0:255];
    integer cycles = 0;
    integer direct_traps = 0;
    integer vector_traps = 0;
    integer vector_visits = 0;
    integer i;

    pipeline dut (
        .clk(clk), .rst(rst), .timer_int(timer_int),
        .inst(inst), .mem_dout(32'b0), .inst_addr(inst_addr),
        .mem_din(mem_din), .mem_addr(mem_addr), .mem_we(mem_we)
    );

    always #5 clk = ~clk;
    always_ff @(posedge clk)
        inst <= inst_mem[inst_addr[9:2]];

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
                    if (dut.target_pc !== 32'h00000040)
                        $fatal(1, "[FAIL] ECALL target=%h, expected BASE=0x40", dut.target_pc);
                end else if (dut.trap_cause == 32'h80000007) begin
                    vector_traps <= vector_traps + 1;
                    if (dut.target_pc !== 32'h0000005c)
                        $fatal(1, "[FAIL] Timer target=%h, expected BASE+4*7=0x5c", dut.target_pc);
                end else
                    $fatal(1, "[FAIL] unexpected trap cause=%h pc=%h", dut.trap_cause, dut.pc_ex);
            end
            if (dut.pc == 32'h0000005c)
                vector_visits <= vector_visits + 1;
        end
    end

    initial begin
        for (i = 0; i < 256; i = i + 1)
            inst_mem[i] = 32'h00000013;

        // Direct: mtvec=0x40，ECALL 应到 BASE。
        inst_mem[0]  = 32'h04000093;        // addi x1,x0,0x40
        inst_mem[1]  = csrw(12'h305, 5'd1);
        inst_mem[2]  = 32'h00000073;        // ecall
        inst_mem[3]  = 32'h00100113;        // addi x2,x0,1
        inst_mem[4]  = jal_x0(0);           // 等待测试台放行

        // Vectored: mtvec=0x41，ECALL 仍应到 BASE，不到向量槽。
        inst_mem[8]  = 32'h04100093;        // addi x1,x0,0x41
        inst_mem[9]  = csrw(12'h305, 5'd1);
        inst_mem[10] = csrr(12'h305, 5'd6);
        inst_mem[11] = 32'h00000073;        // ecall
        inst_mem[12] = 32'h00200393;        // addi x7,x0,2
        inst_mem[13] = jal_x0(0);

        // 共用处理程序：中断保持 mepc，异常跳过 ecall 后 MRET。
        inst_mem[16] = csrr(12'h342, 5'd4); // csrr x4,mcause
        inst_mem[17] = csrr(12'h341, 5'd5); // csrr x5,mepc
        inst_mem[18] = 32'h00024463;        // blt x4,x0,+8
        inst_mem[19] = 32'h00428293;        // addi x5,x5,4
        inst_mem[20] = csrw(12'h341, 5'd5); // csrw mepc,x5
        inst_mem[21] = 32'h30200073;        // mret
        inst_mem[23] = jal_x0(-28);         // 0x5c: Timer 向量槽 -> 0x40

        // 使能全局中断和机器定时器中断，在 0x80 等待测试台脉冲。
        inst_mem[28] = 32'h00800413;        // addi x8,x0,8
        inst_mem[29] = csrs(12'h300, 5'd8); // mstatus.MIE
        inst_mem[30] = 32'h08000413;        // addi x8,x0,0x80
        inst_mem[31] = csrs(12'h304, 5'd8); // mie.MTIE
        inst_mem[32] = jal_x0(0);

        // 保留 MODE=2/3：本实现 WARL 为 Direct，并且读回 MODE=0。
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
            $fatal(1, "[FAIL] Direct ECALL: direct=%0d vector visits=%0d", direct_traps, vector_visits);
        inst_mem[4] = jal_x0(16);          // 0x10 -> 0x20

        wait (dut.u_reg_file.regs[7] === 32'd2);
        @(negedge clk);
        if (dut.u_reg_file.regs[6] !== 32'h41 || direct_traps != 2 || vector_visits != 0)
            $fatal(1, "[FAIL] Vectored ECALL: mtvec=%h direct=%0d vector visits=%0d",
                   dut.u_reg_file.regs[6], direct_traps, vector_visits);
        inst_mem[13] = jal_x0(60);         // 0x34 -> 0x70

        wait (dut.u_csr_file.mstatus[3] && dut.u_csr_file.mie[7] &&
              inst_addr == 32'h80);
        repeat (3) @(negedge clk);
        timer_int = 1'b1;
        @(negedge clk);
        timer_int = 1'b0;
        wait (vector_traps == 1 && vector_visits == 1);
        repeat (12) @(negedge clk);
        if (dut.u_reg_file.regs[4] !== 32'h80000007 || dut.csr_mip_mtip !== 1'b0 ||
            dut.u_csr_file.mstatus[3] !== 1'b1)
            $fatal(1, "[FAIL] Timer return: cause=%h pending=%b MIE=%b",
                   dut.u_reg_file.regs[4], dut.csr_mip_mtip, dut.u_csr_file.mstatus[3]);
        inst_mem[32] = jal_x0(16);         // 0x80 -> 0x90

        wait (dut.u_reg_file.regs[11] === 32'd1);
        @(negedge clk);
        if (dut.u_reg_file.regs[9] !== 32'h40 || dut.u_reg_file.regs[10] !== 32'h40 ||
            direct_traps != 3 || vector_traps != 1 || vector_visits != 1)
            $fatal(1, "[FAIL] WARL MODE: readback2=%h readback3=%h direct=%0d vector=%0d visits=%0d",
                   dut.u_reg_file.regs[9], dut.u_reg_file.regs[10],
                   direct_traps, vector_traps, vector_visits);

        $display("[TB PASS] tb_mtvec: Direct, Vectored exception/Timer, reserved MODE WARL");
        $finish;
    end
endmodule
