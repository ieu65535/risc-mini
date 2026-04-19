`include "micro.vh"
module pc_reg(
    input  logic        clk,
    input  logic        rst,
    input  logic        stall,
    
    input  logic [31:0] inst,
    input  logic        pc_mis,
    input  logic [31:0] target_pc,
    input  logic [ 1:0] pc_sel,

<<<<<<< HEAD
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
=======
    output logic [31:0] inst_addr,
    output logic [31:0] pc
>>>>>>> origin/ieu-dev
);

wire [31:0] imm_J = $signed({inst[31], inst[19:12], inst[20], inst[30:21], 1'b0});
wire [31:0] imm_B = $signed({inst[31], inst[7], inst[30:25], inst[11:8], 1'b0});

logic [31:0] pred_pc;

always_comb begin
    case (pc_sel)
        `PC_N: pred_pc = pc + 4;
        `PC_J: pred_pc = pc + imm_J;
        `PC_B: pred_pc = pc + imm_B;
        `PC_JR: pred_pc = pc + 4;
    endcase
end

logic [31:0] next_pc;
logic [31:0] id_inst_reg;

always_comb begin
<<<<<<< HEAD
    // if (exception)
    //     next_pc = interrupt_vector;
    //     //暂时同样用中断向量
    // else 
    // if (interrupt)             // 中断
    //     next_pc = interrupt_vector;
    // else 
    if (mispredict) begin
        next_pc = recovery_addr;   // 预测失败，跳回正确的地址
    end
    else if (stall) begin
        next_pc = fetch_pc;       // 保持 PC 不变
    end
    else if (predict_jump) begin
        next_pc = predict_addr;   // 译码阶段预测跳转，更新 PC
=======
    if (stall) begin
        next_pc = pc;
>>>>>>> origin/ieu-dev
    end
    else begin
        if (pc_mis)
            next_pc = target_pc;
        else
            next_pc = pred_pc;
    end
end

//assign inst_addr = next_pc;
assign inst_addr = fetch_pc;

always_ff @(posedge clk) begin
    if (rst) begin
        pc <= -4;
    end else begin
        pc <= next_pc;
    end
end

<<<<<<< HEAD
logic [31:0] id_pc;
always_ff @(posedge clk) begin
    if (rst) begin
        id_pc <= 32'h0;
    end else begin
        //id_pc <= inst_addr; 
        id_pc <= fetch_pc;
    end
    id_inst_reg <= mem_inst;
end

assign pc = id_pc; 

logic flush_id;
assign flush_id = mispredict | interrupt | exception;

assign id_inst = flush_id ? 32'h00000013 : mem_inst; // 冲刷为 NOP
//assign id_inst = flush_id ? 32'h00000013 : id_inst_reg; // 冲刷为 NOP


=======
>>>>>>> origin/ieu-dev
endmodule