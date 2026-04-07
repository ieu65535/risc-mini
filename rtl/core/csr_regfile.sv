`include "../config.vh"
`include "instructions.vh"

module csr_regfile (
    input  logic        clk,
    input  logic        rst,

    output logic [31:0] mepc_out,          // for PC update during MRET
    
    // CSR read/write interface
    input  logic [11:0] csr_raddr,
    input  logic [11:0] csr_waddr,  // 新增：时序逻辑写地址 (给 WB)
    input  logic [31:0] csr_wdata,         // datain
    input  logic [ 2:0] csr_op,            // reserved for compatibility, not used here
    input  logic        csr_we,
    output logic [31:0] csr_rdata,         // dataout
    output logic        csr_illegal,

    // interrupt control interface
    input  logic        ext_irq,           // external interrupt request

    input  logic        mret,              // MRET
    input  logic        exception,
    input  logic [31:0] exception_pc,      // PC during exception/interrupt
    input  logic [ 3:0] exception_code,
    output logic        interrupt_taken,   // interrupt accepted
    output logic [31:0] interrupt_vector
);

    logic [31:0] mstatus;  // machine status
    logic [31:0] mie;      // machine interrupt enable
    logic [31:0] mip;      // machine interrupt pending
    logic [31:0] mtvec;    // machine trap-vector base-address
    logic [31:0] mepc;     // machine exception program counter
    logic [31:0] mcause;   // machine trap cause

    // status bits
    wire mstatus_mie  = mstatus[3];   // global interrupt enable
    wire mstatus_mpie = mstatus[7];   // previous global interrupt enable

    // local read-implemented flag
    logic csr_implemented;

    always_comb begin
        csr_rdata       = 32'h0;
        csr_implemented = 1'b1;

        case (csr_raddr)
            `CSR_MSTATUS: csr_rdata = mstatus;
            `CSR_MIE:     csr_rdata = mie;
            `CSR_MIP:     csr_rdata = mip;
            `CSR_MTVEC:   csr_rdata = mtvec;
            `CSR_MEPC:    csr_rdata = mepc;
            `CSR_MCAUSE:  csr_rdata = mcause;
            default: begin
                csr_rdata       = 32'h0;
                csr_implemented = 1'b0;
            end
        endcase
    end

    always_comb begin
        csr_illegal = 1'b0;

        // current version: only implemented CSR address check
        if (!csr_implemented) begin
            csr_illegal = 1'b1;
        end

    end

    wire m_interrupt_enabled;
    assign m_interrupt_enabled = mstatus_mie && ((mie & mip) != 32'h0);
    assign interrupt_taken     = m_interrupt_enabled && !exception;

    assign interrupt_vector = mtvec;

    always_ff @(posedge clk) begin
        if (rst) begin
            mstatus <= 32'h0;
            mie     <= 32'h0;
            mip     <= 32'h0;
            mtvec   <= 32'h0000_0200;
            mepc    <= 32'h0;
            mcause  <= 32'h0;
        end
        else begin
            // hardware sets external interrupt pending bit
            if (ext_irq) begin
                mip[11] <= 1'b1;   // MEIP
            end

            if (exception) begin
                mepc            <= exception_pc;
                mcause          <= {1'b0, 27'b0, exception_code};
                mstatus[7]      <= mstatus[3];   // MPIE <= MIE
                mstatus[3]      <= 1'b0;         // MIE  <= 0
                mstatus[12:11]  <= 2'b11;        // MPP  <= M (machine mode)
            end

            else if (interrupt_taken) begin
                mepc            <= exception_pc;
                mcause          <= {1'b1, 27'b0, 4'b1011};
                mstatus[7]      <= mstatus[3];   // MPIE <= MIE
                mstatus[3]      <= 1'b0;         // MIE  <= 0
                mstatus[12:11]  <= 2'b11;        // MPP  <= M
            end

            else if (mret) begin
                mstatus[3]      <= mstatus[7];   // MIE <= MPIE
                mstatus[7]      <= 1'b1;         // MPIE <= 1
                mstatus[12:11]  <= 2'b00;        // MPP <= 0
            end

            // normal CSR write
            else begin
                //if (csr_we && !csr_illegal) begin
                if (csr_we) begin 
                    case (csr_waddr)
                        `CSR_MSTATUS: mstatus <= csr_wdata;
                        `CSR_MIE:     mie     <= csr_wdata;

                        // align trap base to 4-byte boundary
                        `CSR_MTVEC:   mtvec   <= {csr_wdata[31:2], 2'b00};

                        // for RV32I without C extension, 4-byte alignment is recommended
                        `CSR_MEPC:    mepc    <= {csr_wdata[31:2], 2'b00};

                        `CSR_MCAUSE:  mcause  <= csr_wdata;
                        `CSR_MIP:     mip     <= csr_wdata;
                        default: ;
                    endcase
                end
            end


            if (interrupt_taken) begin
                mip[11] <= 1'b0;
            end
        end
    end

    assign mepc_out = mepc;

endmodule
