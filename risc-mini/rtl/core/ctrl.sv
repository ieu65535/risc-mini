`include "micro.vh"
module ctrl(
    input  logic [ 4:0] rs1_addr,
    input  logic [ 4:0] rs2_addr,
    input  logic [ 4:0] rd_addr_ex,
    input  logic [ 1:0] wb_sel_ex,
    input  logic [ 1:0] pc_sel_ex,
    input  logic        alu_cond,
    input  logic [31:0] alu_dout,
    input  logic [31:0] pc_ex,
    output logic        stall,
    output logic        pc_mis,
    output logic [31:0] target_pc,

    input  logic        is_ecall_ex,
    input  logic        is_mret_ex,
    input  logic [31:0] csr_mtvec,       // 从 CSR 读出的异常入口
    input  logic [31:0] csr_mepc,        // 从 CSR 读出的返回地址
    input  logic        csr_mstatus_mie, // 全局中断使能
    input  logic        timer_int,       // 外部定时器中断 (预留给 FreeRTOS)

    output logic        trap_valid,
    output logic        mret_valid,
    output logic [31:0] trap_cause
);

assign stall = (wb_sel_ex == `WB_MEM) && (rd_addr_ex != 5'b0) && ((rs1_addr == rd_addr_ex) || (rs2_addr == rd_addr_ex));

//ecall
assign trap_valid = is_ecall_ex | (timer_int & csr_mstatus_mie);
assign mret_valid = is_mret_ex;

//trap_cause
assign trap_cause = (timer_int & csr_mstatus_mie) ? 32'h8000_0007 : 
                    is_ecall_ex                   ? 32'd11        : 32'd0;

logic branch_mis;
always_comb begin
    branch_mis = 0;
    case (pc_sel_ex)
        `PC_N: branch_mis = 0;
        `PC_J: branch_mis = 0;
        `PC_B: branch_mis = !alu_cond;
        `PC_JR: branch_mis = 1;
        default: branch_mis = 0;
    endcase
end
assign pc_mis = branch_mis | trap_valid | mret_valid;


wire [31:0] jr_addr = {alu_dout[31:1], 1'b0};
always_comb begin
    target_pc = 0;
    
    // 【核心逻辑】优先级划分：异常/中断 最高 -> MRET 其次 -> 普通跳转
    if (trap_valid) begin
        target_pc = csr_mtvec;  // 跳入中断服务函数
    end else if (mret_valid) begin
        target_pc = csr_mepc;   // 恢复到被打断的地方
    end else begin
        case (pc_sel_ex)
            `PC_N: target_pc = 0;
            `PC_J: target_pc = 0;
            `PC_B: target_pc = pc_ex + 4;
            `PC_JR: target_pc = jr_addr;
            default: target_pc = 0;
        endcase
    end
end

endmodule