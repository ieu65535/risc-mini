`timescale 1ns/1ps

module tb_interrupt();

    // ==========================================
    // 1. 信号定义
    // ==========================================
    logic        clk;
    logic        rst;
    logic        timer_int; // 外部定时器中断
    
    logic [31:0] inst_addr;
    logic [31:0] inst = 32'h00000013;
    integer      error_count = 0;
    integer      cycle_count = 0;
    
    logic [31:0] inst_mem [0:255];

    // ==========================================
    // 2. 实例化流水线 (请确保 pipeline 拥有 timer_int 端口)
    // ==========================================
    pipeline dut (
        .clk        (clk),
        .rst        (rst),
        .timer_int  (timer_int),  // <--- 接入外部中断信号
        .inst       (inst),
        .inst_ready (1'b1),
        .mem_dout   (32'b0), // 不涉及内存读写，直接给默认值
        .mem_ready  (1'b1),
        .mem_en     (),
        .inst_addr  (inst_addr),
        .mem_din    (),
        .mem_addr   (),
        .mem_we     ()
    );

    // ==========================================
    // 3. 同步取指：与 RTL 中 flash.sv 的一拍返回模型一致
    // ==========================================
    always_comb inst = inst_mem[inst_addr[9:2]];

    // ==========================================
    // 4. 时钟生成
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // 周期级看门狗：正常测试约 84 个周期，超过 200 周期即视为失去进展。
    always @(posedge clk) begin
        if (rst) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (cycle_count >= 200)
                $fatal(1, "[TB TIMEOUT] tb_interrupt exceeded 200 cycles");
        end
    end

    // ==========================================
    // 5. 组装测试用的微型操作系统汇编代码
    // ==========================================
    initial begin
`ifdef DUMP_WAVES
        $dumpfile("tb_trap.vcd");
        $dumpvars(0, tb_interrupt.dut);
`endif

        for(int i=0; i<256; i++) inst_mem[i] = 32'h00000013; // 默认 NOP
        
        // --- 主程序区 (0x00 ~ 0x18) ---
        // 初始化中断环境
        inst_mem[0] = 32'h04000093; // 00: addi x1, x0, 0x40 (中断入口地址设为 0x40)
        inst_mem[1] = 32'h30509073; // 04: csrw mtvec, x1    (写入 mtvec)
        inst_mem[2] = 32'h00800113; // 08: addi x2, x0, 8    (掩码: 第3位 MIE)
        inst_mem[3] = 32'h30012073; // 0C: csrs mstatus, x2  (开启全局中断 MIE=1)
        
        // 触发同步异常 (ECALL)
        inst_mem[4] = 32'h00000073; // 10: ecall             <-- 产生 Trap，跳去 0x40！
        
        // 如果 Flush 失败，这条会被误执行；如果成功，只会从中断返回后才执行
        inst_mem[5] = 32'h06300193; // 14: addi x3, x0, 99   (目标验证点：x3 是否等于 99)
        
        // 模拟操作系统 Idle 任务 (死循环)
        inst_mem[6] = 32'h0000006f; // 18: jal x0, 0         <-- 死循环等待外部 timer_int

        // --- 中断服务函数 Trap Handler (基址 0x40，即 inst_mem[16]) ---
        inst_mem[16] = 32'h34202273; // 40: csrr x4, mcause  (读取异常原因)
        inst_mem[17] = 32'h341022f3; // 44: csrr x5, mepc    (读取异常返回地址)
        inst_mem[18] = 32'h00b00313; // 48: addi x6, x0, 11  (ECALL 的原因码是 11)
        inst_mem[19] = 32'h00621463; // 4C: bne  x4, x6, 8   (如果是外部中断，跳过 mepc+4)
        
        // 仅 ECALL 会执行这一步 (mepc = mepc + 4)
        inst_mem[20] = 32'h00428293; // 50: addi x5, x5, 4   (修正返回地址)
        
        // 恢复返回地址并退出中断
        inst_mem[21] = 32'h34129073; // 54: csrw mepc, x5    (写回修正后的 mepc)
        inst_mem[22] = 32'h30200073; // 58: mret             (中断返回！)
    end

    // ==========================================
    // 6. 测试控制与检查流程
    // ==========================================
    initial begin
        rst = 1;
        timer_int = 0;
        #20;
        rst = 0;
        $display("[TB PHASE] ECALL/MRET test started");

        // 【阶段 1】：让 CPU 跑 50 个周期，足够它执行完 ECALL 并 MRET 返回
        repeat(50) @(posedge clk);

        // 此时 CPU 应该在 0x18 的死循环里。我们来检查 ECALL 是否处理正确。
        $display("\n========================================");
        $display("       异常与中断机制自动化验证报告       ");
        $display("========================================");

        if (dut.u_reg_file.regs[3] === 32'd99) 
            $display("[PASS] 流水线 Flush 与 ECALL 返回正常 (x3=99)");
        else begin
            $display("[FAIL] ECALL 处理错误！期望 x3=99, 实际=%0d", dut.u_reg_file.regs[3]);
            error_count = error_count + 1;
        end

        if (dut.u_reg_file.regs[4] === 32'd11)
            $display("[PASS] mcause 正确捕获 ECALL 异常码 11");
        else begin
            $display("[FAIL] mcause 未正确捕获, 实际=%0d", dut.u_reg_file.regs[4]);
            error_count = error_count + 1;
        end

        // 【阶段 2】：模拟外部定时器中断 (拉高 timer_int)
        // 此时 CPU 在 0x18 死循环，拉高信号会将其强制拖入中断
        $display("[TB PHASE] Timer interrupt test started");
        @(posedge clk);
        timer_int = 1; 
        
        // 保持中断信号几个周期，然后撤销 (模拟外部设备脉冲)
        repeat(3) @(posedge clk);
        timer_int = 0;

        // 让 CPU 跑 30 个周期，足够它进入中断处理并再次 MRET 返回
        repeat(30) @(posedge clk);

        // 检查 Timer 中断是否被捕获
        if (dut.u_reg_file.regs[4] === 32'h80000007)
            $display("[PASS] mcause 正确捕获外部 Timer 中断 (0x80000007)");
        else begin
            $display("[FAIL] Timer 中断捕获失败, x4=%h", dut.u_reg_file.regs[4]);
            error_count = error_count + 1;
        end

        // 检查 Timer 中断保存的 mepc 是否是死循环的地址 (0x18)
        if (dut.u_reg_file.regs[5] === 32'h00000018)
            $display("[PASS] mepc 正确保存被打断的 PC (0x18)");
        else begin
            $display("[FAIL] mepc 现场保存错误, x5=%h", dut.u_reg_file.regs[5]);
            error_count = error_count + 1;
        end

        $display("========================================\n");
        if (error_count == 0) begin
            $display("[TB PASS] tb_interrupt");
            $finish;
        end else begin
            $fatal(1, "[TB FAIL] tb_interrupt: %0d checks failed", error_count);
        end
    end

endmodule
