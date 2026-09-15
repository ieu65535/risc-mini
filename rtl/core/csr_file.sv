`include "instructions.vh"
`include "micro.vh"

module csr_file(
    input  logic        clk,
    input  logic        rst,

    // 译码与执行阶段的读写端口 (对应 CSRRW, CSRRS, CSRRC 等指令)
    input  logic        csr_we,
    input  logic [11:0] csr_waddr,
    input  logic [31:0] csr_wdata,
    
    input  logic [11:0] csr_raddr,
    output logic [31:0] csr_rdata,

    // 硬件异常与中断控制端口 (由 ctrl 模块控制)
    input  logic        trap_valid,  // 发生异常或中断 (如 ECALL 或 Timer 中断)
    input  logic        mret_valid,  // 执行 MRET 指令返回
    input  logic [31:0] trap_pc,     // 发生异常时的 PC (存入 mepc)
    input  logic [31:0] trap_cause,  // 异常或中断的原因 (存入 mcause)

    // 提供给控制模块 (ctrl) 和 PC 取指模块的只读信号
    output logic [31:0] csr_mepc_out,
    output logic [31:0] csr_mtvec_out,
    output logic        csr_mstatus_mie, // 全局中断使能位 (mstatus 的第3位)
    output logic        csr_mie_mtie     // 机器定时器中断使能位 (mie 的第7位)
);

    // 定义内部实际存在的寄存器
    logic [31:0] mstatus;
    logic [31:0] mtvec;
    logic [31:0] mepc;
    logic [31:0] mcause;
    logic [31:0] mscratch;
    logic [31:0] mie;

    // 输出直通信号
    assign csr_mepc_out    = mepc;
    assign csr_mtvec_out   = mtvec;
    assign csr_mstatus_mie = mstatus[3]; // MIE (Machine Interrupt Enable)
    assign csr_mie_mtie    = mie[7];     // MTIE (Machine Timer Interrupt Enable)

    // 读 CSR 逻辑 (组合逻辑)
    always_comb begin
        case(csr_raddr)
            `CSR_MSTATUS:  csr_rdata = mstatus;
            `CSR_MTVEC:    csr_rdata = mtvec;
            `CSR_MEPC:     csr_rdata = mepc;
            `CSR_MCAUSE:   csr_rdata = mcause;
            `CSR_MSCRATCH: csr_rdata = mscratch;
            `CSR_MIE:      csr_rdata = mie;
            `CSR_MHARTID:  csr_rdata = 32'h0; // 单核系统直接返回 0
            default:       csr_rdata = 32'h0;
        endcase
    end

    // 写 CSR 以及硬件更新逻辑 (时序逻辑)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mstatus  <= 32'b0;
            mtvec    <= 32'b0;
            mepc     <= 32'b0;
            mcause   <= 32'b0;
            mscratch <= 32'b0;
            mie      <= 32'b0;
        end else begin
            // 1. 优先处理硬件触发的异常更新 (进入中断)
            if (trap_valid) begin
                mepc        <= trap_pc;
                mcause      <= trap_cause;
                // 进入中断时，保存当前的 MIE (位3) 到 MPIE (位7)，并关闭 MIE
                mstatus[7]  <= mstatus[3]; 
                mstatus[3]  <= 1'b0;
            end 
            // 2. 硬件触发的中断返回 (MRET)
            else if (mret_valid) begin
                // 从中断返回时，将 MPIE (位7) 恢复到 MIE (位3)，并置 MPIE 为 1
                mstatus[3]  <= mstatus[7];
                mstatus[7]  <= 1'b1;
            end 
            // 3. 处理普通指令的写操作 (CSRRW, CSRRS, CSRRC)
            else if (csr_we) begin
                case(csr_waddr)
                    `CSR_MSTATUS:  mstatus  <= csr_wdata;
                    `CSR_MTVEC:    mtvec    <= csr_wdata;
                    `CSR_MEPC:     mepc     <= csr_wdata;
                    `CSR_MCAUSE:   mcause   <= csr_wdata;
                    `CSR_MSCRATCH: mscratch <= csr_wdata;
                    `CSR_MIE:      mie      <= csr_wdata;
                endcase
            end
        end
    end

endmodule
