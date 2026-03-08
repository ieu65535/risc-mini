`include "../include/config.vh"
`include "../include/instructions.vh"

module alu_control(
    input wire [6:0] opcode,
    input wire [2:0] funct3,
    input wire [6:0] funct7,
    
    // 输出控制信号
    output reg [2:0] alu_ctrl,
    output reg funct7_bit5,
    output reg alu_src1_sel,    // 0: rs1, 1: PC
    output reg alu_src2_sel,    // 0: rs2, 1: imm
    output reg [1:0] alu_op_sel  // ALU操作类型选择
);
    
    // 完全保持原始控制逻辑
    always @(*) begin
        // 默认值
        alu_ctrl = `ADD;
        funct7_bit5 = 1'b0;
        alu_src1_sel = 1'b0;  // 默认使用rs1
        alu_src2_sel = 1'b0;  // 默认使用rs2
        alu_op_sel = 2'b00;   // 默认加法
        
        case (opcode)
            `TYPE_R: begin
                alu_ctrl = funct3;
                funct7_bit5 = funct7[5];
                alu_src2_sel = 1'b0;  // 使用rs2
            end
            
            `TYPE_I: begin
                alu_ctrl = funct3;
                funct7_bit5 = funct7[5];
                alu_src2_sel = 1'b1;  // 使用立即数
            end
            
            `TYPE_B: begin
                alu_ctrl = funct3;
                alu_src2_sel = 1'b0;  // 使用rs2
                alu_op_sel = 2'b01;   // 比较操作
            end
            
            `TYPE_L, `TYPE_S: begin
                alu_ctrl = `ADD;      // 地址计算
                alu_src2_sel = 1'b1;  // 使用立即数
            end
            
            `JALR: begin
                alu_ctrl = `ADD;      // 地址计算
                alu_src2_sel = 1'b1;  // 使用立即数
            end
            
            `AUIPC: begin
                alu_ctrl = `ADD;
                alu_src1_sel = 1'b1;  // 使用PC
                alu_src2_sel = 1'b1;  // 使用立即数
            end
            
            default: begin
                // 其他指令保持默认
            end
        endcase
    end

endmodule