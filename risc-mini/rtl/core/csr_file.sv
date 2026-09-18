`include "instructions.vh"
`include "micro.vh"

module csr_file(
    input  logic        clk,
    input  logic        rst,
    input  logic        csr_we,
    input  logic [11:0] csr_waddr,
    input  logic [31:0] csr_wdata,
    input  logic [11:0] csr_raddr,
    output logic [31:0] csr_rdata,
    input  logic        trap_valid,
    input  logic        mret_valid,
    input  logic [31:0] trap_pc,
    input  logic [31:0] trap_cause,
    input  logic [31:0] trap_tval,
    input  logic        timer_int,
    input  logic        timer_irq_taken,
    input  logic        retire_valid,
    input  logic        stall_valid,
    output logic [31:0] csr_mepc_out,
    output logic [31:0] csr_mtvec_out,
    output logic        csr_mstatus_mie,
    output logic        csr_mie_mtie,
    output logic        csr_mip_mtip
);

logic [31:0] mstatus;
logic [31:0] mtvec;
logic [31:0] mepc;
logic [31:0] mcause;
logic [31:0] mtval;
logic [31:0] mscratch;
logic [31:0] mie;
logic        mtip_pending;
logic [63:0] mcycle;
logic [63:0] minstret;
logic [63:0] stall_cycles;
logic [63:0] mcycle_next;
logic [63:0] minstret_next;

always @(*) begin
    mcycle_next = mcycle + 64'd1;
    minstret_next = minstret + {63'd0, retire_valid};
    if (csr_we) begin
        case (csr_waddr)
            `CSR_MCYCLE:    mcycle_next = {mcycle[63:32], csr_wdata};
            `CSR_MCYCLEH:   mcycle_next[63:32] = csr_wdata;
            `CSR_MINSTRET:  minstret_next = {minstret[63:32], csr_wdata};
            `CSR_MINSTRETH: minstret_next[63:32] = csr_wdata;
            default: begin end
        endcase
    end
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        mcycle       <= 64'd0;
        minstret     <= 64'd0;
        stall_cycles <= 64'd0;
    end else begin
        mcycle   <= mcycle_next;
        minstret <= minstret_next;
        if (stall_valid)
            stall_cycles <= stall_cycles + 64'd1;
    end
end

assign csr_mepc_out    = mepc;
assign csr_mtvec_out   = mtvec;
assign csr_mstatus_mie = mstatus[3];
assign csr_mie_mtie    = mie[7];
assign csr_mip_mtip    = mtip_pending;

always @(*) begin
    case(csr_raddr)
        `CSR_MSTATUS:  csr_rdata = mstatus;
        `CSR_MTVEC:    csr_rdata = mtvec;
        `CSR_MEPC:     csr_rdata = mepc;
        `CSR_MCAUSE:   csr_rdata = mcause;
        `CSR_MTVAL:    csr_rdata = mtval;
        `CSR_MSCRATCH: csr_rdata = mscratch;
        `CSR_MIE:      csr_rdata = mie;
        `CSR_MIP:      csr_rdata = {24'b0, mtip_pending, 7'b0};
        `CSR_MHARTID:  csr_rdata = 32'h0;
        `CSR_CYCLE, `CSR_MCYCLE:       csr_rdata = mcycle[31:0];
        `CSR_CYCLEH, `CSR_MCYCLEH:     csr_rdata = mcycle[63:32];
        `CSR_INSTRET, `CSR_MINSTRET:   csr_rdata = minstret[31:0];
        `CSR_INSTRETH, `CSR_MINSTRETH: csr_rdata = minstret[63:32];
        `CSR_STALL_CYCLES:             csr_rdata = stall_cycles[31:0];
        `CSR_STALL_CYCLESH:            csr_rdata = stall_cycles[63:32];
        default:                       csr_rdata = 32'h0;
    endcase
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        mstatus  <= 32'h0000_1800;
        mtvec    <= 32'b0;
        mepc     <= 32'b0;
        mcause   <= 32'b0;
        mtval    <= 32'b0;
        mscratch <= 32'b0;
        mie      <= 32'b0;
    end else begin
        if (trap_valid) begin
            mepc       <= {trap_pc[31:2], 2'b00};
            mcause     <= trap_cause;
            mtval      <= trap_tval;
            mstatus[7] <= mstatus[3];
            mstatus[3] <= 1'b0;
        end else if (mret_valid) begin
            mstatus[3] <= mstatus[7];
            mstatus[7] <= 1'b1;
        end else if (csr_we) begin
            case(csr_waddr)
                `CSR_MSTATUS:  mstatus  <= (csr_wdata & 32'h0000_0088) |
                                            32'h0000_1800;
                `CSR_MTVEC:    mtvec    <= {csr_wdata[31:2],
                                           (csr_wdata[1:0] == 2'b01) ? 2'b01 : 2'b00};
                `CSR_MEPC:     mepc     <= {csr_wdata[31:2], 2'b00};
                `CSR_MCAUSE:   mcause   <= csr_wdata;
                `CSR_MTVAL:    mtval    <= csr_wdata;
                `CSR_MSCRATCH: mscratch <= csr_wdata;
                `CSR_MIE:      mie      <= {24'b0, csr_wdata[7], 7'b0};
                default: begin end
            endcase
        end
    end
end

always_ff @(posedge clk or posedge rst) begin
    if (rst)
        mtip_pending <= 1'b0;
    else if (timer_irq_taken)
        mtip_pending <= 1'b0;
    else if (timer_int)
        mtip_pending <= 1'b1;
end

endmodule
