`include "../include/config.vh"
`include "../include/instructions.vh"

module mem_control(
    input wire clk,
    input wire rst,
    
    // 控制信号
    input wire mem_read,       // 存储器读
    input wire mem_write,      // 存储器写
    input wire is_load,        // 加载指令
    input wire is_store,       // 存储指令
    input wire [2:0] funct3,   // 访存类型
    
    // 数据输入
    input wire [31:0] mem_addr,    // 存储器地址
    input wire [31:0] mem_data_in, // 写入数据
    
    // 总线接口
    output reg [31:0] mem_addr_out,  // 输出地址
    output reg [31:0] mem_data_out,  // 输出数据
    output reg [3:0] mem_we,         // 写使能
    output reg mem_re,               // 读使能
    
    // 对齐异常
    output reg align_error
);
    
    // 完全保持原始存储控制逻辑
    always @(*) begin
        // 默认值
        mem_addr_out = mem_addr;
        mem_data_out = mem_data_in;
        mem_we = 4'b0000;
        mem_re = 1'b0;
        align_error = 1'b0;
        
        if (mem_read && is_load) begin
            mem_re = 1'b1;
            
            // 加载指令不需要字节使能，由总线处理
        end
        else if (mem_write && is_store) begin
            mem_re = 1'b0;
            
            // 存储指令的字节使能（完全保持原始逻辑）
            case (funct3)
                `SB: begin
                    case (mem_addr[1:0])
                        2'b00: mem_we = 4'b0001;
                        2'b01: mem_we = 4'b0010;
                        2'b10: mem_we = 4'b0100;
                        2'b11: mem_we = 4'b1000;
                    endcase
                end
                `SH: begin
                    case (mem_addr[1:0])
                        2'b00: mem_we = 4'b0011;
                        2'b10: mem_we = 4'b1100;
                        default: align_error = 1'b1;
                    endcase
                end
                `SW: begin
                    mem_we = 4'b1111;
                end
            endcase
        end
    end
    
    // 调试信息
    `ifdef DEBUG
    always @(*) begin
        if (mem_read)
            $display("MEM: Read from %h", mem_addr);
        if (mem_write && !align_error)
            $display("MEM: Write %h to %h (we=%b)", 
                    mem_data_in, mem_addr, mem_we);
        if (align_error)
            $display("MEM: Alignment error at %h", mem_addr);
    end
    `endif

endmodule