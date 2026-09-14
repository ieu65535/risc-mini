`timescale 1ns/1ps

module tb_control();

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
    // 4. 辅助 Task：加载微程序并运行校验
    // -----------------------------------------------------------
    
    // 初始化测试环境
    task setup_test(input string name);
    begin
        $display("----------------------------------------");
        $display("测试: %s", name);
        rst = 1;
        #20;
        // 清空内存，填满 NOP
        for(int i=0; i<256; i++) begin
            inst_mem[i] = 32'h00000013;
            data_mem[i] = 32'h0;
        end
        // 清空所有寄存器
        for(int i=1; i<32; i++) dut.u_reg_file.regs[i] = 32'h0;
    end
    endtask

    // 往指定PC地址写机器码
    task load_inst(input [31:0] pc_addr, input [31:0] machine_code);
    begin
        inst_mem[pc_addr[9:2]] = machine_code;
    end
    endtask

    // 运行流水线并校验最多2个寄存器
    task run_and_check(
        input [4:0] reg1_idx, input [31:0] expected1,
        input [4:0] reg2_idx, input [31:0] expected2
    );
        logic pass;
    begin
        rst = 0;
        // 等待足够多的周期让控制流跑完
        repeat(15) @(posedge clk);

        pass = 1;
        if (reg1_idx != 0) begin
            if (dut.u_reg_file.regs[reg1_idx] !== expected1) begin
                $display("  -> [FAIL] 期望 x%0d = %0d, 实际 = %0d", reg1_idx, expected1, dut.u_reg_file.regs[reg1_idx]);
                pass = 0;
            end
        end
        if (reg2_idx != 0) begin
            if (dut.u_reg_file.regs[reg2_idx] !== expected2) begin
                $display("  -> [FAIL] 期望 x%0d = %0d, 实际 = %0d", reg2_idx, expected2, dut.u_reg_file.regs[reg2_idx]);
                pass = 0;
            end
        end

        if (pass) $display("  -> [PASS]");
    end
    endtask

    // -----------------------------------------------------------
    // 5. 测试用例全集
    // -----------------------------------------------------------
    initial begin
        $display("========================================");
        $display("     RISC-V 流水线 控制冒险 (Flush) 测试    ");
        $display("========================================");

        // -------------------------------------------------------
        // 场景 1: 分支未命中 (Branch Not Taken 纠正测试)
        // -------------------------------------------------------
        // [Always Taken 架构下]：ID 阶段会预测跳转到 PC=24，并取出错误指令。
        // 走到 EX 阶段时，发现 5 != 10，必须纠正并 Flush 掉 PC=24 的指令，退回 PC=12 执行。
        setup_test("Branch Not Taken (预测失败纠正)");
        load_inst(0,  32'h00500093); // ADDI x1, x0, 5
        load_inst(4,  32'h00a00113); // ADDI x2, x0, 10
        
        // 机器码 02208063 -> BEQ x1, x2, 32 (5 != 10，不跳。预测跳转目标PC为 8+32 = 40)
        load_inst(8,  32'h02208063); 
        
        load_inst(12, 32'h06400193); // ADDI x3, x0, 100 (顺序执行的正确指令)
        
        // 【关键保护】加一个原地踏步的死循环，防止流水线往下走到 PC=40
        load_inst(16, 32'h0000006f); // JAL x0, 0 
        
        load_inst(40, 32'h3e700213); // ADDI x4, x0, 999 (【毒药指令】在这里！)
        
        // 检查：x3必须等于100，x4必须等于0
        run_and_check(3, 32'd100, 4, 32'd0);

        // -------------------------------------------------------
        // 场景 2: 分支命中 (Branch Taken 预测成功测试)
        // -------------------------------------------------------
        // [Always Taken 架构下]：ID 阶段预测跳转，直接跳到 PC=20。
        // 紧跟在后面的 PC=12 会在 ID 阶段被当场 Flush！不会等到 EX 阶段。
        setup_test("Branch Taken (预测成功 Flush 验证)");
        load_inst(0,  32'h00500093); // ADDI x1, x0, 5
        load_inst(4,  32'h00108863); // BEQ  x1, x1, 16  (5 == 5，必定跳到 PC=20)
        load_inst(8,  32'h06400193); // ADDI x3, x0, 100 (ID阶段预测跳走，此指令会被Flush！)
        load_inst(12, 32'h0c800193); // ADDI x3, x0, 200 (根本取不到)
        load_inst(16, 32'h00000013); // NOP
        load_inst(20, 32'h03200193); // ADDI x3, x0, 50  (正确目标地址指令)
        // 检查：如果 Flush 失败，x3 会被错误的指令写成 100。
        run_and_check(3, 32'd50, 0, 0);

        // -------------------------------------------------------
        // 场景 3: 无条件跳转 JAL (0 惩罚测试)
        // -------------------------------------------------------
        setup_test("JAL 无条件跳转 (预测成功)");
        load_inst(0,  32'h014002ef); // JAL x5, 20       (预测跳到 PC=20, x5 记为 4)
        load_inst(4,  32'h06400313); // ADDI x6, x0, 100 (应被预测跳转的 Flush 机制杀掉)
        load_inst(8,  32'h0c800313); // ADDI x6, x0, 200 
        load_inst(12, 32'h00000013); // NOP
        load_inst(16, 32'h00000013); // NOP
        load_inst(20, 32'h03200313); // ADDI x6, x0, 50  (正确目标地址指令)
        run_and_check(5, 32'd4, 6, 32'd50);

        // -------------------------------------------------------
        // 场景 4: 寄存器跳转 JALR (EX 阶段纠正测试)
        // -------------------------------------------------------
        // JALR 不在 ID 阶段预测，因此它会顺序取指令，直到 EX 阶段算出目标再纠正。
        setup_test("JALR 寄存器跳转 (结合数据前推与纠正)");
        load_inst(0,  32'h01400093); // ADDI x1, x0, 20
        load_inst(4,  32'h000082e7); // JALR x5, x1, 0   (跳转到 x1+0=20, x5 记为 8)
        load_inst(8,  32'h06400313); // ADDI x6, x0, 100 (应在 EX 阶段被 pc_mis 杀掉！)
        load_inst(12, 32'h0c800313); // ADDI x6, x0, 200 (应在 EX 阶段被 pc_mis 杀掉！)
        load_inst(16, 32'h00000013); // NOP
        load_inst(20, 32'h03200313); // ADDI x6, x0, 50  (正确目标地址指令)
        run_and_check(5, 32'd8, 6, 32'd50);

        $display("========================================");
        $display("               测试全部结束               ");
        $display("========================================");
        $finish;
    end

    // 生成波形
    initial begin
        $dumpfile("tb_control.vcd");
        $dumpvars(0, tb_control.dut.u_pc_reg);
    end

endmodule