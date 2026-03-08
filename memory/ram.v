`include "../include/config.vh"

module ram (
    input wire clk,
    input wire rst,
    
    // 数据接口
    input wire [31:0] data_addr,  // 数据地址
    input wire [31:0] data_in,    // 写入数据
    output reg [31:0] data_out,   // 读取数据
    
    // 控制接口
    input wire [3:0] data_we,     // 字节写使能
    input wire data_re,           // 读使能
    output wire data_ready,       // 数据就绪
    output wire align_error,      // 对齐错误
    
    // 配置接口
    input wire [31:0] base_addr,  // RAM基地址
    input wire [31:0] size,       // RAM大小
    
    // 调试接口
    output wire [31:0] debug_last_addr,
    output wire debug_last_write
);
    
    // RAM存储阵列
    parameter RAM_DEPTH = 4096;   // 4K字 = 16KB
    parameter ADDR_WIDTH = 12;    // 2^12 = 4096
    
    reg [31:0] ram_mem [0:RAM_DEPTH-1];
    reg [31:0] data_out_reg;
    reg [31:0] last_addr_reg;
    reg ready_reg;
    reg last_write_reg;
    reg align_error_reg;
    
    // 地址计算
    wire [ADDR_WIDTH-1:0] ram_addr;
    wire addr_valid;
    
    assign ram_addr = data_addr[ADDR_WIDTH+1:2];  // 字地址
    assign addr_valid = (data_addr >= base_addr) && 
                       (data_addr < (base_addr + (size << 2)));
    
    // 对齐检查
    wire addr_aligned_word = (data_addr[1:0] == 2'b00);
    wire addr_aligned_half = (data_addr[0] == 1'b0);
    
    // 对齐错误检测
    always @(*) begin
        align_error_reg = 1'b0;
        
        if (addr_valid) begin
            // 字访问必须4字节对齐
            if (data_we == 4'b1111 && !addr_aligned_word) begin
                align_error_reg = 1'b1;
            end
            // 半字访问必须2字节对齐
            else if ((data_we == 4'b0011 || data_we == 4'b1100) && !addr_aligned_half) begin
                align_error_reg = 1'b1;
            end
        end
    end
    
    // 写操作
    always @(posedge clk) begin
        if (rst) begin
            // 复位不清空RAM，但可选择性初始化
            `ifdef INIT_RAM
            integer i;
            for (i = 0; i < RAM_DEPTH; i = i + 1) begin
                ram_mem[i] <= 32'b0;
            end
            `endif
        end else if (addr_valid && (|data_we) && !align_error_reg) begin
            // 字节使能写入
            if (data_we[0]) ram_mem[ram_addr][7:0]   <= data_in[7:0];
            if (data_we[1]) ram_mem[ram_addr][15:8]  <= data_in[15:8];
            if (data_we[2]) ram_mem[ram_addr][23:16] <= data_in[23:16];
            if (data_we[3]) ram_mem[ram_addr][31:24] <= data_in[31:24];
            
            last_write_reg <= 1'b1;
            last_addr_reg <= data_addr;
            
            `ifdef DEBUG
            $display("RAM: Write addr=%h, data=%h, we=%b", 
                    data_addr, data_in, data_we);
            `endif
        end
    end
    
    // 读操作
    always @(posedge clk) begin
        if (rst) begin
            data_out <= 32'b0;
            ready_reg <= 1'b0;
        end else if (data_re && addr_valid && !align_error_reg) begin
            data_out <= ram_mem[ram_addr];
            ready_reg <= 1'b1;
            last_write_reg <= 1'b0;
            last_addr_reg <= data_addr;
            
            `ifdef DEBUG
            $display("RAM: Read addr=%h, data=%h", data_addr, ram_mem[ram_addr]);
            `endif
        end else begin
            ready_reg <= 1'b0;
        end
    end
    
    //assign data_out = data_out_reg;
    assign data_ready = ready_reg;
    assign align_error = align_error_reg;
    assign debug_last_addr = last_addr_reg;
    assign debug_last_write = last_write_reg;
    
    // 调试：内存导出功能
    `ifdef DUMP_RAM
    initial begin
        // 在仿真结束时导出RAM内容
        $dumpvars(0, ram_mem);
    end
    
    final begin
        $writememh("ram_dump.mem", ram_mem);
    end
    `endif

endmodule