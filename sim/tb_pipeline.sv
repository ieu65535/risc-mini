`timescale 1ns/1ps

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
        .mem_we     (mem_we)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz
    end

    // -----------------------------------------------------------
    // 4. 终极单指令测试 Task (支持所有六大类指令校验)
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
    begin
        // 1. 发起复位
        rst = 1;
        jump_occurred = 0;
        actual_jump_target = 32'h0;
        #20;

        // 2. 环境初始化 (清空指令/数据内存)
        for(int i=0; i<256; i++) begin 
            inst_mem[i] = 32'h00000013; // 填充 NOP
            data_mem[i] = 32'h0;
        end
        inst_mem[0] = machine_code; // PC=0处放置待测指令

        // 内存预载 (例如测试 LW 时，先把数据放进去)
        if (mem_preload_en) data_mem[mem_preload_addr[9:2]] = mem_preload_data;

        // 3. 释放复位
        rst = 0;

        // 4. 后门预设源寄存器初值 
        // 【重要提醒】如果你的寄存器堆叫其他名字，请修改 .u_reg_file.regs 为对应的变量名
        if (rs1_idx != 0) dut.u_reg_file.regs[rs1_idx] = rs1_init;
        if (rs2_idx != 0) dut.u_reg_file.regs[rs2_idx] = rs2_init;
        if (check_rd && rd_idx != 0) dut.u_reg_file.regs[rd_idx] = 32'h0; 

        // 5. 并发执行：等待流水线走完，同时监听跳转动作
        fork
            begin
                // 监听分支跳转 (由于流水线在 EX 阶段更新 do_jump)
                while (1) begin
                    @(posedge clk);
                    if (dut.do_jump) begin
                        jump_occurred = 1;
                        actual_jump_target = dut.jump_addr;
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
        
        // 校验寄存器写回 (R型, I型, U型, J型, Load)
        if (check_rd && rd_idx != 0) begin
            if (dut.u_reg_file.regs[rd_idx] !== rd_expected) begin
                $display("\n  -> [FAIL] 期望 x%0d = 0x%08h, 实际 = 0x%08h", rd_idx, rd_expected, dut.u_reg_file.regs[rd_idx]);
            end
        end

        // 校验内存改写 (S型 Store)
        if (check_mem) begin
            if (data_mem[mem_check_addr[9:2]] !== mem_expected) begin
                $display("\n  -> [FAIL] 期望 Mem[0x%08h] = 0x%08h, 实际 = 0x%08h", mem_check_addr, mem_expected, data_mem[mem_check_addr[9:2]]);
            end
        end

        // 校验跳转PC (B型, J型)
        if (check_jump) begin
            if (!jump_occurred) begin
                $display("\n  -> [FAIL] 期望发生跳转，但未检测到 do_jump");
            end
            if (actual_jump_target !== pc_expected) begin
                $display("\n  -> [FAIL] 期望跳转PC = 0x%08h, 实际 = 0x%08h", pc_expected, actual_jump_target);
            end
        end else if (jump_occurred) begin
            $display("\n  -> [FAIL] 期望不跳转，但发生了异常跳转到 0x%08h", actual_jump_target);
        end

        $display("[PASS]");
    end
    endtask

    // -----------------------------------------------------------
    // 5. 运行多轮测试用例 (六大类全覆盖)
    // -----------------------------------------------------------
    initial begin
        $display("========================================");
        $display("   RISC-V 32I 流水线 CPU 六大类指令测试   ");
        $display("========================================");

        // 参数顺序: 
        // string test_name, 
        // [31:0] machine_code, 
        // [4:0] rs1_idx, [31:0] rs1_init, 
        // [4:0] rs2_idx, [31:0] rs2_init, 
        // mem_preload_en, [31:0] mem_preload_addr, [31:0] mem_preload_data,
        // check_rd, [4:0] rd_idx, [31:0] rd_expected,
        // check_mem, [31:0] mem_check_addr, [31:0] mem_expected,
        // check_jump, [31:0] pc_expected

        // 1. R-Type 测试 (ADD x3, x1, x2)
        // 机器码：0x002081B3 (rs1=1, rs2=2, rd=3)
        test_single_inst(
            "R-Type: ADD x3, x1, x2", 32'h002081B3,
            1, 32'd10, 2, 32'd20,
            0, 32'd0, 32'd0,
            1, 3, 32'd30,
            0, 32'd0, 32'd0,
            0, 32'd0
        );

        // 2. I-Type 算术 测试 (ADDI x1, x0, 15)
        // 机器码：0x00F00093 (rs1=0, imm=15, rd=1)
        test_single_inst(
            "I-Type: ADDI x1, x0, 15", 32'h00F00093,
            0, 32'd0, 0, 32'd0,
            0, 32'd0, 32'd0,
            1, 1, 32'd15,
            0, 32'd0, 32'd0,
            0, 32'd0
        );

        // 3. I-Type Load 测试 (LW x2, 4(x1))
        // 机器码：0x0040A103 (rs1=1(base=8), imm=4, rd=2). 预期访问地址 = 12
        test_single_inst(
            "I-Type(Load): LW x2, 4(x1)", 32'h0040A103,
            1, 32'd8, 0, 32'd0,
            1, 32'd12, 32'hDEADBEEF, // 预设内存
            1, 2, 32'hDEADBEEF,
            0, 32'd0, 32'd0,
            0, 32'd0
        );

        // 4. S-Type 测试 (SW x2, 4(x1))
        // 机器码：0x0020A223 (rs1=1(base=8), rs2=2(数据), imm=4). 预期写入地址 = 12
        test_single_inst(
            "S-Type: SW x2, 4(x1)", 32'h0020A223,
            1, 32'd8, 2, 32'hAABBCCDD,
            0, 32'd0, 32'd0,
            0, 0, 32'd0,
            1, 32'd12, 32'hAABBCCDD, // 校验内存写入
            0, 32'd0
        );

        // 5. B-Type 测试 (BEQ x1, x2, 16)
        // 机器码：0x00208463 (rs1=1, rs2=2, imm=16) -> 当 x1==x2 时跳转到 PC+16
        test_single_inst(
            "B-Type: BEQ x1, x2, 16 (Taken)", 32'h00208463,
            1, 32'd5, 2, 32'd5, // 创造相等条件
            0, 32'd0, 32'd0,
            0, 0, 32'd0,
            0, 32'd0, 32'd0,
            1, 32'd8 // 校验目标PC是否为16
        );

        // 6. U-Type 测试 (AUIPC x5, 0x12345)
        // 机器码：0x12345297 (imm=0x12345, rd=5). 预期 rd = PC + 0x12345000 = 0x12345000 (因为PC=0)
        test_single_inst(
            "U-Type: AUIPC x5, 0x12345", 32'h12345297,
            0, 32'd0, 0, 32'd0,
            0, 32'd0, 32'd0,
            1, 5, 32'h12345000,
            0, 32'd0, 32'd0,
            0, 32'd0
        );

        // 7. J-Type 测试 (JAL x1, 16)
        // 机器码：0x010000EF (imm=16, rd=1). 预期 rd(返回地址)=PC+4=4, 并且 PC跳转到16
        test_single_inst(
            "J-Type: JAL x1, 16", 32'h010000EF,
            0, 32'd0, 0, 32'd0,
            0, 32'd0, 32'd0,
            1, 1, 32'd4,  // 校验返回地址写入
            0, 32'd0, 32'd0,
            1, 32'd16     // 同时校验跳转动作
        );

        $display("========================================");
        $display("   所有指令测试完毕");
        $display("========================================");
        $finish;
    end

    // 生成波形
    initial begin
        $dumpfile("tb_pipeline.vcd");
        $dumpvars(0, tb_pipeline);
    end

endmodule