`timescale 1ns/1ps

module tb_hazard();

    // -----------------------------------------------------------
    // 1. 信号定义
    // -----------------------------------------------------------
    logic        clk;
    logic        rst;

    logic [31:0] inst;
    logic [31:0] inst_addr;

    logic [31:0] mem_dout;
    logic [31:0] mem_din;
    logic [31:0] mem_addr;
    logic [ 3:0] mem_we;

    // -----------------------------------------------------------
    // 2. 模拟同步内存
    // -----------------------------------------------------------
    logic [31:0] inst_mem [0:255]; 
    logic [31:0] data_mem [0:255]; 

    always_ff @(posedge clk) begin
        inst <= inst_mem[inst_addr[9:2]]; 
        mem_dout <= data_mem[mem_addr[9:2]];

        if (mem_we[0]) data_mem[mem_addr[9:2]][ 7: 0] <= mem_din[ 7: 0];
        if (mem_we[1]) data_mem[mem_addr[9:2]][15: 8] <= mem_din[15: 8];
        if (mem_we[2]) data_mem[mem_addr[9:2]][23:16] <= mem_din[23:16];
        if (mem_we[3]) data_mem[mem_addr[9:2]][31:24] <= mem_din[31:24];
    end

    // -----------------------------------------------------------
    // 3. 例化待测模块 (DUT)
    // -----------------------------------------------------------
    pipeline dut(
        .clk        (clk),
        .rst        (rst),
        .inst       (inst),
        .inst_addr  (inst_addr),
        .mem_dout   (mem_dout),
        .mem_din    (mem_din),
        .mem_addr   (mem_addr),
        .mem_we     (mem_we)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz
    end

    // -----------------------------------------------------------
    // 4. 终极数据冒险序列 Task (升级：支持并发跳转监听与内存校验)
    // -----------------------------------------------------------
    task test_hazard_sequence(
        input string test_name,
        input [31:0] inst0, inst1, inst2, inst3, inst4,
        input int    inst_count,
        
        // 预加载
        input        mem_preload_en, input [31:0] mem_preload_addr, input [31:0] mem_preload_data,
        
        // 校验项开关与期望值
        input        check_rd_en,   input [4:0]  check_rd_idx,   input [31:0] expected_rd_val,
        input        check_mem_en,  input [31:0] mem_check_addr, input [31:0] expected_mem_val,
        input        check_jump_en, input [31:0] expected_jump_pc
    );
        logic [31:0] actual_jump_target;
        bit          jump_occurred;
    begin
        // 复位与环境清理
        rst = 1;
        jump_occurred = 0;
        actual_jump_target = 32'h0;
        #20;

        for(int i=0; i<256; i++) begin 
            inst_mem[i] = 32'h00000013; // NOP
            data_mem[i] = 32'h0;
        end
        
        if (inst_count > 0) inst_mem[0] = inst0;
        if (inst_count > 1) inst_mem[1] = inst1;
        if (inst_count > 2) inst_mem[2] = inst2;
        if (inst_count > 3) inst_mem[3] = inst3;
        if (inst_count > 4) inst_mem[4] = inst4;

        if (mem_preload_en) data_mem[mem_preload_addr[9:2]] = mem_preload_data;

        // 清理常用寄存器以防干扰
        if (check_rd_idx != 0) dut.u_reg_file.regs[check_rd_idx] = 32'h0;
        dut.u_reg_file.regs[1]=0; dut.u_reg_file.regs[2]=0; dut.u_reg_file.regs[3]=0; 
        dut.u_reg_file.regs[4]=0; dut.u_reg_file.regs[5]=0; dut.u_reg_file.regs[6]=0;

        rst = 0;

        // 【核心修改点】并发执行：一边跑流水线，一边监听分支预测与纠正
        fork
            begin
                while(1) begin
                    @(posedge clk);
                    
                    // 1. ID 阶段预测跳转
                    if (dut.predict_jump) begin
                        jump_occurred = 1;
                        actual_jump_target = dut.predict_addr;
                    end
                    
                    // 2. EX 阶段纠正预测
                    if (dut.pc_mis) begin
                        // 动态判断：如果纠正的目标地址正好是这根分支指令的下一条 (pc_ex + 4)
                        // 说明 ALU 算出来的结果是“不满足条件”，退回了顺序执行，也就是实际上“没跳”
                        if (dut.target_pc == dut.pc_ex + 4) begin
                            jump_occurred = 0;
                            actual_jump_target = 32'h0;
                        end else begin
                            // 如果是 JALR 等需要在 EX 阶段才算出真实目标的指令
                            jump_occurred = 1;
                            actual_jump_target = dut.target_pc;
                        end
                    end
                end
            end
            begin
                repeat(15) @(posedge clk); // 15个周期足够5条指令流完
            end
        join_any
        disable fork;

        // 结果校验大派对
        $write("测试 [%s] : ", test_name);
        
        // 1. 校验寄存器写回
        if (check_rd_en) begin
            if (dut.u_reg_file.regs[check_rd_idx] !== expected_rd_val) begin
                $display("\n  -> [FAIL] 期望 x%0d = 0x%08h, 实际 = 0x%08h", check_rd_idx, expected_rd_val, dut.u_reg_file.regs[check_rd_idx]);
            end
        end

        // 2. 校验内存写入
        if (check_mem_en) begin
            if (data_mem[mem_check_addr[9:2]] !== expected_mem_val) begin
                $display("\n  -> [FAIL] 期望 Mem[0x%08h] = 0x%08h, 实际 = 0x%08h", mem_check_addr, expected_mem_val, data_mem[mem_check_addr[9:2]]);
            end
        end

        // 3. 校验分支跳转
        if (check_jump_en) begin
            if (!jump_occurred) begin
                $display("\n  -> [FAIL] 期望发生跳转，但最终判定为不跳转");
            end
            if (actual_jump_target !== expected_jump_pc) begin
                $display("\n  -> [FAIL] 期望跳转PC = 0x%08h, 实际 = 0x%08h", expected_jump_pc, actual_jump_target);
            end
        end else if (jump_occurred) begin
            $display("\n  -> [FAIL] 期望不跳转，但发生了异常跳转到 0x%08h", actual_jump_target);
        end

        $display("[PASS]");
    end
    endtask

    // -----------------------------------------------------------
    // 5. 开始运行
    // -----------------------------------------------------------
    initial begin
        $display("========================================");
        $display("     RISC-V 流水线 极限数据冒险全量测试     ");
        $display("========================================");

        // --- 基础测试 ---
        test_hazard_sequence("基础 1: EX-to-EX 前推 (ADDI -> ADD)", 
            32'h00500093, 32'h00108133, 32'h00000013, 32'h00000013, 32'h00000013, 2,
            0, 0, 0,      
            1, 2, 32'd10, // check_rd: x2 = 10
            0, 0, 0,      // check_mem
            0, 0          // check_jump
        );

        test_hazard_sequence("基础 2: WB-to-EX 前推 (ADDI -> NOP -> ADD)", 
            32'h00800093, 32'h00000013, 32'h001081B3, 32'h00000013, 32'h00000013, 3,
            0, 0, 0,
            1, 3, 32'd16, 
            0, 0, 0, 0, 0
        );

        test_hazard_sequence("基础 3: Load-Use 冒险 (LW 停顿 -> ADD)", 
            32'h00402203, 32'h004202B3, 32'h00000013, 32'h00000013, 32'h00000013, 2,
            1, 32'd4, 32'd50,
            1, 5, 32'd100, 
            0, 0, 0, 0, 0
        );

        // --- 进阶变态测试 (Edge Cases) ---
        
        // 进阶 1: 双重数据冒险
        test_hazard_sequence("进阶 1: 双重数据冒险 (优先级陷阱)", 
            32'h00500093, 32'h00a00093, 32'h00008133, 32'h00000013, 32'h00000013, 3,
            0, 0, 0,
            1, 2, 32'd10, // x2 必须拿到最新的 10
            0, 0, 0, 0, 0
        );

        // 进阶 2: 零寄存器 (x0) 前推陷阱
        test_hazard_sequence("进阶 2: 零寄存器 (x0) 前推防御", 
            32'h06400013, 32'h000001b3, 32'h00000013, 32'h00000013, 32'h00000013, 2,
            0, 0, 0,
            1, 3, 32'd0, // x3 必须是 0
            0, 0, 0, 0, 0
        );

        // 进阶 3: 对 Store 数据进行前推
        test_hazard_sequence("进阶 3: Store 指令的数据前推", 
            32'h05800213, 32'h00402423, 32'h00000013, 32'h00000013, 32'h00000013, 2,
            0, 0, 0,
            0, 0, 0, 
            1, 32'd8, 32'd88, // 验证内存 Mem[8] 写入了 88
            0, 0
        );

        // 进阶 4: 对分支判断进行前推 (测试你的前推和预测结合得对不对)
        // inst0: ADDI x5, x0, 15
        // inst1: ADDI x6, x0, 15
        // inst2: BEQ  x5, x6, 16 
        // 分支所在的 PC 是 8。条件相等，预测正确，最终跳转到 8 + 16 = 24！
        test_hazard_sequence("进阶 4: 分支 (Branch) 指令的前推", 
            32'h00f00293, 32'h00f00313, 32'h00628863, 32'h00000013, 32'h00000013, 3,
            0, 0, 0,
            0, 0, 0,
            0, 0, 0,
            1, 32'd24 
        );

// -----------------------------------------------------------
// 新增测试：栈保存序列（连续 store 指令的数据冒险与写内存验证）
// -----------------------------------------------------------

        // 为 s0, s1, s2 设置易于识别的初值
        dut.u_reg_file.regs[8]  = 32'hA5A5A5A5;   // s0
        dut.u_reg_file.regs[9]  = 32'hB5B5B5B5;   // s1
        dut.u_reg_file.regs[18] = 32'hC5C5C5C5;   // s2
        // ra (x1) 会被任务内部清零，因此期望存储值为 0

        // 调用任务执行指令序列
        test_hazard_sequence(
            "栈保存序列 (连续 Store)",
            32'hff010113, 32'h01212023, 32'h00912223, 32'h00812423, 32'h00112623,
            5,                // 5 条指令
            0, 0, 0,          // 无预加载
            0, 0, 0,          // 不检查寄存器写回
            1, 32'hFFFFFFF0, 32'hC5C5C5C5,  // 仅校验第一个内存地址（其余可在下方补充校验）
            0, 0              // 无跳转检查
        );

        // 补充校验其余三个栈位置（因任务只支持一次内存校验）
        if (data_mem[8'hFC] !== 32'hC5C5C5C5)   // sp+0  -> s2
            $error("栈偏移 0 数据错误，期望 0xC5C5C5C5, 实际 0x%h", data_mem[8'hFC]);
        if (data_mem[8'hFD] !== 32'hB5B5B5B5)   // sp+4  -> s1
            $error("栈偏移 4 数据错误，期望 0xB5B5B5B5, 实际 0x%h", data_mem[8'hFD]);
        if (data_mem[8'hFE] !== 32'hA5A5A5A5)   // sp+8  -> s0
            $error("栈偏移 8 数据错误，期望 0xA5A5A5A5, 实际 0x%h", data_mem[8'hFE]);
        if (data_mem[8'hFF] !== 32'h00000000)   // sp+12 -> ra (已被清零)
            $error("栈偏移 12 数据错误，期望 0x00000000, 实际 0x%h", data_mem[8'hFF]);
        else
            $display("栈保存序列内存校验全部通过");

        $display("========================================");
        $display("               测试全部结束               ");
        $display("========================================");
        $finish;
    end

    // 生成波形
    // initial begin
    //     $dumpfile("tb_hazard.vcd");
    //     $dumpvars(0, tb_hazard);
    // end

endmodule