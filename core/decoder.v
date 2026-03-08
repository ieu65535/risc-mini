`include "../include/config.vh"
`include "../include/instructions.vh"

module decoder(
    input wire [31:0] inst,
    
    // 指令字段输出
    output wire [6:0] opcode,
    output wire [2:0] funct3,
    output wire [6:0] funct7,
    output wire [4:0] rs1_addr,
    output wire [4:0] rs2_addr,
    output wire [4:0] rd_addr,
    
    // 控制信号输出
    output reg reg_write,      // 寄存器写使能
    output reg mem_read,       // 存储器读
    output reg mem_write,      // 存储器写
    output reg [1:0] wb_sel,   // 写回选择
    output reg branch,         // 分支指令
    output reg jump,           // 跳转指令
    output reg is_load,        // 加载指令
    output reg is_store        // 存储指令
);
    
    // 指令字段提取
    assign opcode = inst[6:0];
    assign funct3 = inst[14:12];
    assign funct7 = inst[31:25];
    assign rs1_addr = inst[19:15];
    assign rs2_addr = inst[24:20];
    assign rd_addr = inst[11:7];
    
    // 控制信号生成（保持原始逻辑）
    always @(*) begin
        // 默认值
        reg_write = 1'b0;
        mem_read = 1'b0;
        mem_write = 1'b0;
        wb_sel = 2'b00;  // 00: ALU结果, 01: PC+4, 10: 立即数, 11: 存储器数据
        branch = 1'b0;
        jump = 1'b0;
        is_load = 1'b0;
        is_store = 1'b0;
        
        case (opcode)
            `TYPE_R: begin
                reg_write = 1'b1;
                wb_sel = 2'b00;  // ALU结果
            end
            
            `TYPE_I: begin
                reg_write = 1'b1;
                wb_sel = 2'b00;  // ALU结果
            end
            
            `TYPE_L: begin
                reg_write = 1'b1;
                mem_read = 1'b1;
                is_load = 1'b1;
                wb_sel = 2'b11;  // 存储器数据
            end
            
            `TYPE_S: begin
                mem_write = 1'b1;
                is_store = 1'b1;
            end
            
            `TYPE_B: begin
                branch = 1'b1;
            end
            
            `JAL: begin
                reg_write = 1'b1;
                jump = 1'b1;
                wb_sel = 2'b01;  // PC+4
            end
            
            `JALR: begin
                reg_write = 1'b1;
                jump = 1'b1;
                wb_sel = 2'b01;  // PC+4
            end
            
            `LUI: begin
                reg_write = 1'b1;
                wb_sel = 2'b10;  // 立即数
            end
            
            `AUIPC: begin
                reg_write = 1'b1;
                wb_sel = 2'b00;  // ALU结果
            end
        endcase
    end
    
    // 调试信息
    `ifdef DEBUG
    function string opcode_name;
        input [6:0] opc;
        case (opc)
            `TYPE_R: return "R-type";
            `TYPE_I: return "I-type";
            `TYPE_L: return "Load";
            `TYPE_S: return "Store";
            `TYPE_B: return "Branch";
            `JAL:    return "JAL";
            `JALR:   return "JALR";
            `LUI:    return "LUI";
            `AUIPC:  return "AUIPC";
            default: return "Unknown";
        endcase
    endfunction
    
    always @(*) begin
        if (opcode != 0)
            $display("DECODE: %s, rs1=%0d, rs2=%0d, rd=%0d", 
                    opcode_name(opcode), rs1_addr, rs2_addr, rd_addr);
    end
    `endif

endmodule