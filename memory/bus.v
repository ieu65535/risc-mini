`include "../include/config.vh"

module bus (
    input wire clk,
    input wire rst,
    
    // CPU接口
    input wire [31:0] inst_addr,  // 指令地址
    input wire inst_re,           // 指令读使能
    output wire [31:0] inst_data, // 指令数据
    output wire inst_ready,       // 指令就绪
    
    input wire [31:0] data_addr,  // 数据地址
    input wire [31:0] data_in,    // 写入数据
    input wire [3:0] data_we,     // 字节写使能
    input wire data_re,           // 数据读使能
    output wire [31:0] data_out,  // 读取数据
    output wire data_ready,       // 数据就绪
    output wire data_error,       // 数据错误
    
    // 存储器接口
    output wire [31:0] rom_addr,
    output wire rom_re,
    input wire [31:0] rom_data,
    input wire rom_ready,
    
    output wire [31:0] ram_addr,
    output wire [31:0] ram_data_in,
    output wire [3:0] ram_we,
    output wire ram_re,
    input wire [31:0] ram_data_out,
    input wire ram_ready,
    input wire ram_align_error,
    
    // 外设接口
    output wire [31:0] io_addr,
    output wire [31:0] io_data_in,
    output wire io_we,
    output wire io_re,
    input wire [31:0] io_data_out,
    input wire io_ready,
    
    // 调试接口
    output wire [1:0] debug_access_type,  // 0:无, 1:ROM, 2:RAM, 3:IO
    output wire debug_access_pending
);
    
    // 地址解码
    wire [3:0] inst_space = inst_addr[31:28];
    wire [3:0] data_space = data_addr[31:28];
    
    // ROM访问
    assign rom_addr = inst_addr;
    assign rom_re = inst_re && (inst_space == 4'h0);
    
    // 数据访问解码
    wire ram_access = (data_space == 4'h2) && (data_re || (|data_we));
    wire io_access = (data_space == 4'h4) && (data_re || (|data_we));
    
    // RAM接口
    assign ram_addr = data_addr;
    assign ram_data_in = data_in;
    assign ram_we = ram_access ? data_we : 4'b0000;
    assign ram_re = ram_access ? data_re : 1'b0;
    
    // IO接口
    assign io_addr = data_addr;
    assign io_data_in = data_in;
    assign io_we = io_access ? (|data_we) : 1'b0;
    assign io_re = io_access ? data_re : 1'b0;
    
    // 输出数据多路选择
    reg [31:0] data_out_reg;
    reg data_ready_reg;
    reg data_error_reg;
    reg [1:0] access_type_reg;
    
    always @(*) begin
        // 默认值
        data_out_reg = 32'b0;
        data_ready_reg = 1'b0;
        data_error_reg = 1'b0;
        access_type_reg = 2'b0;
        
        if (ram_access && ram_ready) begin
            data_out_reg = ram_data_out;
            data_ready_reg = 1'b1;
            data_error_reg = ram_align_error;
            access_type_reg = 2'b01;  // RAM访问
        end
        else if (io_access && io_ready) begin
            data_out_reg = io_data_out;
            data_ready_reg = 1'b1;
            access_type_reg = 2'b10;  // IO访问
        end
        else if (!ram_access && !io_access && (data_re || (|data_we))) begin
            // 未映射地址访问
            data_error_reg = 1'b1;
            access_type_reg = 2'b11;  // 错误访问
            
            `ifdef DEBUG
            if (data_re) 
                $display("Bus Error: Read from unmapped address %h", data_addr);
            if (|data_we) 
                $display("Bus Error: Write to unmapped address %h", data_addr);
            `endif
        end
    end
    
    // 指令数据直通
    assign inst_data = rom_data;
    assign inst_ready = rom_ready;
    
    // 数据输出
    assign data_out = data_out_reg;
    assign data_ready = data_ready_reg;
    assign data_error = data_error_reg;
    
    // 调试信号
    assign debug_access_type = access_type_reg;
    assign debug_access_pending = (inst_re || data_re || (|data_we));
    
    // 仲裁状态机（未来可扩展支持多主设备）
    reg [1:0] arb_state;
    localparam [1:0] IDLE = 2'b00,
                     ROM_ACCESS = 2'b01,
                     RAM_ACCESS = 2'b10,
                     IO_ACCESS = 2'b11;
    
    always @(posedge clk) begin
        if (rst) begin
            arb_state <= IDLE;
        end else begin
            case (arb_state)
                IDLE: begin
                    if (inst_re && rom_re) arb_state <= ROM_ACCESS;
                    else if (ram_access) arb_state <= RAM_ACCESS;
                    else if (io_access) arb_state <= IO_ACCESS;
                end
                ROM_ACCESS: begin
                    if (!inst_re || !rom_re) arb_state <= IDLE;
                end
                RAM_ACCESS: begin
                    if (!ram_access) arb_state <= IDLE;
                end
                IO_ACCESS: begin
                    if (!io_access) arb_state <= IDLE;
                end
            endcase
        end
    end
    
    // 调试信息
    `ifdef DEBUG
    always @(posedge clk) begin
        if (inst_re && rom_re) begin
            $display("Bus: IFetch addr=%h", inst_addr);
        end
        if (ram_access) begin
            if (data_re) 
                $display("Bus: RAM Read addr=%h", data_addr);
            if (|data_we) 
                $display("Bus: RAM Write addr=%h, data=%h, we=%b", 
                        data_addr, data_in, data_we);
        end
        if (io_access) begin
            if (data_re) 
                $display("Bus: IO Read addr=%h", data_addr);
            if (|data_we) 
                $display("Bus: IO Write addr=%h, data=%h", data_addr, data_in);
        end
    end
    `endif

endmodule