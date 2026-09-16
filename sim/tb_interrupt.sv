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
    logic [31:0] mem_din;
    logic [31:0] mem_addr;
    logic [ 3:0] mem_we;
    integer      error_count = 0;
    integer      cycle_count = 0;
    integer      timer_trap_count = 0;
    integer      timer_trap_count_before = 0;
    integer      ecall_trap_count = 0;
    integer      ecall_trap_count_before = 0;
    integer      handler_pc_count = 0;
    integer      handler_pc_count_before = 0;
    integer      trap_stall_overlap_count = 0;
    integer      trap_stall_overlap_count_before = 0;
    integer      store_commit_count = 0;
    integer      store_commit_count_before = 0;
    integer      store_addr0_count = 0;
    integer      store_addr4_count = 0;
    integer      store_addr0_count_before = 0;
    integer      store_addr4_count_before = 0;
    integer      younger_store_before_handler_count = 0;
    integer      younger_store_before_handler_count_before = 0;
    integer      illegal_trap_count = 0;
    integer      illegal_trap_count_before = 0;
    integer      inst_misaligned_count = 0;
    integer      inst_misaligned_count_before = 0;
    integer      load_misaligned_count = 0;
    integer      load_misaligned_count_before = 0;
    integer      store_misaligned_count = 0;
    integer      store_misaligned_count_before = 0;
    logic        boundary_phase_active = 1'b0;
    
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
        .mem_din    (mem_din),
        .mem_addr   (mem_addr),
        .mem_we     (mem_we)
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

    // 周期级看门狗：正常测试低于 400 个周期，超过 450 周期即视为失去进展。
    always @(posedge clk) begin
        if (rst) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (cycle_count >= 450)
                $fatal(1, "[TB TIMEOUT] tb_interrupt exceeded 450 cycles");
        end
    end

    // 记录 CPU 实际接收了多少次机器定时器中断。
    // 只观察 DUT 的中断接收结果，不直接修改 CSR 内部状态。
    always @(posedge clk) begin
        if (rst) begin
            timer_trap_count <= 0;
            ecall_trap_count <= 0;
            handler_pc_count <= 0;
            trap_stall_overlap_count <= 0;
            store_commit_count <= 0;
            store_addr0_count <= 0;
            store_addr4_count <= 0;
            younger_store_before_handler_count <= 0;
            illegal_trap_count <= 0;
            inst_misaligned_count <= 0;
            load_misaligned_count <= 0;
            store_misaligned_count <= 0;
        end else begin
            if (dut.trap_valid && (dut.trap_cause === 32'h80000007))
                timer_trap_count <= timer_trap_count + 1;
            if (dut.trap_valid && (dut.trap_cause === 32'd11))
                ecall_trap_count <= ecall_trap_count + 1;
            if (dut.pc === 32'h00000040)
                handler_pc_count <= handler_pc_count + 1;
            if (dut.trap_valid && dut.stall)
                trap_stall_overlap_count <= trap_stall_overlap_count + 1;
            if (dut.trap_valid && (dut.trap_cause === 32'd2))
                illegal_trap_count <= illegal_trap_count + 1;
            if (dut.trap_valid && (dut.trap_cause === 32'd0))
                inst_misaligned_count <= inst_misaligned_count + 1;
            if (dut.trap_valid && (dut.trap_cause === 32'd4))
                load_misaligned_count <= load_misaligned_count + 1;
            if (dut.trap_valid && (dut.trap_cause === 32'd6))
                store_misaligned_count <= store_misaligned_count + 1;
            if ((|mem_we) === 1'b1) begin
                store_commit_count <= store_commit_count + 1;
                if (mem_addr === 32'h00000000)
                    store_addr0_count <= store_addr0_count + 1;
                if (mem_addr === 32'h00000004) begin
                    store_addr4_count <= store_addr4_count + 1;
                    if (boundary_phase_active &&
                        (handler_pc_count == handler_pc_count_before))
                        younger_store_before_handler_count <=
                            younger_store_before_handler_count + 1;
                end
            end
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
        inst_mem[16] = 32'h34402e73; // 40: csrr x28, mip    (软件读取 MTIP pending)
        inst_mem[17] = 32'h34202273; // 44: csrr x4, mcause  (读取异常原因)
        inst_mem[18] = 32'h341022f3; // 48: csrr x5, mepc    (读取异常返回地址)
        inst_mem[19] = 32'h00024463; // 4C: blt  x4, x0, 8   (中断 cause 最高位为1，跳过 mepc+4)

        // 同步异常（ECALL/非法指令）跳过故障指令；异步中断返回原 PC。
        inst_mem[20] = 32'h00428293; // 50: addi x5, x5, 4
        inst_mem[21] = 32'h34129073; // 54: csrw mepc, x5
        inst_mem[22] = 32'h30200073; // 58: mret
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
        if (dut.csr_mip_mtip === 1'b1)
            $display("[PASS] MIE=0 时 Timer 请求已锁存到 mip.MTIP");
        else begin
            $display("[FAIL] MIE=0 时 Timer 请求没有进入 pending");
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
        if (dut.u_reg_file.regs[28] === 32'h00000080)
            $display("[PASS] 软件通过 CSR 读取到 mip.MTIP=1");
        else begin
            $display("[FAIL] CSR 读取 mip 错误, x28=%h",
                     dut.u_reg_file.regs[28]);
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
        if (dut.csr_mip_mtip === 1'b1)
            $display("[PASS] MTIE=0 时 mip.MTIP 保持挂起");
        else begin
            $display("[FAIL] MTIE=0 时 pending 被错误清除");
            error_count = error_count + 1;
        end

        // 把 0x18 的等待指令替换为 MTIE 掩码装载，让程序继续运行。
        @(negedge clk);
        inst_mem[6] = 32'h08000113; // 18: addi x2, x0, 0x80

        // 【阶段 4】：先前在屏蔽期间到达的请求必须保持；开放 MTIE 后自动接收，
        // 不再发送新的 timer_int 脉冲。
        $display("[TB PHASE] Pending Timer released by MIE=1 and MTIE=1");
        timer_trap_count_before = timer_trap_count;
        wait (dut.u_csr_file.mie[7] === 1'b1);
        wait (dut.u_reg_file.regs[10] === 32'd1);
        wait (inst_addr === 32'h00000024);
        repeat(20) @(posedge clk);

        if (timer_trap_count > timer_trap_count_before)
            $display("[PASS] 屏蔽期间的 Timer 请求在开放后被正确接收");
        else begin
            $display("[FAIL] 屏蔽期间的 Timer 请求丢失");
            error_count = error_count + 1;
        end
        if (dut.csr_mip_mtip === 1'b0)
            $display("[PASS] Timer 被接收后 mip.MTIP 正确清除");
        else begin
            $display("[FAIL] Timer 被接收后 mip.MTIP 仍为 1");
            error_count = error_count + 1;
        end

        // 检查 Timer 中断是否被捕获
        if (dut.u_reg_file.regs[4] === 32'h80000007)
            $display("[PASS] mcause 正确捕获外部 Timer 中断 (0x80000007)");
        else begin
            $display("[FAIL] Timer 中断捕获失败, x4=%h", dut.u_reg_file.regs[4]);
            error_count = error_count + 1;
        end

        // MTIE 在 0x1C 提交后，请求在下一条 0x20 的精确边界被接收。
        if (dut.u_reg_file.regs[5] === 32'h00000020)
            $display("[PASS] mepc 正确保存首次可接收边界 PC (0x20)");
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

        // 【阶段 6】：让 Timer Trap 与 Store 在 EX 阶段重合。
        // 精确中断要求：若 mepc 保存 Store 自身地址，则 Trap 当拍必须取消该 Store，
        // 等 MRET 后再由重执行只提交一次，不能在中断前后各写一次。
        $display("[TB PHASE] Timer trap kills current Store before commit");
        wait (dut.u_csr_file.mstatus[3] === 1'b1);
        wait (inst_addr === 32'h00000030);
        @(negedge clk);
        inst_mem[12] = 32'h05500713; // 30: addi x14, x0, 0x55
        inst_mem[13] = 32'h00e02023; // 34: sw   x14, 0(x0)
        inst_mem[14] = 32'h00100793; // 38: addi x15, x0, 1
        inst_mem[15] = 32'h0000006f; // 3C: jal  x0, 0

        wait ((dut.pc_ex === 32'h00000034) && (dut.mem_mask_ex != 4'b0));
        store_commit_count_before = store_commit_count;
        timer_trap_count_before = timer_trap_count;
        pulse_timer();
        repeat(30) @(posedge clk);

        if (timer_trap_count > timer_trap_count_before)
            $display("[PASS] Timer Trap 与 Store EX 周期成功重合");
        else begin
            $display("[FAIL] 未能构造 Timer Trap/Store 重合条件");
            error_count = error_count + 1;
        end

        if ((store_commit_count - store_commit_count_before) == 1)
            $display("[PASS] 被中断 Store 只在 MRET 后提交一次");
        else begin
            $display("[FAIL] 被中断 Store 提交次数错误, 实际=%0d, 期望=1",
                     store_commit_count - store_commit_count_before);
            error_count = error_count + 1;
        end

        if (dut.u_reg_file.regs[15] === 32'd1)
            $display("[PASS] Store 重执行后程序继续前进 (x15=1)");
        else begin
            $display("[FAIL] Store 重执行后程序未继续, x15=%0d", dut.u_reg_file.regs[15]);
            error_count = error_count + 1;
        end

        // 【阶段 7】：验证精确 Trap 的边界。
        // 0x80 的老指令必须完成；0x84 的当前 Store 必须 kill 后重执行一次；
        // 0x88 的年轻 Store 在进入 Handler 前不得提交。
        $display("[TB PHASE] Precise trap boundary: older/current/younger");
        wait (dut.u_csr_file.mstatus[3] === 1'b1);
        wait (inst_addr === 32'h0000003c);
        repeat(3) @(posedge clk);

        boundary_phase_active = 1'b1;
        handler_pc_count_before = handler_pc_count;
        store_addr0_count_before = store_addr0_count;
        store_addr4_count_before = store_addr4_count;
        younger_store_before_handler_count_before =
            younger_store_before_handler_count;

        @(negedge clk);
        inst_mem[15] = 32'h0440006f; // 3C: jal  x0, 0x80
        inst_mem[32] = 32'h03300a13; // 80: addi x20, x0, 0x33 (老指令)
        inst_mem[33] = 32'h00e02023; // 84: sw   x14, 0(x0)   (当前指令)
        inst_mem[34] = 32'h00e02223; // 88: sw   x14, 4(x0)   (年轻指令)
        inst_mem[35] = 32'h00100a93; // 8C: addi x21, x0, 1
        inst_mem[36] = 32'h0000006f; // 90: jal  x0, 0

        wait ((dut.pc_ex === 32'h00000084) && (dut.mem_mask_ex != 4'b0));
        pulse_timer();
        repeat(40) @(posedge clk);
        boundary_phase_active = 1'b0;

        if (dut.u_reg_file.regs[20] === 32'h00000033)
            $display("[PASS] Trap 之前的老指令正常提交 (x20=0x33)");
        else begin
            $display("[FAIL] Trap 之前的老指令未提交, x20=%h",
                     dut.u_reg_file.regs[20]);
            error_count = error_count + 1;
        end

        if ((store_addr0_count - store_addr0_count_before) == 1)
            $display("[PASS] 当前 Store 被 kill，并在 MRET 后只提交一次");
        else begin
            $display("[FAIL] 当前 Store 提交次数=%0d, 期望=1",
                     store_addr0_count - store_addr0_count_before);
            error_count = error_count + 1;
        end

        if ((younger_store_before_handler_count -
             younger_store_before_handler_count_before) == 0)
            $display("[PASS] 年轻 Store 在进入 Handler 前没有副作用");
        else begin
            $display("[FAIL] 年轻 Store 在 Handler 前错误提交");
            error_count = error_count + 1;
        end

        if ((store_addr4_count - store_addr4_count_before) == 1)
            $display("[PASS] 年轻 Store 在 MRET 后按程序顺序提交一次");
        else begin
            $display("[FAIL] 年轻 Store 最终提交次数=%0d, 期望=1",
                     store_addr4_count - store_addr4_count_before);
            error_count = error_count + 1;
        end

        if (dut.u_reg_file.regs[21] === 32'd1)
            $display("[PASS] 精确 Trap 返回后程序继续前进 (x21=1)");
        else begin
            $display("[FAIL] 精确 Trap 返回后程序未继续, x21=%0d",
                     dut.u_reg_file.regs[21]);
            error_count = error_count + 1;
        end

        // 【阶段 8】：非法指令必须产生同步异常 cause=2，并由 Handler 跳过。
        $display("[TB PHASE] Illegal instruction trap");
        wait (inst_addr === 32'h00000090);
        repeat(3) @(posedge clk);
        illegal_trap_count_before = illegal_trap_count;

        @(negedge clk);
        inst_mem[36] = 32'h0300006f; // 90: jal  x0, 0xC0
        inst_mem[48] = 32'hffffffff; // C0: 非法指令
        inst_mem[49] = 32'h00100b13; // C4: addi x22, x0, 1
        inst_mem[50] = 32'h0000006f; // C8: jal  x0, 0

        repeat(35) @(posedge clk);

        if ((illegal_trap_count - illegal_trap_count_before) == 1)
            $display("[PASS] 非法指令只触发一次 Trap");
        else begin
            $display("[FAIL] 非法指令 Trap 次数=%0d, 期望=1",
                     illegal_trap_count - illegal_trap_count_before);
            error_count = error_count + 1;
        end

        if (dut.u_reg_file.regs[4] === 32'd2)
            $display("[PASS] mcause 正确记录非法指令异常码 2");
        else begin
            $display("[FAIL] 非法指令 mcause=%h, 期望=00000002",
                     dut.u_reg_file.regs[4]);
            error_count = error_count + 1;
        end

        if (dut.u_reg_file.regs[5] === 32'h000000c4)
            $display("[PASS] Handler 将 mepc 从 0xC0 修正到 0xC4");
        else begin
            $display("[FAIL] 非法指令返回地址 x5=%h, 期望=000000c4",
                     dut.u_reg_file.regs[5]);
            error_count = error_count + 1;
        end

        if (dut.u_reg_file.regs[22] === 32'd1)
            $display("[PASS] 跳过非法指令后程序继续前进 (x22=1)");
        else begin
            $display("[FAIL] 跳过非法指令后程序未继续, x22=%0d",
                     dut.u_reg_file.regs[22]);
            error_count = error_count + 1;
        end

        // 【阶段 9】：LW 地址未按 4 字节对齐时产生 cause=4，且不得写回 rd。
        $display("[TB PHASE] Load address misaligned trap");
        wait (inst_addr === 32'h000000c8);
        load_misaligned_count_before = load_misaligned_count;
        @(negedge clk);
        inst_mem[50] = 32'h0080006f; // C8: jal  x0, 0xD0
        inst_mem[52] = 32'h05a00b93; // D0: addi x23, x0, 0x5A (哨兵值)
        inst_mem[53] = 32'h00102b83; // D4: lw   x23, 1(x0)   (未对齐)
        inst_mem[54] = 32'h00100c13; // D8: addi x24, x0, 1
        inst_mem[55] = 32'h0000006f; // DC: jal  x0, 0
        repeat(35) @(posedge clk);

        if ((load_misaligned_count - load_misaligned_count_before) == 1)
            $display("[PASS] 未对齐 LW 只触发一次 cause=4 Trap");
        else begin
            $display("[FAIL] 未对齐 LW Trap 次数=%0d, 期望=1",
                     load_misaligned_count - load_misaligned_count_before);
            error_count = error_count + 1;
        end
        if (dut.u_reg_file.regs[23] === 32'h0000005a)
            $display("[PASS] 未对齐 LW 未覆盖目标寄存器");
        else begin
            $display("[FAIL] 未对齐 LW 产生了写回, x23=%h",
                     dut.u_reg_file.regs[23]);
            error_count = error_count + 1;
        end
        if ((dut.u_reg_file.regs[4] === 32'd4) &&
            (dut.u_reg_file.regs[5] === 32'h000000d8) &&
            (dut.u_reg_file.regs[24] === 32'd1))
            $display("[PASS] LW 异常 cause/mepc/返回执行正确");
        else begin
            $display("[FAIL] LW 异常现场错误: cause=%h mepc_next=%h x24=%h",
                     dut.u_reg_file.regs[4], dut.u_reg_file.regs[5],
                     dut.u_reg_file.regs[24]);
            error_count = error_count + 1;
        end

        // 【阶段 10】：SW 地址未按 4 字节对齐时产生 cause=6，且 mem_we 必须保持 0。
        $display("[TB PHASE] Store address misaligned trap");
        wait (inst_addr === 32'h000000dc);
        store_misaligned_count_before = store_misaligned_count;
        store_commit_count_before = store_commit_count;
        @(negedge clk);
        inst_mem[55] = 32'h0040006f; // DC: jal  x0, 0xE0
        inst_mem[56] = 32'h00e02123; // E0: sw   x14, 2(x0)   (未对齐)
        inst_mem[57] = 32'h00100c93; // E4: addi x25, x0, 1
        inst_mem[58] = 32'h0000006f; // E8: jal  x0, 0
        repeat(35) @(posedge clk);

        if ((store_misaligned_count - store_misaligned_count_before) == 1)
            $display("[PASS] 未对齐 SW 只触发一次 cause=6 Trap");
        else begin
            $display("[FAIL] 未对齐 SW Trap 次数=%0d, 期望=1",
                     store_misaligned_count - store_misaligned_count_before);
            error_count = error_count + 1;
        end
        if ((store_commit_count - store_commit_count_before) == 0)
            $display("[PASS] 未对齐 SW 未产生内存写使能");
        else begin
            $display("[FAIL] 未对齐 SW 产生了 %0d 次内存写",
                     store_commit_count - store_commit_count_before);
            error_count = error_count + 1;
        end
        if ((dut.u_reg_file.regs[4] === 32'd6) &&
            (dut.u_reg_file.regs[5] === 32'h000000e4) &&
            (dut.u_reg_file.regs[25] === 32'd1))
            $display("[PASS] SW 异常 cause/mepc/返回执行正确");
        else begin
            $display("[FAIL] SW 异常现场错误: cause=%h mepc_next=%h x25=%h",
                     dut.u_reg_file.regs[4], dut.u_reg_file.regs[5],
                     dut.u_reg_file.regs[25]);
            error_count = error_count + 1;
        end

        // 【阶段 11】：RV32I 的控制流目标必须按 4 字节对齐。
        $display("[TB PHASE] Instruction address misaligned trap");
        wait (inst_addr === 32'h000000e8);
        inst_misaligned_count_before = inst_misaligned_count;
        @(negedge clk);
        inst_mem[58] = 32'h0080006f; // E8: jal  x0, 0xF0
        inst_mem[60] = 32'h0020006f; // F0: jal  x0, +2 (目标 0xF2 未对齐)
        inst_mem[61] = 32'h00100d13; // F4: addi x26, x0, 1
        inst_mem[62] = 32'h0000006f; // F8: jal  x0, 0
        repeat(35) @(posedge clk);

        if ((inst_misaligned_count - inst_misaligned_count_before) == 1)
            $display("[PASS] 未对齐 JAL 目标只触发一次 cause=0 Trap");
        else begin
            $display("[FAIL] 未对齐 JAL Trap 次数=%0d, 期望=1",
                     inst_misaligned_count - inst_misaligned_count_before);
            error_count = error_count + 1;
        end
        if ((dut.u_reg_file.regs[4] === 32'd0) &&
            (dut.u_reg_file.regs[5] === 32'h000000f4) &&
            (dut.u_reg_file.regs[26] === 32'd1))
            $display("[PASS] 指令地址异常 cause/mepc/返回执行正确");
        else begin
            $display("[FAIL] 指令地址异常现场错误: cause=%h mepc_next=%h x26=%h",
                     dut.u_reg_file.regs[4], dut.u_reg_file.regs[5],
                     dut.u_reg_file.regs[26]);
            error_count = error_count + 1;
        end

        // 【阶段 12】：同步异常和 Timer 同时到达时，先处理 ECALL；
        // Timer 请求必须保持，并在 MRET 恢复 MIE 后再处理。
        $display("[TB PHASE] Synchronous exception preserves pending Timer");
        wait (inst_addr === 32'h000000f8);
        ecall_trap_count_before = ecall_trap_count;
        timer_trap_count_before = timer_trap_count;
        @(negedge clk);
        inst_mem[62] = 32'h0040006f; // F8:  jal  x0, 0xFC
        inst_mem[63] = 32'h00000073; // FC:  ecall
        inst_mem[64] = 32'h00100d93; // 100: addi x27, x0, 1
        inst_mem[65] = 32'h0000006f; // 104: jal  x0, 0

        wait ((dut.pc_ex === 32'h000000fc) && dut.is_ecall_ex);
        @(negedge clk);
        timer_int = 1'b1;
        #1;
        if (dut.trap_valid && (dut.trap_cause === 32'd11))
            $display("[PASS] ECALL 与 Timer 同周期时同步异常优先");
        else begin
            $display("[FAIL] ECALL/Timer 同周期优先级错误, cause=%h",
                     dut.trap_cause);
            error_count = error_count + 1;
        end
        @(negedge clk);
        timer_int = 1'b0;
        repeat(45) @(posedge clk);

        if ((ecall_trap_count - ecall_trap_count_before) == 1)
            $display("[PASS] 同步 ECALL 只处理一次");
        else begin
            $display("[FAIL] ECALL Trap 次数=%0d, 期望=1",
                     ecall_trap_count - ecall_trap_count_before);
            error_count = error_count + 1;
        end
        if ((timer_trap_count - timer_trap_count_before) == 1)
            $display("[PASS] 延后的 Timer 请求在 MRET 后处理一次");
        else begin
            $display("[FAIL] 延后 Timer Trap 次数=%0d, 期望=1",
                     timer_trap_count - timer_trap_count_before);
            error_count = error_count + 1;
        end
        if ((dut.u_reg_file.regs[4] === 32'h80000007) &&
            (dut.u_reg_file.regs[27] === 32'd1))
            $display("[PASS] 延后中断处理后程序继续前进 (x27=1)");
        else begin
            $display("[FAIL] 延后中断返回错误: cause=%h x27=%h",
                     dut.u_reg_file.regs[4], dut.u_reg_file.regs[27]);
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
