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
    input  logic [31:0] csr_mtvec,
    input  logic [31:0] csr_mepc,
    input  logic        csr_mstatus_mie,
    input  logic        csr_mie_mtie,
    input  logic        csr_mip_mtip,
    input  logic        timer_int,
    input  logic        irq_blocked,
    output logic        trap_valid,
    output logic        timer_irq_taken,
    output logic        mret_valid,
    output logic [31:0] trap_cause,
    output logic [31:0] trap_tval
);

assign stall = valid_ex && (wb_sel_ex == `WB_MEM) && (rd_addr_ex != 5'b0) &&
               ((rs1_addr == rd_addr_ex) || (rs2_addr == rd_addr_ex));

logic timer_irq_eligible;
logic illegal_trap;
logic ecall_trap;
logic ebreak_trap;
logic inst_misaligned_trap;
logic load_misaligned_trap;
logic store_misaligned_trap;
logic sync_trap_valid;

assign timer_irq_eligible = valid_ex && (timer_int || csr_mip_mtip) &&
                            csr_mstatus_mie && csr_mie_mtie && !irq_blocked;
assign inst_misaligned_trap  = valid_ex && inst_addr_misaligned_ex;
assign illegal_trap          = valid_ex && is_illegal_ex;
assign load_misaligned_trap  = valid_ex && load_addr_misaligned_ex;
assign store_misaligned_trap = valid_ex && store_addr_misaligned_ex;
assign ecall_trap             = valid_ex && is_ecall_ex;
assign ebreak_trap            = valid_ex && is_ebreak_ex;
assign sync_trap_valid = inst_misaligned_trap || illegal_trap ||
                         load_misaligned_trap || store_misaligned_trap ||
                         ecall_trap || ebreak_trap;

assign timer_irq_taken = timer_irq_eligible && !sync_trap_valid;
assign trap_valid = sync_trap_valid || timer_irq_taken;
assign mret_valid = valid_ex && is_mret_ex;

assign trap_cause = inst_misaligned_trap  ? 32'd0         :
                    illegal_trap          ? 32'd2         :
                    ebreak_trap           ? 32'd3         :
                    load_misaligned_trap  ? 32'd4         :
                    store_misaligned_trap ? 32'd6         :
                    ecall_trap            ? 32'd11        :
                    timer_irq_taken       ? 32'h8000_0007 : 32'd0;

assign trap_tval = inst_misaligned_trap  ? inst_misaligned_target_ex :
                   illegal_trap          ? inst_ex                    :
                   load_misaligned_trap  ? alu_dout                   :
                   store_misaligned_trap ? alu_dout                   : 32'd0;

logic branch_mis;
always_comb begin
    branch_mis = 1'b0;
    if (valid_ex) begin
        case (pc_sel_ex)
            `PC_B:  branch_mis = !alu_cond;
            `PC_JR: branch_mis = 1'b1;
            default: branch_mis = 1'b0;
        endcase
    end
end
assign pc_mis = branch_mis || trap_valid || mret_valid;

wire [31:0] jr_addr = {alu_dout[31:1], 1'b0};
wire [31:0] mtvec_base = {csr_mtvec[31:2], 2'b00};
wire [31:0] vector_offset = {trap_cause[29:0], 2'b00};
wire        vectored_interrupt = (csr_mtvec[1:0] == 2'b01) && trap_cause[31];
wire [31:0] trap_target = vectored_interrupt ? mtvec_base + vector_offset : mtvec_base;

always_comb begin
    if (trap_valid)
        target_pc = trap_target;
    else if (mret_valid)
        target_pc = csr_mepc;
    else begin
        case (pc_sel_ex)
            `PC_B:  target_pc = pc_ex + 32'd4;
            `PC_JR: target_pc = jr_addr;
            default: target_pc = 32'b0;
        endcase
    end
end

endmodule
