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
    input  logic [31:0] trap_tval,   // 导致异常的地址或指令编码
    input  logic        timer_int,   // 与 clk 同步的一拍 Timer 请求
    input  logic        timer_irq_taken,
    input  logic        retire_valid, // WB 中真正退休的一条指令
    input  logic        stall_valid,  // PC 确实因暂停而保持的周期

    // 提供给控制模块 (ctrl) 和 PC 取指模块的只读信号
    output logic [31:0] csr_mepc_out,
    output logic [31:0] csr_mtvec_out,
    output logic        csr_mstatus_mie, // 全局中断使能位 (mstatus 的第3位)
    output logic        csr_mie_mtie,    // 机器定时器中断使能位 (mie 的第7位)
    output logic        csr_mip_mtip     // 机器定时器中断挂起位 (mip.MTIP)
);

    // 定义内部实际存在的寄存器
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

    // 机器态可分别改写高/低半字；写低半字时丢弃旧值的当拍进位。
    always @* begin
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
            mcycle <= 64'd0;
            minstret <= 64'd0;
            stall_cycles <= 64'd0;
        end else begin
            mcycle <= mcycle_next;
            minstret <= minstret_next;
            if (stall_valid)
                stall_cycles <= stall_cycles + 64'd1;
        end
    end

    // 输出直通信号
    assign csr_mepc_out    = mepc;
    assign csr_mtvec_out   = mtvec;
    assign csr_mstatus_mie = mstatus[3]; // MIE (Machine Interrupt Enable)
    assign csr_mie_mtie    = mie[7];     // MTIE (Machine Timer Interrupt Enable)
    assign csr_mip_mtip    = mtip_pending;

    // 读 CSR 逻辑 (组合逻辑)
    always @* begin
        case(csr_raddr)
            `CSR_MSTATUS:  csr_rdata = mstatus;
            `CSR_MTVEC:    csr_rdata = mtvec;
            `CSR_MEPC:     csr_rdata = mepc;
            `CSR_MCAUSE:   csr_rdata = mcause;
            `CSR_MTVAL:    csr_rdata = mtval;
            `CSR_MSCRATCH: csr_rdata = mscratch;
            `CSR_MIE:      csr_rdata = mie;
            `CSR_MIP:      csr_rdata = {24'b0, mtip_pending, 7'b0};
            `CSR_MHARTID:  csr_rdata = 32'h0; // 单核系统直接返回 0
            `CSR_CYCLE, `CSR_MCYCLE:       csr_rdata = mcycle[31:0];
            `CSR_CYCLEH, `CSR_MCYCLEH:     csr_rdata = mcycle[63:32];
            `CSR_INSTRET, `CSR_MINSTRET:   csr_rdata = minstret[31:0];
            `CSR_INSTRETH, `CSR_MINSTRETH: csr_rdata = minstret[63:32];
            `CSR_STALL_CYCLES:             csr_rdata = stall_cycles[31:0];
            `CSR_STALL_CYCLESH:            csr_rdata = stall_cycles[63:32];
            default:       csr_rdata = 32'h0;
        endcase
    end

    // 写 CSR 以及硬件更新逻辑 (时序逻辑)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // 仅有 M 模式：MPP 固定为 11，其他未实现状态位读回 0。
            mstatus  <= 32'h0000_1800;
            mtvec    <= 32'b0;
            mepc     <= 32'b0;
            mcause   <= 32'b0;
            mtval    <= 32'b0;
            mscratch <= 32'b0;
            mie      <= 32'b0;
        end else begin
            // 1. 优先处理硬件触发的异常更新 (进入中断)
            if (trap_valid) begin
                mepc        <= {trap_pc[31:2], 2'b00};
                mcause      <= trap_cause;
                mtval       <= trap_tval;
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
                    // 本核只实现 MIE、MPIE；MPP 只能表示唯一支持的 M 模式。
                    `CSR_MSTATUS:  mstatus  <= (csr_wdata & 32'h0000_0088) |
                                                32'h0000_1800;
                    // BASE 保持 4 字节对齐；只支持 MODE=0/1，保留编码 WARL 为 Direct。
                    `CSR_MTVEC:    mtvec    <= {csr_wdata[31:2],
                                               (csr_wdata[1:0] == 2'b01) ? 2'b01 : 2'b00};
                    // RV32I 不支持压缩指令，IALIGN=32，mepc[1:0] 恒为 0。
                    `CSR_MEPC:     mepc     <= {csr_wdata[31:2], 2'b00};
                    `CSR_MCAUSE:   mcause   <= csr_wdata;
                    `CSR_MTVAL:    mtval    <= csr_wdata;
                    `CSR_MSCRATCH: mscratch <= csr_wdata;
                    // 当前只有 Timer 来源；其他尚未实现的使能位读回 0。
                    `CSR_MIE:      mie      <= {24'b0, csr_wdata[7], 7'b0};
                endcase
            end
        end
    end

    // 请求到来时无条件挂起，不受 MIE/MTIE 影响；只有 Timer 真正被接收才清除。
    // 清除优先使单周期请求在“到达且立即接收”时不会残留第二次中断。
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            mtip_pending <= 1'b0;
        else if (timer_irq_taken)
            mtip_pending <= 1'b0;
        else if (timer_int)
            mtip_pending <= 1'b1;
    end

endmodule
