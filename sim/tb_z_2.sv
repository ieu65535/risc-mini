`timescale 1ns / 1ps

module tb_pipeline();

    // ==========================================
    // 信号声明
    // ==========================================
    logic        clk;
    logic        rst;
    
    logic [31:0] inst;
    logic [31:0] inst_addr;
    
    logic [31:0] mem_dout;
    logic [31:0] mem_din;
    logic [31:0] mem_addr;
    logic [ 3:0] mem_we;
    
    logic        rxd;

    // ==========================================
    // 同步内存模型 (第一拍给地址，第二拍出数据)
    // ==========================================
    logic [31:0] imem [0:1023]; // 4KB 指令内存
    logic [31:0] dmem [0:1023]; // 4KB 数据内存

    // 初始化内存为 NOP 指令 (addi x0, x0, 0)
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            imem[i] = 32'h00000013;
            dmem[i] = 32'h0;
        end
    end

    // 1. 同步指令内存 (IMEM)
    always_ff @(posedge clk) begin
        inst <= imem[inst_addr[11:2]]; 
    end

    // 2. 同步数据内存 (DMEM)
    always_ff @(posedge clk) begin
        if (mem_we != 4'b0000) begin
            if (mem_we[0]) dmem[mem_addr[11:2]][7:0]   <= mem_din[7:0];
            if (mem_we[1]) dmem[mem_addr[11:2]][15:8]  <= mem_din[15:8];
            if (mem_we[2]) dmem[mem_addr[11:2]][23:16] <= mem_din[23:16];
            if (mem_we[3]) dmem[mem_addr[11:2]][31:24] <= mem_din[31:24];
        end
        mem_dout <= dmem[mem_addr[11:2]];
    end

    // ==========================================
    // 待测设计 (DUT) 实例化
    // ==========================================
    pipeline uut (
        .clk        (clk),
        .rst        (rst),
        .inst       (inst),
        .inst_addr  (inst_addr),
        .mem_dout   (mem_dout),
        .mem_din    (mem_din),
        .mem_addr   (mem_addr),
        .mem_we     (mem_we),
        .rxd        (rxd)
    );

    // ==========================================
    // 时钟生成
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz (10ns 周期)
    end

    // ==========================================
    // 检查验证 Task 集合
    // ==========================================
    
    task check_reg(input [4:0] reg_addr, input [31:0] expected, input string test_name);
        begin
            repeat(7) @(posedge clk); 
            // ⚠️如果你的寄存器堆内部数组名不是 regs，请修改这里
            if (uut.u_reg_file.regs[reg_addr] === expected) begin
                $display("[成功] %s : 寄存器 x%0d 值匹配 (0x%h)", test_name, reg_addr, expected);
            end else begin
                $display("[失败] %s : 寄存器 x%0d 期望值: 0x%h, 实际值: 0x%h", test_name, reg_addr, expected, uut.u_reg_file.regs[reg_addr]);
            end
        end
    endtask

    task check_mem(input [31:0] addr, input [31:0] expected, input string test_name);
        begin
            repeat(5) @(posedge clk);
            if (dmem[addr[11:2]] === expected) begin
                $display("[成功] %s : 内存地址 0x%h 值匹配 (0x%h)", test_name, addr, expected);
            end else begin
                $display("[失败] %s : 内存地址 0x%h 期望值: 0x%h, 实际值: 0x%h", test_name, addr, expected, dmem[addr[11:2]]);
            end
        end
    endtask

    task check_csr_mtvec(input [31:0] expected, input string test_name);
        begin
            repeat(5) @(posedge clk);
            // 直接读取 csr_regfile 内部的 mtvec 变量
            if (uut.u_csr_regfile.mtvec === expected) begin
                $display("[成功] %s : CSR mtvec 值匹配 (0x%h)", test_name, expected);
            end else begin
                $display("[失败] %s : CSR mtvec 期望值: 0x%h, 实际值: 0x%h", test_name, expected, uut.u_csr_regfile.mtvec);
            end
        end
    endtask

    integer timeout_cnt = 0;
    // ==========================================
    // 测试主流程
    // ==========================================
    initial begin
        rst = 1;
        rxd = 1; // 外部拉高，防止误触发

        imem[0] = 32'h04000093; // ADDI x1, x0, 64 (0x40)
        imem[1] = 32'h30509073; // CSRRW x0, mtvec, x1

        // 1. 测试 CSRRS 的 x0 免写机制
        // 先给 mie 写入 0xF
        imem[2] = 32'h00F00113; // ADDI x2, x0, 15
        imem[3] = 32'h30411073; // CSRRW x0, mie, x2  -> mie = 15
        // 使用 x0 作为 rs1。按照标准，这不应触发写动作。
        imem[4] = 32'h30402173; // CSRRS x2, mie, x0  -> 预期：x2=15, mie 保持 15

        // 2. 测试非法 CSR 地址访问 (预期：触发异常，跳往 mtvec=0x40)
        imem[5] = 32'hFFF09073; // CSRRW x0, 0xFFF, x1 (访问不存在的地址)
        imem[6] = 32'h00100093; // ADDI x1, x0, 1 (这行不应被执行，因为上一行该跳走了)

        // --- 异常处理程序 (位于 0x40) ---
        // 地址 0x40 (即 imem[16])
        // 1. CSRRS x30, mepc, x0
        imem[16] = 32'h34102F73; 
        // 2. ADDI x30, x30, 4
        imem[17] = 32'h004F0F13; 
        // 3. CSRRW x0, mepc, x30
        imem[18] = 32'h341F1073; 
        // 4. MRET (此时 mepc 已经被软件改为了 0x18)
        imem[19] = 32'h30200073;
        // ------------------------

        #15;
        rst = 0;
        $display("\n================ 测试开始 ================");

        // --- 开始测试 ---
        rst = 0;

        // 1. 验证免写机制 (rs1=x0)
        repeat(10) @(posedge clk);
        if (uut.u_csr_regfile.mie === 32'hF) 
            $display("[成功] 免写测试 : CSRRS x0 未修改寄存器值");
        else
            $display("[失败] 免写测试 : mie 被错误修改为 0x%h", uut.u_csr_regfile.mie);

        // 2. 验证异常跳转与 mcause
        // 等待非法指令触发并跳转
        repeat(10) @(posedge clk);
        if (uut.inst_addr === 32'h40) begin
            $display("[成功] 异常跳转 : 成功跳往 mtvec (0x40)");
            // 验证 mcause，按照你的代码，异常时最高位为 0
            if (uut.u_csr_regfile.mcause[31] === 1'b0)
                $display("[成功] 异常原因 : mcause 记录为同步异常");
        end else begin
            $display("[失败] 异常跳转 : PC 未能跳往 0x40，当前 PC: 0x%h", uut.inst_addr);
        end

        // 3. 验证 MRET 返回
        // 动态等待 PC 到达 0x18，最多等 30 拍防止死循环挂死仿真
        while (uut.inst_addr !== 32'h18 && timeout_cnt < 30) begin
            @(posedge clk);
            timeout_cnt++;
        end

        if (uut.inst_addr === 32'h18) begin
            $display("[成功] MRET 返回 : 成功跳过非法指令，PC 恢复到 0x18 执行！");
        end else begin
            $display("[失败] MRET 返回 : PC 未能回到 0x18，当前 PC: 0x%0h", uut.inst_addr);
        end

        $display("================ 测试结束 ================\n");
        $finish;
    end

    initial begin
        $dumpfile("pipeline_wave.vcd");
        $dumpvars(0, tb_pipeline);
    end

endmodule