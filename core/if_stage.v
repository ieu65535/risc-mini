`include "../include/config.vh"
`include "../include/instructions.vh"

module if_stage(
    input wire clk,
    input wire rst,
    
    // 控制信号
    input wire stall_if,        // IF阶段停顿
    input wire flush_if,        // IF阶段清空
    input wire [31:0] pc_target, // 跳转目标（来自EX阶段）
    
    // 存储器接口
    input wire [31:0] inst_from_mem, // 来自存储器的指令
    output wire [31:0] pc_to_mem,    // 输出到存储器的PC
    
    // 流水线输出
    output wire [31:0] if_pc,        // 当前PC
    output wire [31:0] if_pc_plus4,  // PC+4
    output wire [31:0] if_inst       // 取到的指令
);
    
    // PC寄存器实例
    pc_reg u_pc_reg(
        .clk(clk),
        .rst(rst),
        .stall(stall_if),
        .flush(flush_if),
        .pc_next(pc_target),
        .pc(pc_to_mem),
        .pc_plus4(if_pc_plus4)
    );
    
    assign if_pc = pc_to_mem;
    
    // 指令寄存器（流水线寄存器位置，但当前直接传递）
    reg [31:0] if_inst_reg;
    
    always @(posedge clk) begin
        if (rst) begin
            if_inst_reg <= 32'b0;
        end else if (!stall_if) begin
            if_inst_reg <= inst_from_mem;
        end
    end
    
    assign if_inst = if_inst_reg;
    
    // 调试信息
    `ifdef DEBUG
    always @(posedge clk) begin
        if (!rst && !stall_if && if_inst != 0)
            $display("IF: PC=%h, INST=%h", if_pc, if_inst);
    end
    `endif

endmodule