`include "../include/config.vh"
`include "../include/instructions.vh"

module regfile(
    input wire clk,
    input wire rst,
    
    // 读端口（EX阶段使用）
    input wire [4:0] raddr1,
    input wire [4:0] raddr2,
    output reg [31:0] rdata1,
    output reg [31:0] rdata2,
    
    // 写端口（MEM阶段使用）
    input wire [4:0] waddr,
    input wire [31:0] wdata,
    input wire we
);
    
    // 寄存器阵列
    reg [31:0] registers [0:`REG_NUM-1];
    
    // 读端口1（组合逻辑）
    always @(*) begin
        if (raddr1 == 5'b0) begin
            rdata1 = 0;  // x0寄存器始终为0
        end else begin
            rdata1 = registers[raddr1];
        end
    end
    
    // 读端口2（组合逻辑）
    always @(*) begin
        if (raddr2 == 5'b0) begin
            rdata2 = 0;  // x0寄存器始终为0
        end else begin
            rdata2 = registers[raddr2];
        end
    end
    
    // 写端口（时序逻辑）
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            // 复位时清零所有寄存器
            for (i = 0; i < `REG_NUM; i = i + 1) begin
                registers[i] <= 0;
            end
        end else if (we && waddr != 0) begin
            // 写入寄存器（x0寄存器只读）
            registers[waddr] <= wdata;
            
            // 调试信息
            `ifdef DEBUG
            $display("RF: Write x%0d = %h", waddr, wdata);
            `endif
        end
    end
    
    // 调试：读取时显示
    `ifdef DEBUG
    always @(*) begin
        if (raddr1 != 0) 
            $display("RF: Read x%0d = %h", raddr1, rdata1);
        if (raddr2 != 0)
            $display("RF: Read x%0d = %h", raddr2, rdata2);
    end
    `endif

endmodule