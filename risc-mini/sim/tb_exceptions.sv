`timescale 1ns/1ps

module tb_exceptions;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [31:0] inst;
    logic [31:0] inst_addr;
    logic [31:0] inst_mem [0:255];
    integer cycles = 0;
    integer traps = 0;
    integer i;

    assign inst = inst_mem[inst_addr[9:2]];

    pipeline dut (
        .clk(clk), .rst(rst), .timer_int(1'b0),
        .inst(inst), .inst_ready(1'b1), .inst_addr(inst_addr),
        .mem_dout(32'b0), .mem_ready(1'b1), .mem_en(),
        .mem_din(), .mem_addr(), .mem_we()
    );

    always #5 clk = ~clk;

    function automatic [31:0] csrw(input [11:0] addr, input [4:0] rs1);
        csrw = {addr, rs1, 3'b001, 5'd0, 7'h73};
    endfunction

    function automatic [31:0] csrr(input [11:0] addr, input [4:0] rd);
        csrr = {addr, 5'd0, 3'b010, rd, 7'h73};
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            cycles <= 0;
            traps <= 0;
        end else begin
            cycles <= cycles + 1;
            if (cycles >= 220)
                $fatal(1, "[TB TIMEOUT] tb_exceptions");
            if (dut.trap_valid) begin
                case (traps)
                    0: if (dut.trap_cause !== 32'd2 || dut.pc_ex !== 32'h0c ||
                           dut.trap_tval !== 32'hffffffff)
                           $fatal(1, "[FAIL] generic illegal trap");
                    1: if (dut.trap_cause !== 32'd3 || dut.pc_ex !== 32'h10 ||
                           dut.trap_tval !== 32'h0)
                           $fatal(1, "[FAIL] EBREAK trap");
                    2: if (dut.trap_cause !== 32'd2 || dut.pc_ex !== 32'h14 ||
                           dut.trap_tval !== 32'h30602ef3)
                           $fatal(1, "[FAIL] unsupported CSR trap");
                    3: if (dut.trap_cause !== 32'd2 || dut.pc_ex !== 32'h1c ||
                           dut.trap_tval !== 32'hf1471ef3)
                           $fatal(1, "[FAIL] read-only CSR write trap");
                    4: if (dut.trap_cause !== 32'd0 || dut.pc_ex !== 32'h20 ||
                           dut.trap_tval !== 32'h22)
                           $fatal(1, "[FAIL] instruction target alignment trap");
                    default: $fatal(1, "[FAIL] unexpected extra trap");
                endcase
                if (dut.target_pc !== 32'h100)
                    $fatal(1, "[FAIL] trap target=%h", dut.target_pc);
                traps <= traps + 1;
            end
        end
    end

    initial begin
        for (i = 0; i < 256; i = i + 1)
            inst_mem[i] = 32'h00000013;

        inst_mem[0]  = 32'h10000093; // mtvec = 0x100
        inst_mem[1]  = csrw(12'h305, 5'd1);
        inst_mem[2]  = 32'h05a00e93; // x29 哨兵
        inst_mem[3]  = 32'hffffffff; // 非法指令
        inst_mem[4]  = 32'h00100073; // ebreak
        inst_mem[5]  = 32'h30602ef3; // 未实现 CSR 0x306，rd=x29
        inst_mem[6]  = 32'hf1402f73; // 合法读取 mhartid -> x30
        inst_mem[7]  = 32'hf1471ef3; // 非法写只读 mhartid，rd=x29
        inst_mem[8]  = 32'h0020006f; // JAL 目标 0x22，IALIGN=32 异常
        inst_mem[9]  = 32'h00100d93; // 完成标志 x27=1
        inst_mem[10] = 32'h0000006f;

        // 通用 Handler：保存现场，跳过故障指令后返回。
        inst_mem[64] = csrr(12'h342, 5'd20);
        inst_mem[65] = csrr(12'h341, 5'd21);
        inst_mem[66] = csrr(12'h343, 5'd22);
        inst_mem[67] = 32'h004a8a93;
        inst_mem[68] = csrw(12'h341, 5'd21);
        inst_mem[69] = 32'h30200073;

        repeat (3) @(negedge clk);
        rst = 1'b0;
        wait (dut.u_reg_file.regs[27] === 32'd1);
        repeat (3) @(negedge clk);

        if (traps != 5 || dut.u_reg_file.regs[29] !== 32'h5a ||
            dut.u_reg_file.regs[30] !== 32'h0 ||
            dut.u_reg_file.regs[20] !== 32'd0 ||
            dut.u_reg_file.regs[21] !== 32'h24 ||
            dut.u_reg_file.regs[22] !== 32'h22)
            $fatal(1, "[FAIL] exception result traps=%0d x29=%h x30=%h cause=%h mepc_next=%h mtval=%h",
                   traps, dut.u_reg_file.regs[29], dut.u_reg_file.regs[30],
                   dut.u_reg_file.regs[20], dut.u_reg_file.regs[21],
                   dut.u_reg_file.regs[22]);

        $display("[TB PASS] tb_exceptions");
        $finish;
    end
endmodule
