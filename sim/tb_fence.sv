`timescale 1ns/1ps

module tb_fence;
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
    integer traps = 0;
    integer stores = 0;
    integer fences_retired = 0;
    integer i;

    pipeline dut (
        .clk(clk), .rst(rst), .timer_int(1'b0),
        .inst(inst), .mem_dout(mem_dout), .inst_addr(inst_addr),
        .mem_din(mem_din), .mem_addr(mem_addr), .mem_we(mem_we)
    );
    ram u_ram (
        .clk(clk), .addr(mem_addr), .din(mem_din),
        .we(mem_we), .dout(mem_dout)
    );

    always #5 clk = ~clk;
    always_ff @(posedge clk)
        inst <= inst_mem[inst_addr[9:2]];

    function automatic [31:0] fence_inst(
        input [3:0] fm, input [3:0] pred, input [3:0] succ,
        input [4:0] rs1, input [4:0] rd
    );
        fence_inst = {fm, pred, succ, rs1, 3'b000, rd, 7'h0f};
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            cycles <= 0;
            traps <= 0;
            stores <= 0;
            fences_retired <= 0;
        end else begin
            cycles <= cycles + 1;
            if (cycles >= 180)
                $fatal(1, "[TB TIMEOUT] tb_fence exceeded 180 cycles");
            if (inst_addr[31:10] !== 22'd0)
                $fatal(1, "[FAIL] fetch outside ROM: %h", inst_addr);
            if (dut.valid_wb &&
                (dut.pc_wb == 32'h18 || dut.pc_wb == 32'h20 ||
                 dut.pc_wb == 32'h24))
                fences_retired <= fences_retired + 1;
            if (dut.trap_valid) begin
                if (dut.trap_cause !== 32'd2 || dut.pc_ex !== 32'h2c ||
                    dut.trap_tval !== 32'h0000100f || traps != 0 ||
                    mem_we !== 4'b0000)
                    $fatal(1, "[FAIL] FENCE.I trap: cause=%h pc=%h tval=%h count=%0d",
                           dut.trap_cause, dut.pc_ex, dut.trap_tval, traps);
                traps <= traps + 1;
            end
            if (|mem_we) begin
                if (stores != 0 || mem_addr !== 32'h20000000 ||
                    mem_we !== 4'b1111 || mem_din !== 32'h0000005a)
                    $fatal(1, "[FAIL] Store around FENCE: addr=%h we=%b data=%h",
                           mem_addr, mem_we, mem_din);
                stores <= stores + 1;
            end
        end
    end

    initial begin
        for (i = 0; i < 256; i = i + 1)
            inst_mem[i] = 32'h00000013;
        u_ram.ram[0] = 32'd0;

        inst_mem[0]  = 32'h200000b7; // lui x1,0x20000
        inst_mem[1]  = 32'h10000793; // addi x15,x0,0x100
        inst_mem[2]  = 32'h30579073; // csrw mtvec,x15
        inst_mem[3]  = 32'h05a00113; // addi x2,x0,0x5a
        inst_mem[4]  = 32'h06600293; // addi x5,x0,0x66
        inst_mem[5]  = 32'h0020a023; // sw x2,0(x1)
        inst_mem[6]  = fence_inst(4'h0, 4'h3, 4'h3, 5'd0, 5'd0); // fence rw,rw
        inst_mem[7]  = 32'h0000a183; // lw x3,0(x1)
        inst_mem[8]  = fence_inst(4'h8, 4'h3, 4'h3, 5'd0, 5'd0); // fence.tso
        inst_mem[9]  = fence_inst(4'hf, 4'h3, 4'h3, 5'd6, 5'd5); // 保留 fm/rs1/rd
        inst_mem[10] = 32'h00700213; // addi x4,x0,7
        inst_mem[11] = 32'h0000100f; // FENCE.I 不在当前 ISA 中
        inst_mem[12] = 32'h00100393; // addi x7,x0,1：完成标记
        inst_mem[13] = 32'h0000006f; // 等待测试台

        // Handler 跳过不支持的 FENCE.I，然后返回。
        inst_mem[64] = 32'h34202a73; // csrr x20,mcause
        inst_mem[65] = 32'h34102af3; // csrr x21,mepc
        inst_mem[66] = 32'h34302b73; // csrr x22,mtval
        inst_mem[67] = 32'h004a8a93; // addi x21,x21,4
        inst_mem[68] = 32'h341a9073; // csrw mepc,x21
        inst_mem[69] = 32'h30200073; // mret

        repeat (3) @(negedge clk);
        rst = 1'b0;
        wait (dut.u_reg_file.regs[7] === 32'd1);
        repeat (3) @(negedge clk);
        if (traps != 1 || stores != 1 || fences_retired != 3 ||
            dut.u_reg_file.regs[3] !== 32'h0000005a ||
            dut.u_reg_file.regs[4] !== 32'd7 ||
            dut.u_reg_file.regs[5] !== 32'h00000066 ||
            dut.u_reg_file.regs[20] !== 32'd2 ||
            dut.u_reg_file.regs[21] !== 32'h30 ||
            dut.u_reg_file.regs[22] !== 32'h0000100f ||
            u_ram.ram[0] !== 32'h0000005a)
            $fatal(1, "[FAIL] FENCE result: trap=%0d store=%0d retire=%0d x3=%h x4=%h x5=%h cause=%h mepc=%h mtval=%h RAM=%h",
                   traps, stores, fences_retired, dut.u_reg_file.regs[3],
                   dut.u_reg_file.regs[4], dut.u_reg_file.regs[5],
                   dut.u_reg_file.regs[20], dut.u_reg_file.regs[21],
                   dut.u_reg_file.regs[22], u_ram.ram[0]);
        $display("[TB PASS] tb_fence: FENCE/FENCE.TSO retire; FENCE.I traps");
        $finish;
    end
endmodule
