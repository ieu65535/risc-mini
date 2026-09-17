`timescale 1ns/1ps

module tb_halfword;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [31:0] inst = 32'h00000013;
    logic [31:0] inst_addr;
    logic [31:0] mem_dout;
    logic [31:0] mem_din;
    logic [31:0] mem_addr;
    logic [3:0] mem_we;
    logic [31:0] inst_mem [0:255];
    integer cycles = 0;
    integer trap_count = 0;
    integer store_count = 0;
    integer i;

    pipeline dut (
        .clk(clk), .rst(rst), .timer_int(1'b0),
        .inst(inst), .mem_dout(mem_dout), .inst_addr(inst_addr),
        .mem_din(mem_din), .mem_addr(mem_addr), .mem_we(mem_we)
    );

    // 与 SoC 相同的一拍同步读、四字节写使能 RAM。
    ram u_ram (
        .clk(clk), .addr(mem_addr), .din(mem_din),
        .we(mem_we), .dout(mem_dout)
    );

    always #5 clk = ~clk;
    always_ff @(posedge clk)
        inst <= inst_mem[inst_addr[9:2]];

    function automatic [31:0] load_inst(
        input [2:0] funct3, input [4:0] rd, input [4:0] rs1, input integer offset
    );
        load_inst = {offset[11:0], rs1, funct3, rd, 7'h03};
    endfunction

    function automatic [31:0] store_inst(
        input [2:0] funct3, input [4:0] rs2, input [4:0] rs1, input integer offset
    );
        store_inst = {offset[11:5], rs2, rs1, funct3, offset[4:0], 7'h23};
    endfunction

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
            store_count <= 0;
        end else begin
            cycles <= cycles + 1;
            if (cycles >= 220)
                $fatal(1, "[TB TIMEOUT] tb_halfword exceeded 220 cycles");

            if (dut.trap_valid) begin
                case (trap_count)
                    0: if (dut.trap_cause !== 32'd4 || dut.pc_ex !== 32'h30 ||
                           dut.trap_tval !== 32'h20000001)
                           $fatal(1, "[FAIL] LH misaligned: cause=%h pc=%h tval=%h",
                                  dut.trap_cause, dut.pc_ex, dut.trap_tval);
                    1: if (dut.trap_cause !== 32'd4 || dut.pc_ex !== 32'h34 ||
                           dut.trap_tval !== 32'h20000003)
                           $fatal(1, "[FAIL] LHU misaligned: cause=%h pc=%h tval=%h",
                                  dut.trap_cause, dut.pc_ex, dut.trap_tval);
                    2: if (dut.trap_cause !== 32'd6 || dut.pc_ex !== 32'h38 ||
                           dut.trap_tval !== 32'h20000001)
                           $fatal(1, "[FAIL] SH+1 misaligned: cause=%h pc=%h tval=%h",
                                  dut.trap_cause, dut.pc_ex, dut.trap_tval);
                    3: if (dut.trap_cause !== 32'd6 || dut.pc_ex !== 32'h3c ||
                           dut.trap_tval !== 32'h20000003)
                           $fatal(1, "[FAIL] SH+3 misaligned: cause=%h pc=%h tval=%h",
                                  dut.trap_cause, dut.pc_ex, dut.trap_tval);
                    default: $fatal(1, "[FAIL] unexpected extra trap at %h", dut.pc_ex);
                endcase
                if (mem_we !== 4'b0000)
                    $fatal(1, "[FAIL] faulting instruction asserted mem_we=%b", mem_we);
                trap_count <= trap_count + 1;
            end

            if (|mem_we) begin
                if (store_count == 0 &&
                    (mem_addr !== 32'h20000000 || mem_we !== 4'b0011 ||
                     mem_din !== 32'h000080ff))
                    $fatal(1, "[FAIL] lower SH: addr=%h we=%b din=%h",
                           mem_addr, mem_we, mem_din);
                if (store_count == 1 &&
                    (mem_addr !== 32'h20000002 || mem_we !== 4'b1100 ||
                     mem_din !== 32'h7f010000))
                    $fatal(1, "[FAIL] upper SH: addr=%h we=%b din=%h",
                           mem_addr, mem_we, mem_din);
                if (store_count >= 2)
                    $fatal(1, "[FAIL] unexpected extra Store: addr=%h we=%b", mem_addr, mem_we);
                store_count <= store_count + 1;
            end
        end
    end

    initial begin
        for (i = 0; i < 256; i = i + 1)
            inst_mem[i] = 32'h00000013;
        // 小端字节序：地址 +0..+3 依次为 01, 7f, ff, 80。
        u_ram.ram[0] = 32'h80ff7f01;

        inst_mem[0]  = 32'h200000b7;          // lui x1,0x20000: RAM 基址
        inst_mem[1]  = 32'h10000793;          // addi x15,x0,0x100
        inst_mem[2]  = csrw(12'h305, 5'd15);  // mtvec = 0x100
        inst_mem[3]  = load_inst(3'b001, 5'd2, 5'd1, 0); // LH 低半，正数
        inst_mem[4]  = load_inst(3'b101, 5'd3, 5'd1, 0); // LHU 低半
        inst_mem[5]  = load_inst(3'b001, 5'd4, 5'd1, 2); // LH 高半，负数
        inst_mem[6]  = load_inst(3'b101, 5'd5, 5'd1, 2); // LHU 高半
        inst_mem[7]  = store_inst(3'b001, 5'd5, 5'd1, 0); // SH 低半
        inst_mem[8]  = store_inst(3'b001, 5'd2, 5'd1, 2); // SH 高半
        inst_mem[9]  = load_inst(3'b010, 5'd6, 5'd1, 0); // LW 交叉核对
        inst_mem[10] = 32'h04d00413;          // addi x8,x0,77：故障 LH 哨兵
        inst_mem[11] = 32'h05800493;          // addi x9,x0,88：故障 LHU 哨兵
        inst_mem[12] = load_inst(3'b001, 5'd8, 5'd1, 1); // 未对齐 LH
        inst_mem[13] = load_inst(3'b101, 5'd9, 5'd1, 3); // 未对齐 LHU
        inst_mem[14] = store_inst(3'b001, 5'd5, 5'd1, 1); // 未对齐 SH
        inst_mem[15] = store_inst(3'b001, 5'd2, 5'd1, 3); // 跨字边界 SH
        inst_mem[16] = load_inst(3'b010, 5'd10, 5'd1, 0);
        inst_mem[17] = 32'h00100593;          // 完成标记 x11=1
        inst_mem[18] = 32'h0000006f;          // 等待测试台

        // 简单 Trap Handler：读取 mepc/mtval，跳过故障指令后返回。
        inst_mem[64] = csrr(12'h342, 5'd20);
        inst_mem[65] = csrr(12'h341, 5'd21);
        inst_mem[66] = csrr(12'h343, 5'd22);
        inst_mem[67] = 32'h004a8a93;          // addi x21,x21,4
        inst_mem[68] = csrw(12'h341, 5'd21);
        inst_mem[69] = 32'h30200073;          // mret

        repeat (3) @(negedge clk);
        rst = 1'b0;
        wait (dut.u_reg_file.regs[11] === 32'd1);
        repeat (3) @(negedge clk);

        if (dut.u_reg_file.regs[2] !== 32'h00007f01 ||
            dut.u_reg_file.regs[3] !== 32'h00007f01 ||
            dut.u_reg_file.regs[4] !== 32'hffff80ff ||
            dut.u_reg_file.regs[5] !== 32'h000080ff ||
            dut.u_reg_file.regs[6] !== 32'h7f0180ff ||
            dut.u_reg_file.regs[8] !== 32'd77 ||
            dut.u_reg_file.regs[9] !== 32'd88 ||
            dut.u_reg_file.regs[10] !== 32'h7f0180ff ||
            u_ram.ram[0] !== 32'h7f0180ff ||
            trap_count != 4 || store_count != 2)
            $fatal(1, "[FAIL] halfword result: LH=%h LHU=%h LH+2=%h LHU+2=%h LW=%h RAM=%h trap=%0d store=%0d",
                   dut.u_reg_file.regs[2], dut.u_reg_file.regs[3],
                   dut.u_reg_file.regs[4], dut.u_reg_file.regs[5],
                   dut.u_reg_file.regs[6], u_ram.ram[0], trap_count, store_count);

        $display("[TB PASS] tb_halfword: LH/LHU/SH low/high lanes and misaligned Trap");
        $finish;
    end
endmodule
