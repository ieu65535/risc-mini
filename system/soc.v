`include "../include/config.vh"

module soc(
    input wire clk,
    input wire rst_n,
    
    // 外设接口
    //output wire uart_tx,
    //input wire uart_rx,
    
    // 调试接口
    output wire [31:0] debug_pc,
    output wire [31:0] debug_inst
);
    
    // 复位同步
    wire rst;
    reset_sync u_reset_sync(
        .clk(clk),
        .rst_n(rst_n),
        .rst(rst)
    );
    
    // ==================== CPU接口信号 ====================
    wire [31:0] inst_addr;
    wire inst_re;
    wire [31:0] inst_data;
    wire inst_ready;
    
    wire [31:0] data_addr;
    wire [31:0] data_in;
    wire [3:0] data_we;
    wire data_re;
    wire [31:0] data_out;
    wire data_ready;
    wire data_error;
    
    // ==================== 存储器接口信号 ====================
    wire [31:0] rom_addr_bus;
    wire rom_re_bus;
    wire [31:0] rom_data_bus;
    wire rom_ready_bus;
    
    wire [31:0] ram_addr_bus;
    wire [31:0] ram_data_in_bus;
    wire [3:0] ram_we_bus;
    wire ram_re_bus;
    wire [31:0] ram_data_out_bus;
    wire ram_ready_bus;
    wire ram_align_error_bus;
    
    // ==================== IO接口信号 ====================
    wire [31:0] io_addr_bus;
    wire [31:0] io_data_in_bus;
    wire io_we_bus;
    wire io_re_bus;
    wire [31:0] io_data_out_bus;
    wire io_ready_bus;
    
    // ==================== 调试信号 ====================
    wire [1:0] bus_access_type;
    wire bus_access_pending;
    
    // ==================== 模块实例化 ====================
    
    // CPU
    cpu_top u_cpu_top(
        .clk(clk),
        .rst(rst),
        .inst_addr(inst_addr),
        .inst_re(inst_re),
        .inst_data(inst_data),
        .inst_ready(inst_ready),
        .data_addr(data_addr),
        .data_in(data_in),
        .data_we(data_we),
        .data_re(data_re),
        .data_out(data_out),
        .data_ready(data_ready),
        .data_error(data_error),
        .debug_pc(debug_pc),
        .debug_inst(debug_inst)
    );
    
    // 总线
    bus u_bus(
        .clk(clk),
        .rst(rst),
        .inst_addr(inst_addr),
        .inst_re(inst_re),
        .inst_data(inst_data),
        .inst_ready(inst_ready),
        .data_addr(data_addr),
        .data_in(data_in),
        .data_we(data_we),
        .data_re(data_re),
        .data_out(data_out),
        .data_ready(data_ready),
        .data_error(data_error),
        .rom_addr(rom_addr_bus),
        .rom_re(rom_re_bus),
        .rom_data(rom_data_bus),
        .rom_ready(rom_ready_bus),
        .ram_addr(ram_addr_bus),
        .ram_data_in(ram_data_in_bus),
        .ram_we(ram_we_bus),
        .ram_re(ram_re_bus),
        .ram_data_out(ram_data_out_bus),
        .ram_ready(ram_ready_bus),
        .ram_align_error(ram_align_error_bus),
        .io_addr(io_addr_bus),
        .io_data_in(io_data_in_bus),
        .io_we(io_we_bus),
        .io_re(io_re_bus),
        .io_data_out(io_data_out_bus),
        .io_ready(io_ready_bus),
        .debug_access_type(bus_access_type),
        .debug_access_pending(bus_access_pending)
    );
    
    // ROM（指令存储器）
    rom u_rom(
        .clk(clk),
        .rst(rst),
        .inst_addr(rom_addr_bus),
        .inst_data(rom_data_bus),
        .inst_re(rom_re_bus),
        .inst_ready(rom_ready_bus),
        .base_addr(`FLASH_BASE),
        .size(32'h0000_1000),  // 4KB
        .debug_last_addr()
    );
    
    // RAM（数据存储器）
    ram u_ram(
        .clk(clk),
        .rst(rst),
        .data_addr(ram_addr_bus),
        .data_in(ram_data_in_bus),
        .data_out(ram_data_out_bus),
        .data_we(ram_we_bus),
        .data_re(ram_re_bus),
        .data_ready(ram_ready_bus),
        .align_error(ram_align_error_bus),
        .base_addr(`RAM_BASE),
        .size(32'h0000_1000),  // 4KB
        .debug_last_addr(),
        .debug_last_write()
    );
    
    // IO控制器
    io u_io(
        .clk(clk),
        .rst(rst),
        .addr(io_addr_bus),
        .din(io_data_in_bus),
        .wr(io_we_bus),
        .dout(io_data_out_bus)
        //.uart_tx(uart_tx),
        //.uart_rx(uart_rx)
    );
    
    // 为io模块添加就绪信号（组合逻辑，无延迟）
    assign io_ready_bus = 1'b1;
    
    // ==================== 调试和监控 ====================
    `ifdef DEBUG
    reg [31:0] cycle_count;
    
    always @(posedge clk) begin
        if (rst) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            
            if (cycle_count == 0) begin
                $display("========== SoC Starting ==========");
            end
            
            // 每1000周期报告一次
            if (cycle_count % 1000 == 0) begin
                $display("Cycle: %d", cycle_count);
            end
            
            // 总线访问监控
            if (bus_access_pending) begin
                case (bus_access_type)
                    2'b01: $display("Cycle %d: RAM access", cycle_count);
                    2'b10: $display("Cycle %d: IO access", cycle_count);
                    2'b11: $display("Cycle %d: Bus error!", cycle_count);
                endcase
            end
        end
    end
    `endif
    
    // ==================== 波形调试 ====================
    `ifdef SIMULATION
    initial begin
        $dumpfile("soc.vcd");
        $dumpvars(0, soc);
        
        // 监控关键信号
        $dumpvars(1, u_cpu_top);
        $dumpvars(1, u_bus);
        $dumpvars(1, u_rom);
        $dumpvars(1, u_ram);
    end
    `endif

endmodule