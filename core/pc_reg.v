`include "../include/config.vh"

module pc_reg(
    input wire clk,
    input wire rst,
    
    // 控制信号
    input wire stall,          // 停顿信号
    input wire flush,          // 清空信号
    input wire [31:0] pc_next, // 下一个PC值
    
    // 输出
    output reg [31:0] pc,      // 当前PC
    output wire [31:0] pc_plus4 // PC+4
);
    
    // PC+4计算
    assign pc_plus4 = pc + 4;
    
    // PC寄存器更新
    always @(posedge clk) begin
        if (rst) begin
            pc <= `PC_RESET;// 复位时PC初始化（置0）
        end else if (flush) begin
            pc <= pc_next;      // 分支跳转
        end else if (!stall) begin
            pc <= pc_plus4;     // 顺序执行
        end
        // stall时PC保持不变
    end
    
    // 调试信息
    `ifdef DEBUG
    always @(posedge clk) begin
        if (!rst && !stall) 
            $display("PC: %h -> %h", pc, (flush ? pc_next : pc_plus4));
    end
    `endif

endmodule