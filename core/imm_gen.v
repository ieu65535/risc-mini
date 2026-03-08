`include "../include/config.vh"
`include "../include/instructions.vh"

module imm_gen(
    input wire [31:0] inst,        // 输入指令
    output reg [31:0] imm_I,       // I型立即数
    output reg [31:0] imm_S,       // S型立即数
    output reg [31:0] imm_B,       // B型立即数
    output reg [31:0] imm_U,       // U型立即数
    output reg [31:0] imm_J        // J型立即数
);
    
    always @(*) begin
        // 完全保持原始立即数生成逻辑
        // I型立即数
        imm_I = {{20{inst[31]}}, inst[31:20]};
        
        // S型立即数
        imm_S = {{20{inst[31]}}, inst[31:25], inst[11:7]};
        
        // B型立即数
        imm_B = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
        
        // U型立即数
        imm_U = {inst[31:12], 12'b0};
        
        // J型立即数
        imm_J = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
    end

endmodule