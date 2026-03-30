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

    // ==========================================
    // 测试主流程
    // ==========================================
    initial begin
        rst = 1;
        rxd = 1; // 外部拉高，防止误触发

        // --- 写入测试指令序列 ---
        // 1. 基础测试：ADDI x1, x0, 16 
        imem[0] = 32'h01000093; 
        
        // 2. 内存测试：SW x1, 4(x0) 
        imem[1] = 32'h00102223; 

        // 3. 内存测试：LW x2, 4(x0) 
        imem[2] = 32'h00402103;

        // 4. Zicsr测试：CSRRW x0, mtvec, x1 -> mtvec = 16 
        imem[3] = 32'h30509073;

        // 5. 开启全局中断：ADDI x3, x0, 8 (mstatus.MIE 位)
        imem[4] = 32'h00800193;
        //    CSRRW x0, mstatus, x3 
        imem[5] = 32'h30019073;

        // 6. 开启外部中断：ADDI x4, x0, 2048 (mie.MEIE 位，第11位)
        imem[6] = 32'h80000213;
        //    CSRRW x0, mie, x4 
        imem[7] = 32'h30421073;
        // ------------------------

        #15;
        rst = 0;
        $display("\n================ 测试开始 ================");

        // 依次检查每条指令的结果 (每次检查 task 内部等了5拍让流水线走完)
        check_reg(5'd1, 32'd16, "测试 ADDI (x1 = 16)");
        check_mem(32'h4, 32'd16, "测试 SW (mem[4] = 16)");
        check_reg(5'd2, 32'd16, "测试 LW (x2 = mem[4])");
        check_csr_mtvec(32'd16, "测试 Zicsr (mtvec = 16)");

        // 等待 MSTATUS 和 MIE 写完
        repeat(15) @(posedge clk); 
        $display("-> 已开启全局中断使能(MIE) 和 外部中断使能(MEIE)");

        // 触发外部中断
        $display("\n---> 触发外部中断 (拉低 rxd 信号)...");
        rxd = 0; 
        repeat(3) @(posedge clk); // 等待边沿检测同步，足够触发 mip[11] <= 1
        rxd = 1; 
        
        // 等待中断冒泡、清空流水线并跳入处理程序
        repeat(8) @(posedge clk);
        
        // 判断是否成功响应：如果有响应，mepc 会保存发生中断时的 PC (肯定不为0)
        if (uut.u_csr_regfile.mepc !== 32'h0) begin
            $display("[成功] 测试 中断响应 : 触发成功！mepc 已保存断点 (0x%h)", uut.u_csr_regfile.mepc);
            $display("       当前 mcause = 0x%h", uut.u_csr_regfile.mcause);
        end else begin
            $display("[失败] 测试 中断响应 : mepc 仍然为 0，未响应中断，请检查 interrupt_taken 逻辑。");
        end

        $display("================ 测试结束 ================\n");
        $finish;
    end

    initial begin
        $dumpfile("pipeline_wave.vcd");
        $dumpvars(0, tb_pipeline);
    end

endmodule