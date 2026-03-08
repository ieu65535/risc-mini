`include "../include/config.vh"
`include "../include/instructions.vh"

module alu(
    input wire [31:0] a,          // 操作数A
    input wire [31:0] b,          // 操作数B
    input wire [2:0] alu_ctrl,    // ALU控制信号
    input wire funct7_bit5,       // funct7[5]用于区分ADD/SUB
    output reg [31:0] result,     // 运算结果
    output wire zero,             // 零标志位
    output wire lt,               // 小于标志位（有符号）
    output wire ltu               // 小于标志位（无符号）
);
    
    // 完全保持原始ALU逻辑
    always @(*) begin
        result = 0;
        
        case (alu_ctrl)
            `ADD: begin
                // ADD或SUB
                if (funct7_bit5) begin
                    result = a - b;  // SUB
                end else begin
                    result = a + b;  // ADD
                end
            end
            `SLL: begin
                result = a << b[4:0];
            end
            `SLT: begin
                result = ($signed(a) < $signed(b)) ? 1 : 0;
            end
            `SLTU: begin
                result = (a < b) ? 1 : 0;
            end
            `XOR: begin
                result = a ^ b;
            end
            `SR: begin
                if (funct7_bit5) begin
                    result = $signed(a) >>> b[4:0];  // SRA
                end else begin
                    result = a >> b[4:0];            // SRL
                end
            end
            `OR: begin
                result = a | b;
            end
            `AND: begin
                result = a & b;
            end
            default: begin
                result = 0;
            end
        endcase
    end
    
    // 标志位生成
    assign zero = (result == 0);
    assign lt = ($signed(a) < $signed(b));
    assign ltu = (a < b);
    
    // 调试信息
    `ifdef DEBUG
    always @(*) begin
        if (alu_ctrl != 0)
            $display("ALU: %h %s %h = %h", a, 
                    alu_ctrl_name(alu_ctrl, funct7_bit5), b, result);
    end
    
    function string alu_ctrl_name;
        input [2:0] ctrl;
        input funct7_bit5;
        case (ctrl)
            `ADD: return (funct7_bit5 ? "SUB" : "ADD");
            `SLL: return "SLL";
            `SLT: return "SLT";
            `SLTU: return "SLTU";
            `XOR: return "XOR";
            `SR: return (funct7_bit5 ? "SRA" : "SRL");
            `OR: return "OR";
            `AND: return "AND";
            default: return "UNKNOWN";
        endcase
    endfunction
    `endif

endmodule