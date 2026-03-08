`include "../include/config.vh"
`include "../include/instructions.vh"

module ex_stage(
    input wire clk,
    input wire rst,
    
    // 来自IF阶段的输入
    input wire [31:0] ex_pc,        // 当前指令的PC
    input wire [31:0] ex_pc_plus4,  // PC+4
    input wire [31:0] ex_inst,      // 指令
    
    // 寄存器文件接口
    output wire [4:0] rf_raddr1,    // 寄存器读地址1
    output wire [4:0] rf_raddr2,    // 寄存器读地址2
    input wire [31:0] rf_rdata1,    // 寄存器读数据1
    input wire [31:0] rf_rdata2,    // 寄存器读数据2
    
    // 立即数
    output wire [31:0] ex_imm_I,
    output wire [31:0] ex_imm_S,
    output wire [31:0] ex_imm_B,
    output wire [31:0] ex_imm_U,
    output wire [31:0] ex_imm_J,
    
    // ALU接口
    output wire [31:0] alu_a,
    output wire [31:0] alu_b,
    input wire [31:0] alu_result,
    input wire alu_zero,
    input wire alu_lt,
    input wire alu_ltu,
    
    // 控制信号
    input wire ex_reg_write,
    input wire ex_mem_read,
    input wire ex_mem_write,
    input wire [1:0] ex_wb_sel,
    input wire ex_branch,
    input wire ex_jump,
    input wire ex_is_load,
    input wire ex_is_store,
    input wire [2:0] ex_alu_ctrl,
    input wire ex_funct7_bit5,
    input wire ex_alu_src1_sel,
    input wire ex_alu_src2_sel,
    
    // 输出到MEM阶段
    output reg [31:0] ex_alu_out,     // ALU计算结果
    output reg [31:0] ex_rs2_data,    // rs2数据（用于存储）
    output reg [31:0] ex_pc_out,      // PC传递
    output reg [31:0] ex_pc_plus4_out,// PC+4传递
    output reg [4:0] ex_rd_addr,      // 目标寄存器地址
    output reg ex_reg_write_out,      // 寄存器写使能传递
    output reg ex_mem_read_out,       // 存储器读传递
    output reg ex_mem_write_out,      // 存储器写传递
    output reg [1:0] ex_wb_sel_out,   // 写回选择传递
    output reg ex_is_load_out,        // 加载指令标志传递
    output reg ex_is_store_out,       // 存储指令标志传递
    
    // 分支/跳转输出
    output reg branch_taken,          // 分支发生
    output reg [31:0] branch_target,  // 分支目标
    output reg jump_taken,            // 跳转发生
    output reg [31:0] jump_target     // 跳转目标
);
    
    // 模块实例
    // 立即数生成器
    imm_gen u_imm_gen(
        .inst(ex_inst),
        .imm_I(ex_imm_I),
        .imm_S(ex_imm_S),
        .imm_B(ex_imm_B),
        .imm_U(ex_imm_U),
        .imm_J(ex_imm_J)
    );
    
    // 寄存器地址提取
    assign rf_raddr1 = ex_inst[19:15];
    assign rf_raddr2 = ex_inst[24:20];
    
    // ALU操作数选择
    wire [31:0] alu_src1 = ex_alu_src1_sel ? ex_pc : rf_rdata1;
    wire [31:0] alu_src2 = ex_alu_src2_sel ? ex_imm_I : rf_rdata2;
    
    assign alu_a = alu_src1;
    assign alu_b = alu_src2;
    
    // 分支判断（完全保持原始逻辑）
    always @(*) begin
        branch_taken = 1'b0;
        branch_target = 32'b0;
        
        if (ex_branch) begin
            case (ex_inst[14:12])  // funct3
                `BEQ:  branch_taken = (rf_rdata1 == rf_rdata2);
                `BNE:  branch_taken = (rf_rdata1 != rf_rdata2);
                `BLT:  branch_taken = alu_lt;
                `BGE:  branch_taken = ~alu_lt;
                `BLTU: branch_taken = alu_ltu;
                `BGEU: branch_taken = ~alu_ltu;
            endcase
            
            if (branch_taken) begin
                branch_target = ex_pc + ex_imm_B;
            end
        end
    end
    
    // 跳转判断
    always @(*) begin
        jump_taken = 1'b0;
        jump_target = 32'b0;
        
        if (ex_jump) begin
            jump_taken = 1'b1;
            if (ex_inst[6:0] == `JALR) begin
                // JALR: (rs1 + imm_I) & ~1
                jump_target = (rf_rdata1 + ex_imm_I) & ~1;
            end else begin
                // JAL: pc + imm_J
                jump_target = ex_pc + ex_imm_J;
            end
        end
    end
    
    // 传递信号到MEM阶段
    always @(posedge clk) begin
        if (rst) begin
            ex_alu_out <= 0;
            ex_rs2_data <= 0;
            ex_pc_out <= 0;
            ex_pc_plus4_out <= 0;
            ex_rd_addr <= 0;
            ex_reg_write_out <= 0;
            ex_mem_read_out <= 0;
            ex_mem_write_out <= 0;
            ex_wb_sel_out <= 0;
            ex_is_load_out <= 0;
            ex_is_store_out <= 0;
        end else begin
            ex_alu_out <= alu_result;
            ex_rs2_data <= rf_rdata2;
            ex_pc_out <= ex_pc;
            ex_pc_plus4_out <= ex_pc_plus4;
            ex_rd_addr <= ex_inst[11:7];
            ex_reg_write_out <= ex_reg_write;
            ex_mem_read_out <= ex_mem_read;
            ex_mem_write_out <= ex_mem_write;
            ex_wb_sel_out <= ex_wb_sel;
            ex_is_load_out <= ex_is_load;
            ex_is_store_out <= ex_is_store;
        end
    end
    
    // 调试信息
    `ifdef DEBUG
    always @(posedge clk) begin
        if (!rst) begin
            if (branch_taken)
                $display("EX: Branch taken to %h", branch_target);
            if (jump_taken)
                $display("EX: Jump to %h", jump_target);
            if (ex_inst != 0)
                $display("EX: PC=%h, ALU=%h", ex_pc, alu_result);
        end
    end
    `endif

endmodule