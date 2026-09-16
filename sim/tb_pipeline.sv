`timescale 1ns/1ps
`include "micro.vh"

module tb_pipeline();

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
    integer      error_count = 0;

    // -----------------------------------------------------------
    // 2. 模拟同步内存 (Instruction & Data)
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
        .mem_we     (mem_we),
        .timer_int  (1'b0)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz
    end

    // -----------------------------------------------------------
    // 4. 终极单指令测试 Task (升级版：支持分支预测与纠正监听)
    // -----------------------------------------------------------
    task test_single_inst(
        input string test_name,
        input [31:0] machine_code,
        // 寄存器预设
        input [4:0]  rs1_idx, input [31:0] rs1_init,
        input [4:0]  rs2_idx, input [31:0] rs2_init,
        // 内存预设 (用于 Load 指令)
        input        mem_preload_en, input [31:0] mem_preload_addr, input [31:0] mem_preload_data,
        
        // 校验控制位与期望值
        input        check_rd,   input [4:0]  rd_idx,   input [31:0] rd_expected,
        input        check_mem,  input [31:0] mem_check_addr, input [31:0] mem_expected,
        input        check_jump, input [31:0] pc_expected
    );
        logic [31:0] actual_jump_target;
        bit          jump_occurred;
        bit          pass;
    begin
        // 1. 发起复位
        rst = 1;
        jump_occurred = 0;
        actual_jump_target = 32'h0;

        // 2. 先初始化同步存储器，再保持复位两个周期。
        // 若先等待、后填充，第一次测试在复位释放时仍会看到未知指令，
        // 严格译码会把它正确识别为非法指令并触发 Trap。
        for(int i=0; i<256; i++) begin 
            inst_mem[i] = 32'h00000013; // 填充 NOP
            data_mem[i] = 32'h0;
        end
        inst_mem[0] = machine_code; // PC=0处放置待测指令

        // 内存预载
        if (mem_preload_en) data_mem[mem_preload_addr[9:2]] = mem_preload_data;

        #20;

        // 3. 释放复位
        rst = 0;

        // 4. 后门预设源寄存器初值 
        if (rs1_idx != 0) dut.u_reg_file.regs[rs1_idx] = rs1_init;
        if (rs2_idx != 0) dut.u_reg_file.regs[rs2_idx] = rs2_init;
        if (check_rd && rd_idx != 0) dut.u_reg_file.regs[rd_idx] = 32'h0; 

        // 5. 并发执行：等待流水线走完，同时监听分支预测与纠正动作
        fork
            begin
                // 【核心修改点】监听分支预测与纠正
                // 注意：这里假设 predict_jump, predict_addr, pc_mis, target_pc 
                // 是在 pipeline.sv 顶层声明的 wire/logic。如果它们在内部模块，请修改层级路径。
                while (1) begin
                    @(posedge clk);
                    
                    // a) ID 阶段的“预测跳转” (B型 / JAL)
                    if ((dut.pc_sel == `PC_B) || (dut.pc_sel == `PC_J)) begin
                        jump_occurred = 1;
                        actual_jump_target = dut.u_pc_reg.pred_pc;
                    end
                    
                    // b) EX 阶段的“预测失败纠正” (优先级更高，会覆盖前面的预测结果)
                    if (dut.pc_mis) begin
                        // 如果纠正地址是 4 (因为我们测试单指令，PC是0，下一条是4)
                        // 说明 ALU 发现条件不满足，退回了顺序执行，实际上等于没跳
                        if (dut.target_pc == 32'h4) begin
                            jump_occurred = 0; 
                            actual_jump_target = 32'h0;
                        end else begin
                            // 如果是 JALR 等需要在 EX 阶段给出真实目标的指令
                            jump_occurred = 1;
                            actual_jump_target = dut.target_pc;
                        end
                    end
                end
            end
            begin
                // 等待足够多的周期让指令走完 WB 阶段
                repeat(7) @(posedge clk);
            end
        join_any
        disable fork; // 7个周期到了，关闭监听

        // 6. 结果校验
        $write("测试 [%s] : ", test_name);
        pass = 1;
        
        // 校验寄存器写回 (R型, I型, U型, J型, Load)
        if (check_rd && rd_idx != 0) begin
            if (dut.u_reg_file.regs[rd_idx] !== rd_expected) begin
                $display("\n  -> [FAIL] 期望 x%0d = 0x%08h, 实际 = 0x%08h", rd_idx, rd_expected, dut.u_reg_file.regs[rd_idx]);
                error_count = error_count + 1;
                pass = 0;
            end
        end

        // 校验内存改写 (S型 Store)
        if (check_mem) begin
            if (data_mem[mem_check_addr[9:2]] !== mem_expected) begin
                $display("\n  -> [FAIL] 期望 Mem[0x%08h] = 0x%08h, 实际 = 0x%08h", mem_check_addr, mem_expected, data_mem[mem_check_addr[9:2]]);
                error_count = error_count + 1;
                pass = 0;
            end
        end

        // 校验跳转PC (B型, J型)
        if (check_jump) begin
            if (!jump_occurred) begin
                $display("\n  -> [FAIL] 期望发生跳转，但最终判定为不跳转");
                error_count = error_count + 1;
                pass = 0;
            end
            if (actual_jump_target !== pc_expected) begin
                $display("\n  -> [FAIL] 期望跳转PC = 0x%08h, 实际 = 0x%08h", pc_expected, actual_jump_target);
                error_count = error_count + 1;
                pass = 0;
            end
        end else if (jump_occurred) begin
            $display("\n  -> [FAIL] 期望不跳转，但发生了异常跳转到 0x%08h", actual_jump_target);
            error_count = error_count + 1;
            pass = 0;
        end

        if (pass) $display("[PASS]");
    end
    endtask

    // -----------------------------------------------------------
    // 5. 运行多轮测试用例
    // -----------------------------------------------------------
    initial begin
        $display("========================================");
        $display("   RISC-V 32I 流水线 CPU 分支预测测试   ");
        $display("========================================");

        // 1. R-Type 测试
        test_single_inst(
            "R-Type: ADD x3, x1, x2", 32'h002081B3,
            1, 32'd10, 2, 32'd20,
            0, 32'd0, 32'd0,
            1, 3, 32'd30,
            0, 32'd0, 32'd0,
            0, 32'd0
        );

        // 2. I-Type 算术 测试
        test_single_inst(
            "I-Type: ADDI x1, x0, 15", 32'h00F00093,
            0, 32'd0, 0, 32'd0,
            0, 32'd0, 32'd0,
            1, 1, 32'd15,
            0, 32'd0, 32'd0,
            0, 32'd0
        );

        // 3. I-Type Load 测试
        test_single_inst(
            "I-Type(Load): LW x2, 4(x1)", 32'h0040A103,
            1, 32'd8, 0, 32'd0,
            1, 32'd12, 32'hDEADBEEF,
            1, 2, 32'hDEADBEEF,
            0, 32'd0, 32'd0,
            0, 32'd0
        );

        // 4. S-Type 测试
        test_single_inst(
            "S-Type: SW x2, 4(x1)", 32'h0020A223,
            1, 32'd8, 2, 32'hAABBCCDD,
            0, 32'd0, 32'd0,
            0, 0, 32'd0,
            1, 32'd12, 32'hAABBCCDD,
            0, 32'd0
        );

        // 5. B-Type 预测正确测试 (条件满足，跳)
        test_single_inst(
            "B-Type: BEQ x1, x2, 16 (Taken - 预测成功)", 32'h00208463,
            1, 32'd5, 2, 32'd5, // 条件相等
            0, 32'd0, 32'd0,
            0, 0, 32'd0,
            0, 32'd0, 32'd0,
            1, 32'd8 // 校验最终PC跳转到了16
        );

        // 6. U-Type 测试
        test_single_inst(
            "U-Type: AUIPC x5, 0x12345", 32'h12345297,
            0, 32'd0, 0, 32'd0,
            0, 32'd0, 32'd0,
            1, 5, 32'h12345000,
            0, 32'd0, 32'd0,
            0, 32'd0
        );

        // 7. J-Type 测试
        test_single_inst(
            "J-Type: JAL x1, 16", 32'h010000EF,
            0, 32'd0, 0, 32'd0,
            0, 32'd0, 32'd0,
            1, 1, 32'd4,  
            0, 32'd0, 32'd0,
            1, 32'd16     
        );

        // 8. 【新增】B-Type 预测失败纠正测试 (条件不满足，不跳)
        test_single_inst(
            "B-Type: BEQ x1, x2, 8 (Not Taken - 预测失败纠正)", 32'h00208463,
            1, 32'd5, 2, 32'd99, // 创造不相等条件，ALU会判定不跳
            0, 32'd0, 32'd0,
            0, 0, 32'd0,
            0, 32'd0, 32'd0,
            0, 32'd0 // 期望发生 pc_mis 纠正，最终判定为没跳
        );

        $display("========================================");
        $display("   所有指令测试完毕");
        $display("========================================");
        if (error_count == 0) begin
            $display("[TB PASS] tb_pipeline");
            $finish;
        end else begin
            $fatal(1, "[TB FAIL] tb_pipeline: %0d checks failed", error_count);
        end
    end

    // 生成波形
    // initial begin
    //     $dumpfile("tb_pipeline.vcd");
    //     $dumpvars(0, tb_pipeline);
    // end

endmodule
