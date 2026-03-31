`include "micro.vh"

module pc_reg(
    input  logic        clk,
    input  logic        rst,
    input  logic        stall,
    
    input  logic        predict_jump,  
    input  logic [31:0] predict_addr, 

    input  logic        mispredict,    
    input  logic [31:0] recovery_addr, 

    input  logic [31:0] mem_inst,  
    output logic [31:0] id_inst,   

    output logic [31:0] inst_addr, 
    output logic [31:0] pc,

    //interrupt
    input  logic        interrupt,
    input  logic [31:0] interrupt_vector,

    input exception
);

logic [31:0] fetch_pc; 
logic [31:0] next_pc;

always_comb begin
    if (exception)
        next_pc = interrupt_vector;
        //暂时同样用中断向量
    if (interrupt)             // 中断
        next_pc = interrupt_vector;
    else if (mispredict) begin
        next_pc = recovery_addr;   // 预测失败，跳回正确的地址
    end
    else if (stall) begin
        next_pc = fetch_pc;       // 保持 PC 不变
    end
    else if (predict_jump) begin
        next_pc = predict_addr;   // 译码阶段预测跳转，更新 PC
    end
    else begin
        next_pc = fetch_pc + 4;   // 默认 PC+4
    end
end

assign inst_addr = next_pc;

always_ff @(posedge clk) begin
    if (rst) begin
        fetch_pc <= 32'hFFFFFFFC;
    end else begin
        fetch_pc <= next_pc;
    end
end

logic [31:0] id_pc;
always_ff @(posedge clk) begin
    if (rst) begin
        id_pc <= 32'h0;
    end else begin
        id_pc <= inst_addr; 
    end
end

assign pc = id_pc; 

logic flush_id;
assign flush_id = mispredict; 

assign id_inst = flush_id ? 32'h00000013 : mem_inst; // 冲刷为 NOP

endmodule