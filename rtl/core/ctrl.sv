`include "micro.vh"
module ctrl(
    input  logic [ 4:0] rs1_addr,
    input  logic [ 4:0] rs2_addr,
    input  logic [ 4:0] rd_addr_ex,
    input  logic [ 1:0] wb_sel_ex,
    input  logic [ 1:0] pc_sel_ex,
    input  logic        valid_ex,
    input  logic        alu_cond,
    input  logic [31:0] alu_dout,
    input  logic [31:0] pc_ex,
    input  logic [31:0] inst_ex,
    input  logic [31:0] inst_misaligned_target_ex,
    output logic        stall,
    output logic        pc_mis,
    output logic [31:0] target_pc,

    input  logic        is_ecall_ex,
    input  logic        is_ebreak_ex,
    input  logic        is_illegal_ex,
    input  logic        inst_addr_misaligned_ex,
    input  logic        load_addr_misaligned_ex,
    input  logic        store_addr_misaligned_ex,
    input  logic        is_mret_ex,
    input  logic [31:0] csr_mtvec,       // 从 CSR 读出的异常入口
    input  logic [31:0] csr_mepc,        // 从 CSR 读出的返回地址
    input  logic        csr_mstatus_mie, // 全局中断使能
    input  logic        csr_mie_mtie,    // 机器定时器中断使能
    input  logic        csr_mip_mtip,    // 已锁存的机器定时器挂起位
    input  logic        timer_int,       // 同步的一拍定时器请求

    output logic        trap_valid,
    output logic        timer_irq_taken,
    output logic        mret_valid,
    output logic [31:0] trap_cause,
    output logic [31:0] trap_tval
);

assign stall = valid_ex && (wb_sel_ex == `WB_MEM) && (rd_addr_ex != 5'b0) &&
               ((rs1_addr == rd_addr_ex) || (rs2_addr == rd_addr_ex));

logic timer_irq_eligible;
assign timer_irq_eligible = valid_ex & (timer_int | csr_mip_mtip) &
                            csr_mstatus_mie & csr_mie_mtie;

logic illegal_trap;
logic ecall_trap;
logic ebreak_trap;
logic inst_misaligned_trap;
logic load_misaligned_trap;
logic store_misaligned_trap;
assign inst_misaligned_trap  = valid_ex & inst_addr_misaligned_ex;
assign illegal_trap = valid_ex & is_illegal_ex;
assign load_misaligned_trap  = valid_ex & load_addr_misaligned_ex;
assign store_misaligned_trap = valid_ex & store_addr_misaligned_ex;
assign ecall_trap             = valid_ex & is_ecall_ex;
assign ebreak_trap            = valid_ex & is_ebreak_ex;

logic sync_trap_valid;
assign sync_trap_valid = inst_misaligned_trap | illegal_trap |
                         load_misaligned_trap | store_misaligned_trap |
                         ecall_trap | ebreak_trap;

// 同步异常优先；只有 Timer 真正赢得仲裁时才确认并清除 pending。
assign timer_irq_taken = timer_irq_eligible & ~sync_trap_valid;
assign trap_valid = sync_trap_valid | timer_irq_taken;
assign mret_valid = valid_ex & is_mret_ex;

//trap_cause
assign trap_cause = inst_misaligned_trap  ? 32'd0         :
                    illegal_trap          ? 32'd2         :
                    ebreak_trap           ? 32'd3         :
                    load_misaligned_trap  ? 32'd4         :
                    store_misaligned_trap ? 32'd6         :
                    ecall_trap            ? 32'd11        :
                    timer_irq_taken       ? 32'h8000_0007 : 32'd0;

// 与 mcause 使用同一优先级：故障目标/编码/访存地址；EBREAK、ECALL、Timer 为 0。
assign trap_tval = inst_misaligned_trap  ? inst_misaligned_target_ex :
                   illegal_trap          ? inst_ex                    :
                   load_misaligned_trap  ? alu_dout                   :
                   store_misaligned_trap ? alu_dout                   : 32'd0;

logic branch_mis;
always_comb begin
    branch_mis = 0;
    if (valid_ex) begin
        case (pc_sel_ex)
            `PC_N: branch_mis = 0;
            `PC_J: branch_mis = 0;
            `PC_B: branch_mis = !alu_cond;
            `PC_JR: branch_mis = 1;
            default: branch_mis = 0;
        endcase
    end
end
assign pc_mis = branch_mis | trap_valid | mret_valid;


wire [31:0] jr_addr = {alu_dout[31:1], 1'b0};
wire [31:0] mtvec_base = {csr_mtvec[31:2], 2'b00};
wire [31:0] vector_offset = {trap_cause[29:0], 2'b00};
wire        vectored_interrupt = (csr_mtvec[1:0] == 2'b01) && trap_cause[31];
wire [31:0] trap_target = vectored_interrupt ? mtvec_base + vector_offset : mtvec_base;
always_comb begin
    target_pc = 0;
    
    // 【核心逻辑】优先级划分：异常/中断 最高 -> MRET 其次 -> 普通跳转
    if (trap_valid) begin
        // Vectored 只对异步中断按 cause 编号偏移；同步异常仍进入 BASE。
        target_pc = trap_target;
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
