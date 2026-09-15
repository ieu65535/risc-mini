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
    integer      timer_trap_count = 0;
    integer      timer_trap_count_before = 0;
    integer      handler_pc_count = 0;
    integer      handler_pc_count_before = 0;
    integer      trap_stall_overlap_count = 0;
    integer      trap_stall_overlap_count_before = 0;
    
    logic [31:0] inst_mem [0:255];

    // ==========================================
    // 2. 实例化流水线 (请确保 pipeline 拥有 timer_int 端口)
    // ==========================================
    pipeline dut (
        .clk        (clk),
        .rst        (rst),
        .timer_int  (timer_int),  // <--- 接入外部中断信号
        .inst       (inst),
        .mem_dout   (32'b0), // 不涉及内存读写，直接给默认值
        .inst_addr  (inst_addr),
        .mem_din    (),
        .mem_addr   (),
        .mem_we     ()
    );

    // ==========================================
    // 3. 同步取指：与 RTL 中 flash.sv 的一拍返回模型一致
    // ==========================================
    always_ff @(posedge clk) begin
        inst <= inst_mem[inst_addr[9:2]];
    end

    // ==========================================
    // 4. 时钟生成
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // 周期级看门狗：正常测试低于 150 个周期，超过 200 周期即视为失去进展。
    always @(posedge clk) begin
        if (rst) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (cycle_count >= 200)
                $fatal(1, "[TB TIMEOUT] tb_interrupt exceeded 200 cycles");
        end
    end

    // 记录 CPU 实际接收了多少次机器定时器中断。
    // 只观察 DUT 的中断接收结果，不直接修改 CSR 内部状态。
    always @(posedge clk) begin
        if (rst) begin
            timer_trap_count <= 0;
            handler_pc_count <= 0;
            trap_stall_overlap_count <= 0;
        end else begin
            if (dut.trap_valid && (dut.trap_cause === 32'h80000007))
                timer_trap_count <= timer_trap_count + 1;
            if (dut.pc === 32'h00000040)
                handler_pc_count <= handler_pc_count + 1;
            if (dut.trap_valid && dut.stall)
                trap_stall_overlap_count <= trap_stall_overlap_count + 1;
        end
    end

    task automatic pulse_timer;
        begin
            // 在下降沿改变异步测试输入，使其跨越一个完整的上升沿。
            @(negedge clk);
            timer_int = 1'b1;
            @(negedge clk);
            timer_int = 1'b0;
        end
    endtask

    // ==========================================
    // 5. 组装测试用的微型操作系统汇编代码
    // ==========================================
    initial begin
`ifdef DUMP_WAVES
        $dumpfile("tb_trap.vcd");
        $dumpvars(0, tb_interrupt.dut);
`endif

        for(int i=0; i<256; i++) inst_mem[i] = 32'h00000013; // 默认 NOP
        
        // --- 主程序区 ---
        // 初始化 mtvec，然后先停在 0x08。此时 MIE=0、MTIE=0。
        inst_mem[0] = 32'h04000093; // 00: addi x1, x0, 0x40 (中断入口地址设为 0x40)
        inst_mem[1] = 32'h30509073; // 04: csrw mtvec, x1    (写入 mtvec)
        inst_mem[2] = 32'h0000006f; // 08: jal x0, 0         (测试阶段动态替换后继续)

        // 开启全局中断并验证 ECALL/MRET；此时仍保持 mie.MTIE=0。
        inst_mem[3] = 32'h30012073; // 0C: csrs mstatus, x2  (开启全局中断 MIE=1)
        inst_mem[4] = 32'h00000073; // 10: ecall             <-- 产生 Trap，跳去 0x40！
        inst_mem[5] = 32'h06300193; // 14: addi x3, x0, 99   (目标验证点：x3 是否等于 99)
        inst_mem[6] = 32'h0000006f; // 18: jal x0, 0         (MTIE=0 测试等待点)

        // 测试阶段会把 0x18 动态替换为 addi x2, x0, 0x80，随后执行：
        inst_mem[7] = 32'h30412073; // 1C: csrs mie, x2      (开启 MTIE，mie[7]=1)
        inst_mem[8] = 32'h00100513; // 20: addi x10, x0, 1  (到达最终等待点的标记)
        inst_mem[9] = 32'h0000006f; // 24: jal x0, 0         (MIE=1、MTIE=1 测试等待点)

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
        $display("\n========================================");
        $display("       异常与中断机制自动化验证报告       ");
        $display("========================================");

        // 【阶段 1】：mstatus.MIE=0 时，即使 timer_int 到来也不能进入中断。
        $display("[TB PHASE] Timer masked by mstatus.MIE=0");
        wait (dut.u_csr_file.mtvec === 32'h00000040);
        wait (inst_addr === 32'h00000008);
        repeat(3) @(posedge clk);
        timer_trap_count_before = timer_trap_count;
        pulse_timer();
        repeat(3) @(posedge clk);

        if (timer_trap_count == timer_trap_count_before)
            $display("[PASS] mstatus.MIE=0 时 Timer 中断被正确屏蔽");
        else begin
            $display("[FAIL] mstatus.MIE=0 时错误接收了 Timer 中断");
            error_count = error_count + 1;
        end

        // 把 0x08 的等待指令替换为设置 MIE 掩码，让程序继续运行。
        @(negedge clk);
        inst_mem[2] = 32'h00800113; // 08: addi x2, x0, 8

        // 【阶段 2】：验证同步异常 ECALL 及 MRET 返回。
        $display("[TB PHASE] ECALL/MRET test started");
        wait (dut.u_reg_file.regs[3] === 32'd99);

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

        // 【阶段 3】：MIE=1 但 mie.MTIE=0 时，Timer 仍必须被屏蔽。
        $display("[TB PHASE] Timer masked by mie.MTIE=0");
        wait (dut.u_csr_file.mstatus[3] === 1'b1);
        wait (inst_addr === 32'h00000018);
        repeat(3) @(posedge clk);
        timer_trap_count_before = timer_trap_count;
        pulse_timer();
        repeat(3) @(posedge clk);

        if (timer_trap_count == timer_trap_count_before)
            $display("[PASS] mie.MTIE=0 时 Timer 中断被正确屏蔽");
        else begin
            $display("[FAIL] mie.MTIE=0 时错误接收了 Timer 中断");
            error_count = error_count + 1;
        end

        // 把 0x18 的等待指令替换为 MTIE 掩码装载，让程序继续运行。
        @(negedge clk);
        inst_mem[6] = 32'h08000113; // 18: addi x2, x0, 0x80

        // 【阶段 4】：MIE=1 且 MTIE=1 时，Timer 必须被接收。
        $display("[TB PHASE] Timer enabled by MIE=1 and MTIE=1");
        wait (dut.u_csr_file.mie[7] === 1'b1);
        wait (dut.u_reg_file.regs[10] === 32'd1);
        wait (inst_addr === 32'h00000024);
        repeat(3) @(posedge clk);
        timer_trap_count_before = timer_trap_count;
        pulse_timer();
        repeat(20) @(posedge clk);

        if (timer_trap_count > timer_trap_count_before)
            $display("[PASS] MIE=1 且 MTIE=1 时正确接收 Timer 中断");
        else begin
            $display("[FAIL] MIE=1 且 MTIE=1 时未接收 Timer 中断");
            error_count = error_count + 1;
        end

        // 检查 Timer 中断是否被捕获
        if (dut.u_reg_file.regs[4] === 32'h80000007)
            $display("[PASS] mcause 正确捕获外部 Timer 中断 (0x80000007)");
        else begin
            $display("[FAIL] Timer 中断捕获失败, x4=%h", dut.u_reg_file.regs[4]);
            error_count = error_count + 1;
        end

        // CPU 已稳定停在 0x24，自此处接受中断时 mepc 应保存 0x24。
        if (dut.u_reg_file.regs[5] === 32'h00000024)
            $display("[PASS] mepc 正确保存被打断的 PC (0x24)");
        else begin
            $display("[FAIL] mepc 现场保存错误, x5=%h", dut.u_reg_file.regs[5]);
            error_count = error_count + 1;
        end

        // 【阶段 5】：构造 LW -> ADD load-use 冒险，并在 stall=1 的同一周期触发 Timer。
        // 如果 PC 更新把 stall 放在 Trap 重定向之前，CSR 虽会记录 Trap，PC 却不会进入 0x40。
        $display("[TB PHASE] Timer redirect overlaps load-use stall");
        wait (dut.u_csr_file.mstatus[3] === 1'b1);
        wait (inst_addr === 32'h00000024);
        @(negedge clk);
        inst_mem[9]  = 32'h00002583; // 24: lw   x11, 0(x0)
        inst_mem[10] = 32'h00b58633; // 28: add  x12, x11, x11 (触发 load-use stall)
        inst_mem[11] = 32'h00100693; // 2C: addi x13, x0, 1     (继续执行标记)
        inst_mem[12] = 32'h0000006f; // 30: jal  x0, 0

        wait (dut.stall === 1'b1);
        handler_pc_count_before = handler_pc_count;
        trap_stall_overlap_count_before = trap_stall_overlap_count;
        pulse_timer();
        repeat(25) @(posedge clk);

        if (trap_stall_overlap_count > trap_stall_overlap_count_before)
            $display("[PASS] 测试已命中 Timer Trap 与 load-use stall 同周期条件");
        else begin
            $display("[FAIL] 测试未能构造 Trap/stall 同周期条件");
            error_count = error_count + 1;
        end

        if (handler_pc_count > handler_pc_count_before)
            $display("[PASS] Trap 重定向未被 stall 阻塞，CPU 进入 0x40");
        else begin
            $display("[FAIL] stall 覆盖了 Trap 重定向，CPU 未进入 0x40");
            error_count = error_count + 1;
        end

        if (dut.u_reg_file.regs[13] === 32'd1)
            $display("[PASS] MRET 后流水线继续执行 (x13=1)");
        else begin
            $display("[FAIL] MRET 后未继续执行, x13=%0d", dut.u_reg_file.regs[13]);
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
