`include "../include/config.vh"

module rom (
    input wire clk,
    input wire rst,
    
    // 指令接口
    input wire [31:0] inst_addr,  // 指令地址
    output reg [31:0] inst_data,  // 指令数据
    
    // 控制接口
    input wire inst_re,           // 指令读使能
    output wire inst_ready,       // 指令就绪
    
    // 配置接口
    input wire [31:0] base_addr,  // ROM基地址
    input wire [31:0] size,       // ROM大小
    
    // 调试接口
    output wire [31:0] debug_last_addr
);
    
    // ROM存储阵列
    parameter ROM_DEPTH = 4096;  // 4K字 = 16KB
    parameter ADDR_WIDTH = 12;   // 2^12 = 4096
    
    reg [31:0] rom_mem [0:ROM_DEPTH-1];
    reg [31:0] inst_data_reg;
    reg [31:0] last_addr_reg;
    reg ready_reg;
    
    // 地址计算
    wire [ADDR_WIDTH-1:0] rom_addr;
    wire addr_valid;
    
    assign rom_addr = inst_addr[ADDR_WIDTH+1:2];  // 字地址
    assign addr_valid = (inst_addr >= base_addr) && 
                       (inst_addr < (base_addr + (size << 2)));
    
    // 同步读
    always @(posedge clk) begin
        if (rst) begin
            inst_data <= 32'b0;
            last_addr_reg <= 32'b0;
            ready_reg <= 1'b0;
        end else if (inst_re && addr_valid) begin
            inst_data <= rom_mem[rom_addr];
            last_addr_reg <= inst_addr;
            ready_reg <= 1'b1;
        end else begin
            ready_reg <= 1'b0;
        end
    end
    
    //assign inst_data = inst_data_reg;
    assign inst_ready = ready_reg;
    assign debug_last_addr = last_addr_reg;
    
    // 初始化
    initial begin
        // 从文件加载ROM内容
        `ifdef SIMULATION
            $readmemh("program.mem", rom_mem);
        `else
            $readmemh("../firmware/program.mem", rom_mem);
        `endif
    end
    
    // 调试信息
    `ifdef DEBUG
    always @(posedge clk) begin
        if (inst_re && addr_valid) begin
            $display("ROM: Read addr=%h, data=%h", inst_addr, rom_mem[rom_addr]);
        end
    end
    `endif
    
    // 安全检查
    always @(*) begin
        if (inst_re && !addr_valid) begin
            $display("ROM Warning: Invalid address %h", inst_addr);
        end
    end

endmodule