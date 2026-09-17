`timescale 1ns/1ps

module tb_csr_fields;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [31:0] inst = 32'h00000013;
    logic [31:0] inst_addr;
    logic [31:0] mem_din;
    logic [31:0] mem_addr;
    logic [3:0] mem_we;
    logic [31:0] inst_mem [0:255];
    integer cycles = 0;
    integer trap_count = 0;
    integer mret_count = 0;
    integer i;

    pipeline dut (
        .clk(clk), .rst(rst), .timer_int(1'b0),
        .inst(inst), .mem_dout(32'b0), .inst_addr(inst_addr),
        .mem_din(mem_din), .mem_addr(mem_addr), .mem_we(mem_we)
    );

    always #5 clk = ~clk;
    always_ff @(posedge clk)
        inst <= inst_mem[inst_addr[9:2]];

    function automatic [31:0] csrw(input [11:0] addr, input [4:0] rs1);
        csrw = {addr, rs1, 3'b001, 5'd0, 7'h73};
    endfunction

    function automatic [31:0] csrr(input [11:0] addr, input [4:0] rd);
        csrr = {addr, 5'd0, 3'b010, rd, 7'h73};
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            cycles <= 0;
            trap_count <= 0;
            mret_count <= 0;
        end else begin
            cycles <= cycles + 1;
            if (cycles >= 150)
                $fatal(1, "[TB TIMEOUT] tb_csr_fields exceeded 150 cycles");
            if (dut.trap_valid) begin
                trap_count <= trap_count + 1;
                if (dut.trap_cause !== 32'd11 || dut.target_pc !== 32'h40)
                    $fatal(1, "[FAIL] unexpected trap cause=%h target=%h",
                           dut.trap_cause, dut.target_pc);
            end
            if (dut.mret_valid) begin
                if (mret_count == 0 && dut.target_pc !== 32'h80)
                    $fatal(1, "[FAIL] first MRET target=%h, expected aligned 0x80", dut.target_pc);
                if (mret_count == 1 && dut.target_pc !== 32'h88)
                    $fatal(1, "[FAIL] second MRET target=%h, expected 0x88", dut.target_pc);
                mret_count <= mret_count + 1;
            end
        end
    end

    initial begin
        for (i = 0; i < 256; i = i + 1)
            inst_mem[i] = 32'h00000013;

        // 全 1 写入：只保留已实现的 MIE/MPIE/MPP 与 MTIE。
        inst_mem[0]  = 32'hfff00093;         // addi x1,x0,-1
        inst_mem[1]  = csrw(12'h300, 5'd1);  // mstatus <- all ones
        inst_mem[2]  = csrr(12'h300, 5'd2);
        inst_mem[3]  = csrw(12'h304, 5'd1);  // mie <- all ones
        inst_mem[4]  = csrr(12'h304, 5'd3);
        inst_mem[5]  = 32'h08300093;         // addi x1,x0,0x83
        inst_mem[6]  = csrw(12'h341, 5'd1);  // mepc 必须按 IALIGN=32 对齐
        inst_mem[7]  = csrr(12'h341, 5'd4);
        inst_mem[8]  = 32'h04000393;         // addi x7,x0,0x40
        inst_mem[9]  = csrw(12'h305, 5'd7);  // mtvec <- 0x40
        inst_mem[10] = 32'h00000293;         // addi x5,x0,0：错误路径哨兵
        inst_mem[11] = 32'h30200073;         // mret -> 0x80
        inst_mem[12] = 32'h00100293;         // 错误路径，不得写 x5

        // ECALL 到来时 MIE 关闭、MPIE 保存旧 MIE；Handler 修正 mepc 后 MRET。
        inst_mem[16] = csrr(12'h300, 5'd8); // 0x40: mstatus
        inst_mem[17] = csrr(12'h341, 5'd9); // 0x44: mepc
        inst_mem[18] = 32'h00048613;         // 0x48: addi x12,x9,0，保存原始 mepc
        inst_mem[19] = csrr(12'h342, 5'd10);// 0x4c: mcause
        inst_mem[20] = 32'h00448493;         // 0x50: addi x9,x9,4
        inst_mem[21] = csrw(12'h341, 5'd9); // 0x54: mepc <- 0x88
        inst_mem[22] = 32'h30200073;         // 0x58: mret -> 0x88

        inst_mem[32] = 32'h00100313;         // 0x80: addi x6,x0,1
        inst_mem[33] = 32'h00000073;         // 0x84: ecall
        inst_mem[34] = 32'h00100593;         // 0x88: addi x11,x0,1
        inst_mem[35] = 32'h0000006f;         // 0x8c: wait

        repeat (3) @(negedge clk);
        if (dut.u_csr_file.mstatus !== 32'h00001800)
            $fatal(1, "[FAIL] M-only MPP reset=%h, expected 0x1800", dut.u_csr_file.mstatus);
        rst = 1'b0;

        wait (dut.u_reg_file.regs[11] === 32'd1);
        repeat (3) @(negedge clk);
        if (dut.u_reg_file.regs[2] !== 32'h00001888 ||
            dut.u_reg_file.regs[3] !== 32'h00000080 ||
            dut.u_reg_file.regs[4] !== 32'h00000080 ||
            dut.u_reg_file.regs[5] !== 32'd0 ||
            dut.u_reg_file.regs[6] !== 32'd1 ||
            dut.u_reg_file.regs[8] !== 32'h00001880 ||
            dut.u_reg_file.regs[9] !== 32'h00000088 ||
            dut.u_reg_file.regs[10] !== 32'd11 ||
            dut.u_reg_file.regs[12] !== 32'h00000084 ||
            dut.u_csr_file.mstatus !== 32'h00001888 ||
            dut.u_csr_file.mepc !== 32'h00000088 ||
            trap_count != 1 || mret_count != 2)
            $fatal(1, "[FAIL] CSR state: x2=%h x3=%h x4=%h x5=%h x6=%h x8=%h x9=%h x10=%h x12=%h mstatus=%h mie=%h mepc=%h trap=%0d mret=%0d",
                   dut.u_reg_file.regs[2], dut.u_reg_file.regs[3],
                   dut.u_reg_file.regs[4], dut.u_reg_file.regs[5],
                   dut.u_reg_file.regs[6], dut.u_reg_file.regs[8],
                   dut.u_reg_file.regs[9], dut.u_reg_file.regs[10],
                   dut.u_reg_file.regs[12],
                   dut.u_csr_file.mstatus, dut.u_csr_file.mie,
                   dut.u_csr_file.mepc, trap_count, mret_count);

        $display("[TB PASS] tb_csr_fields: M-only fields, IALIGN=32 mepc, MRET and Trap state");
        $finish;
    end
endmodule
