`timescale 1ns / 1ps

module tb_z_2;

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
    // 同步内存模型
    // ==========================================
    logic [31:0] imem [0:1023];
    logic [31:0] dmem [0:1023];

    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            imem[i] = 32'h00000013; // NOP
            dmem[i] = 32'h00000000;
        end
    end

    // 同步指令存储器
    always_ff @(posedge clk) begin
        inst <= imem[inst_addr[11:2]];
    end

    // 同步数据存储器
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
    // DUT
    // ==========================================
    pipeline uut (
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

    // ==========================================
    // 时钟
    // ==========================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ==========================================
    // Task
    // ==========================================
    task wait_cycles(input integer n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1)
                @(posedge clk);
        end
    endtask

    task wait_until_illegal_exception(
        input integer max_cycles,
        output logic hit
    );
        integer cnt;
        begin
            hit = 1'b0;
            cnt = 0;
            while (cnt < max_cycles) begin
                @(posedge clk);
                if ((uut.u_csr_regfile.mcause[31] === 1'b0) &&
                    (uut.u_csr_regfile.mcause[3:0] === 4'd2) &&
                    (uut.u_csr_regfile.mepc === 32'h00000014)) begin
                    hit = 1'b1;
                    cnt = max_cycles;
                end else begin
                    cnt = cnt + 1;
                end
            end
        end
    endtask

    task wait_until_handler_effect(
        input integer max_cycles,
        output logic hit
    );
        integer cnt;
        begin
            hit = 1'b0;
            cnt = 0;
            while (cnt < max_cycles) begin
                @(posedge clk);
                if ((uut.pc_de === 32'h00000040) ||
                    (uut.u_csr_regfile.mepc === 32'h00000018) ||
                    (uut.mret_de === 1'b1) ||
                    (uut.mret_mem === 1'b1)) begin
                    hit = 1'b1;
                    cnt = max_cycles;
                end else begin
                    cnt = cnt + 1;
                end
            end
        end
    endtask

    task wait_until_mepc_written(
        input [31:0] expected,
        input integer max_cycles,
        output logic hit
    );
        integer cnt;
        begin
            hit = 1'b0;
            cnt = 0;
            while (cnt < max_cycles) begin
                @(posedge clk);
                if (uut.u_csr_regfile.mepc === expected) begin
                    hit = 1'b1;
                    cnt = max_cycles;
                end else begin
                    cnt = cnt + 1;
                end
            end
        end
    endtask

    task wait_until_mret_mem(
        input integer max_cycles,
        output logic hit
    );
        integer cnt;
        begin
            hit = 1'b0;
            cnt = 0;
            while (cnt < max_cycles) begin
                @(posedge clk);
                if (uut.mret_mem === 1'b1) begin
                    hit = 1'b1;
                    cnt = max_cycles;
                end else begin
                    cnt = cnt + 1;
                end
            end
        end
    endtask

    task wait_until_returned_to_main(
        input integer max_cycles,
        output logic hit
    );
        integer cnt;
        begin
            hit = 1'b0;
            cnt = 0;
            while (cnt < max_cycles) begin
                @(posedge clk);
                // 返回后会先到 0x18，再很快到 0x1c 自旋
                if ((uut.pc_de === 32'h00000018) ||
                    (uut.pc_de === 32'h0000001c) ||
                    (uut.inst_addr === 32'h00000018) ||
                    (uut.inst_addr === 32'h0000001c)) begin
                    hit = 1'b1;
                    cnt = max_cycles;
                end else begin
                    cnt = cnt + 1;
                end
            end
        end
    endtask

    // ==========================================
    // 测试标志
    // ==========================================
    logic hit_illegal_exc;
    logic hit_handler_effect;
    logic hit_mepc_18;
    logic hit_mret_mem;
    logic hit_return_main;

    logic trap_entered;
    logic mepc_fixed;

    // ==========================================
    // 主测试流程
    // ==========================================
    initial begin
        rst = 1'b1;
        rxd = 1'b1; // 不触发外部中断

        // 主程序
        imem[0] = 32'h04000093; // 0x00: addi x1, x0, 64        ; x1 = 0x40
        imem[1] = 32'h30509073; // 0x04: csrrw x0, mtvec, x1    ; mtvec = 0x40

        imem[2] = 32'h00F00113; // 0x08: addi x2, x0, 15
        imem[3] = 32'h30411073; // 0x0c: csrrw x0, mie, x2      ; mie = 0xF
        imem[4] = 32'h30402173; // 0x10: csrrs x2, mie, x0      ; 只读，不写

        imem[5] = 32'hFFF09073; // 0x14: csrrw x0, 0xFFF, x1    ; 非法 CSR，触发异常
        imem[6] = 32'h00100093; // 0x18: addi x1, x0, 1         ; mret 后应回到这里
        imem[7] = 32'h0000006F; // 0x1c: jal x0, 0              ; 原地自旋，避免掉进 0x40

        // Trap handler @ 0x40
        imem[16] = 32'h34102F73; // 0x40: csrrs x30, mepc, x0
        imem[17] = 32'h004F0F13; // 0x44: addi  x30, x30, 4
        imem[18] = 32'h341F1073; // 0x48: csrrw x0, mepc, x30
        imem[19] = 32'h30200073; // 0x4c: mret

        #15;
        rst = 1'b0;

        $display("\n================ 测试开始 ================");

        trap_entered = 1'b0;
        mepc_fixed   = 1'b0;

        // 先让前几条指令跑起来
        wait_cycles(12);

        // 1. 免写测试
        if ((uut.u_csr_regfile.mie === 32'h0000000F) &&
            (uut.u_reg_file.regs[2] === 32'h0000000F)) begin
            $display("[成功] 免写测试 : CSRRS x0 未修改寄存器值，x2 正确读回 0xF");
        end else begin
            $display("[失败] 免写测试 : mie=0x%h, x2=0x%h",
                     uut.u_csr_regfile.mie, uut.u_reg_file.regs[2]);
        end

        // 2. 异常记录测试
        wait_until_illegal_exception(40, hit_illegal_exc);
        if (hit_illegal_exc) begin
            $display("[成功] 异常记录 : mcause=非法指令异常, mepc=0x14");
        end else begin
            $display("[失败] 异常记录 : 未观察到 mcause=2 且 mepc=0x14，当前 mcause=0x%h, mepc=0x%h",
                     uut.u_csr_regfile.mcause, uut.u_csr_regfile.mepc);
        end

        // 3. handler 执行痕迹测试
        wait_until_handler_effect(60, hit_handler_effect);
        if (hit_handler_effect) begin
            trap_entered = 1'b1;
            $display("[成功] 异常跳转 : 已观察到 handler 执行痕迹（pc_de=0x40 或 mepc=0x18 或 mret出现）");
        end else begin
            trap_entered = 1'b0;
            $display("[失败] 异常跳转 : 在限定周期内未观察到 handler 执行痕迹，当前 pc_de=0x%h mepc=0x%h",
                     uut.pc_de, uut.u_csr_regfile.mepc);
        end

        // 4. Handler 修改 mepc
        if (trap_entered) begin
            wait_until_mepc_written(32'h00000018, 40, hit_mepc_18);
            if (hit_mepc_18) begin
                mepc_fixed = 1'b1;
                $display("[成功] Handler 修改 mepc : mepc 已更新为 0x18");
            end else begin
                mepc_fixed = 1'b0;
                $display("[失败] Handler 修改 mepc : 未观察到 mepc=0x18，当前 mepc=0x%h",
                         uut.u_csr_regfile.mepc);
            end
        end else begin
            mepc_fixed = 1'b0;
            $display("[跳过] Handler 修改 mepc : 因未确认进入 trap，本项无效");
        end

        // 5. MRET 返回测试
        if (trap_entered && mepc_fixed) begin
            wait_until_mret_mem(40, hit_mret_mem);
            if (!hit_mret_mem) begin
                $display("[失败] MRET 返回 : 未观察到 mret 进入 MEM 级");
            end else begin
                wait_until_returned_to_main(40, hit_return_main);
                if (hit_return_main) begin
                    $display("[成功] MRET 返回 : 成功回到 0x18/0x1c 继续执行主程序");
                end else begin
                    $display("[失败] MRET 返回 : 已观察到 mret_mem，但未观察到返回主程序，当前 pc_de=0x%h inst_addr=0x%h",
                             uut.pc_de, uut.inst_addr);
                end
            end
        end else begin
            $display("[跳过] MRET 返回 : 因 trap/handler 未验证通过，本项无效");
        end

        $display("mcause = 0x%h", uut.u_csr_regfile.mcause);
        $display("mepc   = 0x%h", uut.u_csr_regfile.mepc);
        $display("inst_addr = 0x%h", uut.inst_addr);
        $display("pc_de = 0x%h", uut.pc_de);
        $display("mret_mem  = %b", uut.mret_mem);
        $display("exception_de = %b", uut.exception_de);
        $display("inst_de = 0x%h", uut.inst_de);

        $display("================ 测试结束 ================\n");
        $finish;
    end

    // ==========================================
    // 调试输出
    // ==========================================
    initial begin
        $dumpfile("pipeline_wave.vcd");
        $dumpvars(0, tb_z_2);
    end

    always @(posedge clk) begin
        if (uut.exception_de) begin
            $display("[EXC] time=%0t pc_de=0x%08h inst_de=0x%08h code=%0d mepc(before)=0x%08h",
                     $time,
                     uut.pc_de,
                     uut.inst_de,
                     uut.exception_code_de,
                     uut.u_csr_regfile.mepc);
        end
    end

    always @(posedge clk) begin
        if (uut.mret_de || uut.mret_mem) begin
            $display("[MRET] time=%0t mret_de=%b mret_mem=%b mepc_out=0x%08h inst_addr=0x%08h pc_de=0x%08h",
                     $time,
                     uut.mret_de,
                     uut.mret_mem,
                     uut.mepc_out,
                     uut.inst_addr,
                     uut.pc_de);
        end
    end

endmodule
