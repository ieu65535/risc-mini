`timescale 1ns/1ps

module tb_csr();

    // ==========================================
    // 1. 信号定义
    // ==========================================
    logic        clk;
    logic        rst;
    
    logic [31:0] inst_addr;
    logic [31:0] inst;
    
    // 测试不访问数据存储器：读数据固定为 0，其他信号由 CPU 驱动。
    logic [31:0] mem_addr;
    logic [31:0] mem_dout = 0;
    logic [31:0] mem_din;
    logic [3:0]  mem_we;
    integer      error_count = 0;
    
    // 指令存储器
    logic [31:0] inst_mem [0:255];

    // ==========================================
    // 2. 实例化流水线
    // ==========================================
    pipeline dut (
        .clk        (clk),
        .rst        (rst),
        .inst       (inst),
        .inst_addr  (inst_addr),
        .mem_dout   (mem_dout),
        .mem_din    (mem_din),
        .mem_addr   (mem_addr),
        .mem_we     (mem_we),
        .timer_int  (1'b0)
    );

    // ==========================================
    // 3. 组合逻辑读取指令 (0延迟)
    // ==========================================
    assign inst = inst_mem[inst_addr[9:2]];

    // ==========================================
    // 4. 时钟生成
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz
    end

    // ==========================================
    // 5. 测试主流程
    // ==========================================
    initial begin
`ifdef DUMP_WAVES
        $dumpfile("tb_csr.vcd");
        $dumpvars(0, tb_csr);
`endif

        // 初始化指令内存为 NOP (addi x0, x0, 0)
        for(int i=0; i<256; i++) inst_mem[i] = 32'h00000013; 
        
        // ---------------------------------------------------------
        // [基础测试]: 寄存器读写与位操作
        // ---------------------------------------------------------
        inst_mem[0] = 32'h12300313; // 00: addi x6, x0, 0x123 
        inst_mem[1] = 32'h34031073; // 04: csrw mscratch, x6  
        inst_mem[2] = 32'h340023f3; // 08: csrr x7, mscratch  -> 预期 x7 = 0x123
        inst_mem[3] = 32'h00800413; // 0C: addi x8, x0, 8     
        inst_mem[4] = 32'h30042073; // 10: csrs mstatus, x8   (置位位3)
        inst_mem[5] = 32'h300024f3; // 14: csrr x9, mstatus   -> 预期 x9 包含 8
        inst_mem[6] = 32'h30043073; // 18: csrc mstatus, x8   (清零位3)
        inst_mem[7] = 32'h30002573; // 1C: csrr x10, mstatus  -> 预期 x10 不含 8

        // ---------------------------------------------------------
        // [进阶测试1]: ALU -> CSR 的背靠背数据前递
        // ---------------------------------------------------------
        inst_mem[8]  = 32'h34500593; // 20: addi x11, x0, 0x345
        inst_mem[9]  = 32'h34159073; // 24: csrw mepc, x11    (立刻写CSR，需触发前递)
        inst_mem[10] = 32'h34102673; // 28: csrr x12, mepc    -> 预期 x12 = 0x345

        // ---------------------------------------------------------
        // [进阶测试2]: 立即数操作 (CSRRWI, CSRRSI, CSRRCI)
        // ---------------------------------------------------------
        inst_mem[11] = 32'h340fd073; // 2C: csrrwi x0, mscratch, 31 (写入立即数0x1F)
        inst_mem[12] = 32'h340026f3; // 30: csrr x13, mscratch  -> 预期 x13 = 31
        inst_mem[13] = 32'h3400e073; // 34: csrrsi x0, mscratch, 1  (31 | 1 = 31)
        inst_mem[14] = 32'h34087073; // 38: csrrci x0, mscratch, 16 (31 & ~16 = 15)
        inst_mem[15] = 32'h34002773; // 3C: csrr x14, mscratch  -> 预期 x14 = 15

        // ---------------------------------------------------------
        // [进阶测试3]: CSR -> ALU 的背靠背数据前递
        // ---------------------------------------------------------
        inst_mem[16] = 32'h340027f3; // 40: csrr x15, mscratch  (读出上述的15)
        inst_mem[17] = 32'h00178813; // 44: addi x16, x15, 1    (立刻加1) -> 预期 x16 = 16

        // ---------------------------------------------------------
        // [边界测试4]: x0 寄存器只读保护
        // ---------------------------------------------------------
        inst_mem[18] = 32'h34002073; // 48: csrr x0, mscratch   (试图把15写入x0)
        inst_mem[19] = 32'h00000893; // 4C: addi x17, x0, 0     -> 预期 x17 = 0
        
        // 复位系统
        rst = 1;
        #20;
        rst = 0;

        // 让流水线跑 50 个周期，确保所有指令走完 WB 阶段
        repeat(50) @(posedge clk);
        
        // ==========================================
        // 6. 自动化检查结果
        // ==========================================
        $display("\n========================================");
        $display("         CSR 全覆盖自动化验证报告         ");
        $display("========================================");

        // --- 基础测试检查 ---
        if (dut.u_reg_file.regs[7] === 32'h123) $display("[PASS] 基础读写: x7 = 0x123");
        else begin $display("[FAIL] 基础读写: x7 = 0x%h, 期望 0x123", dut.u_reg_file.regs[7]); error_count = error_count + 1; end

        if (dut.u_reg_file.regs[9] === 32'h8) $display("[PASS] CSRRS(置位): x9 = 0x8");
        else begin $display("[FAIL] CSRRS(置位): x9 = 0x%h, 期望 0x8", dut.u_reg_file.regs[9]); error_count = error_count + 1; end

        if (dut.u_reg_file.regs[10] === 32'h0) $display("[PASS] CSRRC(清零): x10 = 0x0");
        else begin $display("[FAIL] CSRRC(清零): x10 = 0x%h, 期望 0x0", dut.u_reg_file.regs[10]); error_count = error_count + 1; end

        // --- 进阶测试1检查 ---
        if (dut.u_reg_file.regs[12] === 32'h345) $display("[PASS] ALU->CSR前递: x12 = 0x345");
        else begin $display("[FAIL] ALU->CSR前递: x12 = 0x%h, 期望 0x345", dut.u_reg_file.regs[12]); error_count = error_count + 1; end

        // --- 进阶测试2检查 ---
        if (dut.u_reg_file.regs[13] === 32'h1F) $display("[PASS] CSRRWI(立即数写): x13 = 31");
        else begin $display("[FAIL] CSRRWI(立即数写): x13 = 0x%h, 期望 31", dut.u_reg_file.regs[13]); error_count = error_count + 1; end

        if (dut.u_reg_file.regs[14] === 32'hF) $display("[PASS] 立即数置位/清零: x14 = 15");
        else begin $display("[FAIL] 立即数置位/清零: x14 = 0x%h, 期望 15", dut.u_reg_file.regs[14]); error_count = error_count + 1; end

        // --- 进阶测试3检查 ---
        if (dut.u_reg_file.regs[16] === 32'h10) $display("[PASS] CSR->ALU前递: x16 = 16");
        else begin $display("[FAIL] CSR->ALU前递: x16 = 0x%h, 期望 16", dut.u_reg_file.regs[16]); error_count = error_count + 1; end

        // --- 边界测试4检查 ---
        if (dut.u_reg_file.regs[17] === 32'h0) $display("[PASS] x0寄存器保护: x17 = 0");
        else begin $display("[FAIL] x0寄存器保护: x17 = 0x%h, 期望 0", dut.u_reg_file.regs[17]); error_count = error_count + 1; end

        $display("========================================\n");
        if (error_count == 0) begin
            $display("[TB PASS] tb_csr");
            $finish;
        end else begin
            $fatal(1, "[TB FAIL] tb_csr: %0d checks failed", error_count);
        end
    end

endmodule
