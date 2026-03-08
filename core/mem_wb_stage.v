`include "../include/config.vh"
`include "../include/instructions.vh"

module mem_wb_stage(
    input wire clk,
    input wire rst,
    
    // 来自EX阶段的输入
    input wire [31:0] mem_alu_result,  // ALU结果
    input wire [31:0] mem_rs2_data,    // rs2数据
    input wire [31:0] mem_pc,          // PC
    input wire [31:0] mem_pc_plus4,    // PC+4
    input wire [4:0] mem_rd_addr,      // 目标寄存器地址
    input wire mem_reg_write,          // 寄存器写使能
    input wire mem_mem_read,           // 存储器读
    input wire mem_mem_write,          // 存储器写
    input wire [1:0] mem_wb_sel,       // 写回选择
    input wire [2:0] mem_funct3,       // 访存类型
    input wire mem_is_load,            // 加载指令
    input wire mem_is_store,           // 存储指令
    
    // 存储器数据
    input wire [31:0] mem_data_from_bus, // 从总线读取的数据
    
    // 存储器接口
    output wire [31:0] mem_addr_to_bus,  // 输出到总线的地址
    output wire [31:0] mem_data_to_bus,  // 输出到总线的数据
    output wire [3:0] mem_we_to_bus,     // 写使能
    output wire mem_re_to_bus,           // 读使能
    
    // 写回接口
    output reg [31:0] wb_data,           // 写回数据
    output reg [4:0] wb_rd_addr,         // 写回目标地址
    output reg wb_reg_write,             // 写回使能
    
    // 异常输出
    output mem_align_error           // 对齐错误
);
    
    // 存储器控制器实例
    mem_control u_mem_control(
        .clk(clk),
        .rst(rst),
        .mem_read(mem_mem_read),
        .mem_write(mem_mem_write),
        .is_load(mem_is_load),
        .is_store(mem_is_store),
        .funct3(mem_funct3),
        .mem_addr(mem_alu_result),      // ALU结果是存储器地址
        .mem_data_in(mem_rs2_data),     // 存储数据来自rs2
        .mem_addr_out(mem_addr_to_bus),
        .mem_data_out(mem_data_to_bus),
        .mem_we(mem_we_to_bus),
        .mem_re(mem_re_to_bus),
        .align_error(mem_align_error)
    );
    
    // 写回数据选择（完全保持原始逻辑）
    reg [31:0] wb_data_internal;
    always @(*) begin
        case (mem_wb_sel)
            2'b00: wb_data_internal = mem_alu_result;  // ALU结果
            2'b01: wb_data_internal = mem_pc_plus4;    // PC+4
            2'b10: begin
                // LUI指令的立即数
                wb_data_internal = {mem_pc[31:12], 12'b0};
            end
            2'b11: begin
                // 存储器数据，需要根据加载类型处理
                if (mem_is_load) begin
                    case (mem_funct3)
                        `LB: begin
                            case (mem_alu_result[1:0])
                                2'b00: wb_data_internal = $signed(mem_data_from_bus[7:0]);
                                2'b01: wb_data_internal = $signed(mem_data_from_bus[15:8]);
                                2'b10: wb_data_internal = $signed(mem_data_from_bus[23:16]);
                                2'b11: wb_data_internal = $signed(mem_data_from_bus[31:24]);
                            endcase
                        end
                        `LH: begin
                            case (mem_alu_result[1:0])
                                2'b00: wb_data_internal = $signed(mem_data_from_bus[15:0]);
                                2'b10: wb_data_internal = $signed(mem_data_from_bus[31:16]);
                                default: wb_data_internal = 0;  // 对齐错误
                            endcase
                        end
                        `LW: begin
                            wb_data_internal = mem_data_from_bus;
                        end
                        `LBU: begin
                            case (mem_alu_result[1:0])
                                2'b00: wb_data_internal = mem_data_from_bus[7:0];
                                2'b01: wb_data_internal = mem_data_from_bus[15:8];
                                2'b10: wb_data_internal = mem_data_from_bus[23:16];
                                2'b11: wb_data_internal = mem_data_from_bus[31:24];
                            endcase
                        end
                        `LHU: begin
                            case (mem_alu_result[1:0])
                                2'b00: wb_data_internal = mem_data_from_bus[15:0];
                                2'b10: wb_data_internal = mem_data_from_bus[31:16];
                                default: wb_data_internal = 0;  // 对齐错误
                            endcase
                        end
                        default: wb_data_internal = 0;
                    endcase
                end else begin
                    wb_data_internal = 0;
                end
            end
            default: wb_data_internal = 0;
        endcase
    end
    
    // 传递写回信号
    always @(posedge clk) begin
        if (rst) begin
            wb_data <= 0;
            wb_rd_addr <= 0;
            wb_reg_write <= 0;
        end else begin
            wb_data <= wb_data_internal;
            wb_rd_addr <= mem_rd_addr;
            wb_reg_write <= mem_reg_write;
            
            // 调试信息
            `ifdef DEBUG
            if (mem_reg_write && mem_rd_addr != 0) begin
                $display("MEM_WB: Write x%0d = %h (src=%b)", 
                        mem_rd_addr, wb_data_internal, mem_wb_sel);
            end
            `endif
        end
    end

endmodule