`timescale 1ns / 1ps

module tb_csr_pipeline();

    // -----------------------------------------------------------
    // 1. 信号定义
    // -----------------------------------------------------------
    logic clk;
    logic rst;
    logic rxd;

    logic [31:0] inst;
    logic [31:0] inst_addr;

    logic [31:0] mem_dout;
    logic [31:0] mem_din;
    logic [31:0] mem_addr;
    logic [ 3:0] mem_we;

    // -----------------------------------------------------------
    // 2. 待测模块实例化 (DUT)
    // -----------------------------------------------------------
    pipeline dut(
        .clk       (clk),
        .rst       (rst),
        .inst      (inst),
        .inst_addr (inst_addr),
        .mem_dout  (mem_dout),
        .mem_din   (mem_din),
        .mem_addr  (mem_addr),
        .mem_we    (mem_we),
        .rxd       (rxd)
    );

    // -----------------------------------------------------------
    // 3. 时钟与简易指令存储器 (IMEM)
    // -----------------------------------------------------------
    always #5 clk = ~clk; // 100MHz 

    logic [31:0] inst_mem [0:255]; // 1KB 的简易指令内存

    // 组合逻辑读取指令，模拟真实的 IF 阶段取指
    assign inst = inst_mem[inst_addr[9:2]]; 

    wire [31:0] probe_x3 = dut.u_reg_file.regs[3];
    wire [31:0] probe_x6 = dut.u_reg_file.regs[6];
    wire [31:0] probe_x7 = dut.u_reg_file.regs[7];

    // -----------------------------------------------------------
    // 4. 指令自动生成工具函数 (摆脱手搓机器码的痛苦)
    // -----------------------------------------------------------
    function [31:0] gen_addi(input [4:0] rd, input [4:0] rs1, input [11:0] imm);
        return {imm, rs1, 3'b000, rd, 7'b0010011};
    endfunction

    function [31:0] gen_csr(input [2:0] funct3, input [11:0] csr, input [4:0] rs1_uimm, input [4:0] rd);
        return {csr, rs1_uimm, funct3, rd, 7'b1110011};
    endfunction

    function [31:0] gen_ecall();
        //return 32'h00000073;
        return 32'h00000013;
    endfunction

    function [31:0] gen_mret();
        return 32'h30200073;
    endfunction

    // -----------------------------------------------------------
    // 5. 测试序列加载与验证逻辑
    // -----------------------------------------------------------
    initial begin
        // (1) 初始化环境
        clk = 0;
        rst = 1;
        rxd = 1; // 默认拉高 (空闲)
        mem_dout = 32'h0;

        // 全局填充 NOP (addi x0, x0, 0) 以防止跑飞触发异常
        for (int i = 0; i < 256; i++) begin
            inst_mem[i] = 32'h00000013; 
        end

        // -------------------------------------------------------
        // (2) 烧录测试程序 (直接向数组写入机器码)
        // -------------------------------------------------------
        // 地址映射: inst_addr = index * 4
        
        // --- 阶段 A: 基础 CSRRW 读写与寄存器冲突截胡 (Forwarding) 测试 ---
        // PC=0x00 (idx=0): addi x2, x0, 0x123
        inst_mem[0] = gen_addi(5'd2, 5'd0, 12'h123); 
        // PC=0x04 (idx=1): csrrw x0, mie, x2   (mie = 0x123)
        inst_mem[1] = gen_csr(3'b001, 12'h304, 5'd2, 5'd0);

        //inst_mem[2] = 32'h00000013; 
        // PC=0x08 (idx=2): csrrw x3, mie, x0   (x3 = 0x123，这里会触发截胡测试！)
        inst_mem[2] = gen_csr(3'b001, 12'h304, 5'd0, 5'd3);

        // --- 阶段 B: CSRRS / CSRRC 按位运算测试 ---
        // PC=0x0C (idx=3): addi x4, x0, 0x011
        inst_mem[3] = gen_addi(5'd4, 5'd0, 12'h011);
        // PC=0x10 (idx=4): csrrs x0, mie, x4   (mie = 0x123 | 0x011 = 0x133)
        inst_mem[4] = gen_csr(3'b010, 12'h304, 5'd4, 5'd0);
        // PC=0x14 (idx=5): addi x5, x0, 0x020
        inst_mem[5] = gen_addi(5'd5, 5'd0, 12'h020);
        // PC=0x18 (idx=6): csrrc x0, mie, x5   (mie = 0x133 & ~0x020 = 0x113)
        inst_mem[6] = gen_csr(3'b011, 12'h304, 5'd5, 5'd0);

        // --- 阶段 C: 立即数操作 (CSRRWI/CSRRSI/CSRRCI) ---
        // PC=0x1C (idx=7): csrrwi x0, mie, 5   (mie = 5)
        inst_mem[7] = gen_csr(3'b101, 12'h304, 5'd5, 5'd0);
        // PC=0x20 (idx=8): csrrsi x0, mie, 2   (mie = 5 | 2 = 7)
        inst_mem[8] = gen_csr(3'b110, 12'h304, 5'd2, 5'd0);
        // PC=0x24 (idx=9): csrrci x0, mie, 1   (mie = 7 & ~1 = 6)
        inst_mem[9] = gen_csr(3'b111, 12'h304, 5'd1, 5'd0);
        // PC=0x28 (idx=10): csrrw x6, mie, x0  (x6 = 6，用于验证最后结果)
        inst_mem[10]= gen_csr(3'b001, 12'h304, 5'd0, 5'd6);

        // --- 阶段 D: 中断初始化 ---
    
        // 1. 开启全局中断：写入 mstatus (0x300) 的第 3 位
        // CSRRWI (3'b101): 直接用立即数 8 (5'd8) 写入 0x300
        inst_mem[11] = gen_csr(3'b101, 12'h300, 5'd8, 5'd0); 

        // 2. 开启外部中断：写入 mie (0x304) 的第 11 位 (值为 0x800)
        // 因为 0x800 超出了 CSRRWI 的 5 位立即数范围，必须先存入普通寄存器 (借用 x5)
        // 12'h800 符号扩展后是 0xFFFFF800，第 11 位正好是 1，满足触发条件
        inst_mem[12] = gen_addi(5'd5, 5'd0, 12'h800); 

        // CSRRW (3'b001): 将 x5 的值写入 mie (0x304)
        inst_mem[13] = gen_csr(3'b001, 12'h304, 5'd5, 5'd0); 

        // 可以在这里加几条 NOP 防止后面空洞导致非法指令异常
        inst_mem[14] = 32'h00000013;
        inst_mem[15] = 32'h00000013;

        // --- Trap Handler (保持不变，放在 0x200 入口) ---
        // PC=0x200 (idx=128): addi x7, x0, 0x999
        inst_mem[128] = gen_addi(5'd7, 5'd0, 12'h999); 
        // PC=0x204 (idx=129): mret
        inst_mem[129] = gen_mret();


        // -------------------------------------------------------
        // (3) 开始运行与监控
        // -------------------------------------------------------
        #15 rst = 0; // 释放复位信号

        // 监控 MIE 和主要测试寄存器的变化
        $display("================== 仿真开始 ==================");
        $monitor("Time=%0t | PC=%h | mie=%h | mtvec=%h | mepc=%h | x3=%h | x6=%h | x7=%h", 
                 $time, dut.pc, dut.u_csr_regfile.mie, dut.u_csr_regfile.mtvec, 
                 dut.u_csr_regfile.mepc, probe_x3, probe_x6, probe_x7);

        // 等待足够周期让指令全部流过流水线
        #500; 

        // 验证外部中断
        $display("\n================== 触发外部中断 (RXD) ==================");
        // 模拟 UART 发送导致 rxd 拉低触发中断 (假设需要跨时钟域同步)
        rxd = 0; 
        #30 rxd = 1;

        #300; // 等待中断处理流过

        $display("\n================== 仿真结束 ==================");
        $finish;
    end

    // 获取寄存器值的 Helper function
    // 注意：需根据你实际的 reg_file 内部数组名进行修改 (假设数组名为 regs 或者 rf)
    // function [31:0] get_reg(input integer idx);
    //     // 如果你的 reg_file 模块里数组叫 rf：
    //     // return dut.u_reg_file.rf[idx];
        
    //     // 这里用一种保守的方式避免编译报错，如果支持：
    //     return dut.u_reg_file.regs[idx]; 
    // endfunction

endmodule
