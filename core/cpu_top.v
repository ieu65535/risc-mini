`include "../include/config.vh"
`include "../include/instructions.vh"

module cpu_top(
    input wire clk,
    input wire rst,
    
    // 指令接口
    output wire [31:0] inst_addr,  // 指令地址
    output wire inst_re,           // 指令读使能
    input wire [31:0] inst_data,   // 指令数据
    input wire inst_ready,         // 指令就绪
    
    // 数据接口
    output wire [31:0] data_addr,  // 数据地址
    output wire [31:0] data_in,    // 写入数据
    output wire [3:0] data_we,     // 字节写使能
    output wire data_re,           // 数据读使能
    input wire [31:0] data_out,    // 读取数据
    input wire data_ready,         // 数据就绪
    input wire data_error,         // 数据错误
    
    // 调试接口
    output wire [31:0] debug_pc,
    output wire [31:0] debug_inst
);
    
    // ==================== IF阶段信号 ====================
    wire [31:0] if_pc;
    wire [31:0] if_pc_plus4;
    wire [31:0] if_inst;
    
    // 控制信号
    wire stall_if = 1'b0;  // 暂时无停顿
    wire flush_if = 1'b0;  // 暂时无清空
    wire [31:0] pc_target; // 跳转目标
    
    // ==================== EX阶段信号 ====================
    wire [31:0] ex_pc;
    wire [31:0] ex_pc_plus4;
    wire [31:0] ex_inst;
    
    // 寄存器文件信号
    wire [4:0] rf_raddr1;
    wire [4:0] rf_raddr2;
    wire [31:0] rf_rdata1;
    wire [31:0] rf_rdata2;
    
    // 立即数信号
    wire [31:0] ex_imm_I, ex_imm_S, ex_imm_B, ex_imm_U, ex_imm_J;
    
    // ALU信号
    wire [31:0] alu_a, alu_b;
    wire [31:0] alu_result;
    wire alu_zero, alu_lt, alu_ltu;
    
    // 控制信号
    wire ex_reg_write, ex_mem_read, ex_mem_write;
    wire [1:0] ex_wb_sel;
    wire ex_branch, ex_jump, ex_is_load, ex_is_store;
    wire [2:0] ex_alu_ctrl;
    wire ex_funct7_bit5;
    wire ex_alu_src1_sel, ex_alu_src2_sel;
    
    // EX阶段输出
    wire [31:0] ex_alu_out;
    wire [31:0] ex_rs2_data;
    wire [4:0] ex_rd_addr;
    wire ex_reg_write_out, ex_mem_read_out, ex_mem_write_out;
    wire [1:0] ex_wb_sel_out;
    wire ex_is_load_out, ex_is_store_out;
    
    // 分支/跳转
    wire branch_taken;
    wire [31:0] branch_target_wire;
    wire jump_taken;
    wire [31:0] jump_target_wire;
    
    // ==================== MEM阶段信号 ====================
    wire [31:0] mem_alu_result;
    wire [31:0] mem_rs2_data;
    wire [4:0] mem_rd_addr;
    wire mem_reg_write, mem_mem_read, mem_mem_write;
    wire [1:0] mem_wb_sel;
    wire [2:0] mem_funct3;
    wire mem_is_load, mem_is_store;
    
    // 存储器接口
    wire [31:0] mem_addr_to_bus;
    wire [31:0] mem_data_to_bus;
    wire [3:0] mem_we_to_bus;
    wire mem_re_to_bus;
    
    // 写回信号
    wire [31:0] wb_data;
    wire [4:0] wb_rd_addr;
    wire wb_reg_write;
    
    // 异常
    wire mem_align_error;
    
    // ==================== 模块实例化 ====================
    
    // F阶段
    if_stage u_if_stage(
        .clk(clk),
        .rst(rst),
        .stall_if(stall_if),
        .flush_if(flush_if),
        .pc_target(pc_target),
        .inst_from_mem(inst_data),//
        .pc_to_mem(inst_addr),//
        .if_pc(if_pc),
        .if_pc_plus4(if_pc_plus4),
        .if_inst(if_inst)
    );
    
    // 译码器
    decoder u_decoder(
        .inst(if_inst),
        .opcode(), 
        .funct3(mem_funct3),  // 传递给MEM阶段
        .funct7(),
        .rs1_addr(rf_raddr1),
        .rs2_addr(rf_raddr2),
        .rd_addr(),
        .reg_write(ex_reg_write),
        .mem_read(ex_mem_read),
        .mem_write(ex_mem_write),
        .wb_sel(ex_wb_sel),
        .branch(ex_branch),
        .jump(ex_jump),
        .is_load(ex_is_load),
        .is_store(ex_is_store)
    );
    
    // ALU控制器
    alu_control u_alu_control(
        .opcode(if_inst[6:0]),
        .funct3(if_inst[14:12]),
        .funct7(if_inst[31:25]),
        .alu_ctrl(ex_alu_ctrl),
        .funct7_bit5(ex_funct7_bit5),
        .alu_src1_sel(ex_alu_src1_sel),
        .alu_src2_sel(ex_alu_src2_sel),
        .alu_op_sel()
    );
    
    // 寄存器文件
    regfile u_regfile(
        .clk(clk),
        .rst(rst),
        .raddr1(rf_raddr1),
        .raddr2(rf_raddr2),
        .rdata1(rf_rdata1),
        .rdata2(rf_rdata2),
        .waddr(wb_rd_addr),
        .wdata(wb_data),
        .we(wb_reg_write)
    );
    
    // ALU
    alu u_alu(
        .a(alu_a),
        .b(alu_b),
        .alu_ctrl(ex_alu_ctrl),
        .funct7_bit5(ex_funct7_bit5),
        .result(alu_result),
        .zero(alu_zero),
        .lt(alu_lt),
        .ltu(alu_ltu)
    );
    
    // EX阶段控制器
    ex_stage u_ex_stage(
        .clk(clk),
        .rst(rst),
        .ex_pc(if_pc),
        .ex_pc_plus4(if_pc_plus4),
        .ex_inst(if_inst),
        .rf_raddr1(rf_raddr1),
        .rf_raddr2(rf_raddr2),
        .rf_rdata1(rf_rdata1),
        .rf_rdata2(rf_rdata2),
        .ex_imm_I(ex_imm_I),
        .ex_imm_S(ex_imm_S),
        .ex_imm_B(ex_imm_B),
        .ex_imm_U(ex_imm_U),
        .ex_imm_J(ex_imm_J),
        .alu_a(alu_a),
        .alu_b(alu_b),
        .alu_result(alu_result),
        .alu_zero(alu_zero),
        .alu_lt(alu_lt),
        .alu_ltu(alu_ltu),
        .ex_reg_write(ex_reg_write),
        .ex_mem_read(ex_mem_read),
        .ex_mem_write(ex_mem_write),
        .ex_wb_sel(ex_wb_sel),
        .ex_branch(ex_branch),
        .ex_jump(ex_jump),
        .ex_is_load(ex_is_load),
        .ex_is_store(ex_is_store),
        .ex_alu_ctrl(ex_alu_ctrl),
        .ex_funct7_bit5(ex_funct7_bit5),
        .ex_alu_src1_sel(ex_alu_src1_sel),
        .ex_alu_src2_sel(ex_alu_src2_sel),
        .ex_alu_out(ex_alu_out),
        .ex_rs2_data(ex_rs2_data),
        .ex_pc_out(),
        .ex_pc_plus4_out(),
        .ex_rd_addr(ex_rd_addr),
        .ex_reg_write_out(ex_reg_write_out),
        .ex_mem_read_out(ex_mem_read_out),
        .ex_mem_write_out(ex_mem_write_out),
        .ex_wb_sel_out(ex_wb_sel_out),
        .ex_is_load_out(ex_is_load_out),
        .ex_is_store_out(ex_is_store_out),
        .branch_taken(branch_taken),
        .branch_target(branch_target_wire),
        .jump_taken(jump_taken),
        .jump_target(jump_target_wire)
    );
    
    // MEM阶段控制器
    mem_wb_stage u_mem_wb_stage(
        .clk(clk),
        .rst(rst),
        .mem_alu_result(ex_alu_out),
        .mem_rs2_data(ex_rs2_data),
        .mem_pc(if_pc),
        .mem_pc_plus4(if_pc_plus4),
        .mem_rd_addr(ex_rd_addr),
        .mem_reg_write(ex_reg_write_out),
        .mem_mem_read(ex_mem_read_out),
        .mem_mem_write(ex_mem_write_out),
        .mem_wb_sel(ex_wb_sel_out),
        .mem_funct3(mem_funct3),
        .mem_is_load(ex_is_load_out),
        .mem_is_store(ex_is_store_out),
        .mem_data_from_bus(data_out),
        .mem_addr_to_bus(mem_addr_to_bus),
        .mem_data_to_bus(mem_data_to_bus),
        .mem_we_to_bus(mem_we_to_bus),
        .mem_re_to_bus(mem_re_to_bus),
        .wb_data(wb_data),
        .wb_rd_addr(wb_rd_addr),
        .wb_reg_write(wb_reg_write),
        .mem_align_error(mem_align_error)
    );
    
    // 跳转目标选择
    assign pc_target = jump_taken ? jump_target_wire : 
                      (branch_taken ? branch_target_wire : if_pc_plus4);
    
    // 存储器接口连接
    assign mem_addr = mem_addr_to_bus;
    assign mem_din = mem_data_to_bus;
    assign mem_we = mem_we_to_bus;
    assign mem_re = mem_re_to_bus;
    
    // 调试信号
    assign debug_pc = if_pc;
    assign debug_inst = if_inst;
    
    // 全局调试
    `ifdef DEBUG
    always @(posedge clk) begin
        if (!rst) begin
            $display("=== Cycle %0d ===", $time/10);
        end
    end
    `endif

endmodule