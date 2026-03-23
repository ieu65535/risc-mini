`include "../config.vh"
`include "instructions.vh"
module csr_regfile (
    input  logic        clk,
    input  logic        rst,
    
    // CSR读写接口
    input  logic [11:0] csr_addr,      
    input  logic [31:0] csr_wdata,     // datain
    input  logic [ 1:0] csr_op,        // 00=csrrw, 01=csrrs, 10=csrrc, 11=csr立即数
    output logic [31:0] csr_rdata,     // dataout
    output logic        csr_illegal,   
    
    // 中断控制接口
    input  logic        mret,               // MRET
    input  logic        exception,          
    input  logic [31:0] exception_pc,       //pc duiring exception
    input  logic [ 3:0] exception_code,     
    output logic        interrupt_taken,    // if interrupt taken
    output logic [31:0] interrupt_vector    
);

// CSR寄存器定义
    logic [31:0] mstatus;  // status
    logic [31:0] mie;      // interupt enable
    logic [31:0] mip;      // interrupt pending?
    logic [31:0] mtvec;    // instruction handler
    logic [31:0] mepc;     // PC duiring exception
    logic [31:0] mcause;   // recording of exception cause
    
    // the status register's MIE and MPIE bit
    wire mstatus_mie = mstatus[3];  // 全局中断使能
    wire mstatus_mpie = mstatus[7]; // 先前的中断使能
    
    // CSR read(combination logic)
    always_comb begin
        csr_rdata = 32'h0;
        csr_illegal = 1'b0;
        
        case (csr_addr)
            // 机器模式CSR
            `CSR_MSTATUS:   csr_rdata = mstatus;  
            `CSR_MIE:       csr_rdata = mie;      
            `CSR_MIP:       csr_rdata = mip;      
            `CSR_MTVEC:     csr_rdata = mtvec;   
            `CSR_MEPC:      csr_rdata = mepc;     
            `CSR_MCAUSE:    csr_rdata = mcause;   
            default: csr_illegal = 1'b1;   
        endcase
    end
    
    // CSR写操作
    always_ff @(posedge clk) begin
        if (rst) begin
            mstatus <= 32'h0;
            mie <= 32'h0;
            mip <= 32'h0;
            mtvec <= 32'h00000000;
            mepc <= 32'h0;
            mcause <= 32'h0;
        end else begin
            // 正常CSR写
            if (csr_op != 2'b00 && !csr_illegal) begin
                case (csr_addr)
                    `CSR_MSTATUS:   mstatus <= csr_wdata;
                    `CSR_MIE:       mie <= csr_wdata;
                    `CSR_MTVEC:     mtvec <= {csr_wdata[31:2], 2'b00}; // 对齐到4字节
                    `CSR_MEPC:      mepc <= {csr_wdata[31:1], 1'b0};   // 对齐到2字节
                    `CSR_MCAUSE:    mcause <= csr_wdata;
                    `CSR_MIP:       mip <= csr_wdata;
                endcase
            end
            
            // MRET
            if (mret) begin
                mstatus[7] <= mstatus[3];  // MPIE恢复为MIE
                mstatus[3] <= mstatus[7];  // MIE恢复为MPIE
                mstatus[12:11] <= 2'b11;   // 回到机器模式
            end
            
            // Exception 
            if (exception) begin
                mepc <= exception_pc;
                mcause <= {1'b0, exception_code, 27'b0}; // 异常，最高位为0
                mstatus[7] <= mstatus[3];  // MPIE保存当前MIE
                mstatus[3] <= 1'b0;        // 禁用中断
                mstatus[12:11] <= 2'b11;   // 切换到机器模式
            end
            
            // 中断处理
            if (interrupt_taken) begin
                mepc <= exception_pc;
                mcause <= {1'b1, 31'b0};   // 中断，最高位为1
                mstatus[7] <= mstatus[3];  // MPIE保存当前MIE
                mstatus[3] <= 1'b0;        // 禁用中断
                mstatus[12:11] <= 2'b11;   // 切换到机器模式
            end
        end
    end
    
    // 中断检测逻辑
    wire m_interrupt_enabled = mstatus_mie && (mie & mip) != 0;
    assign interrupt_taken = m_interrupt_enabled && !exception;
    
    // 异常/中断向量地址生成
    assign interrupt_vector = mtvec; // 简单直接模式
    
endmodule


