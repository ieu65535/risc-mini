`include "micro.vh"
`include "instructions.vh"
module pipeline(
    input  logic clk,
    input  logic rst,

    input  logic [31:0] inst,
    input  logic        inst_ready,
    output logic [31:0] inst_addr,

    input  logic [31:0] mem_dout,
    input  logic        mem_ready,
    output logic        mem_en,
    output logic [31:0] mem_din,
    output logic [31:0] mem_addr,
    output logic [ 3:0] mem_we,

    input  logic timer_int
);

logic        stall;
logic        mem_wait;
logic        global_stall;
logic        commit_redirect;
logic        pc_mis;
logic [31:0] target_pc;
logic        trap_valid;
logic        mret_valid;
logic [31:0] trap_cause;
logic [31:0] trap_tval;
logic [ 1:0] pc_sel;
logic [31:0] fetch_inst;
logic        fetch_valid;
logic        fetch_wait;
wire  [ 4:0] rs1_addr = fetch_inst[19:15];
wire  [ 4:0] rs2_addr = fetch_inst[24:20];
logic [31:0] csr_rdata_ex;
logic [31:0] csr_wdata_ex;
logic [31:0] csr_mepc;
logic [31:0] csr_mtvec;
logic        csr_mstatus_mie;
logic        csr_mie_mtie;
logic        csr_mip_mtip;
logic        timer_irq_taken;
logic        csr_we_ex;
logic        is_ecall_ex;
logic        is_ebreak_ex;
logic        is_illegal_ex;
logic        is_mret_ex;
logic [ 4:0] rd_addr_ex;
logic [ 1:0] wb_sel_ex;
logic [31:0] pc_ex;
logic [31:0] inst_ex;
logic [ 1:0] pc_sel_ex;
logic [31:0] alu_dout;
logic        alu_cond;
logic [31:0] alu_dout_mem;
logic [ 1:0] wb_sel_mem;
logic [31:0] pc_mem;
logic [ 4:0] rd_addr_mem;
logic [31:0] csr_rdata_mem;
logic [31:0] mem_data;
logic [ 4:0] rd_addr_wb;
logic        valid_ex;
logic        valid_mem;
logic        valid_wb;
logic        kill_ex;
logic        commit_ex;
logic        commit_csr;
logic        commit_wb;
logic        mem_access_ex;
logic        mem_inflight;
logic        inst_addr_misaligned_ex;
logic        load_addr_misaligned_ex;
logic        store_addr_misaligned_ex;
logic [31:0] inst_misaligned_target_ex;

ctrl u_ctrl(
    .rs1_addr   (rs1_addr   ),
    .rs2_addr   (rs2_addr   ),
    .rd_addr_ex (rd_addr_ex ),
    .wb_sel_ex  (wb_sel_ex  ),
    .pc_sel_ex  (pc_sel_ex  ),
    .valid_ex   (valid_ex   ),
    .alu_cond   (alu_cond   ),
    .alu_dout   (alu_dout   ),
    .pc_ex      (pc_ex      ),
    .inst_ex    (inst_ex    ),
    .inst_misaligned_target_ex(inst_misaligned_target_ex),
    .stall      (stall      ),
    .pc_mis     (pc_mis     ),
    .target_pc  (target_pc  ),

    .is_ecall_ex(is_ecall_ex),
    .is_ebreak_ex(is_ebreak_ex),
    .is_illegal_ex(is_illegal_ex),
    .inst_addr_misaligned_ex(inst_addr_misaligned_ex),
    .load_addr_misaligned_ex(load_addr_misaligned_ex),
    .store_addr_misaligned_ex(store_addr_misaligned_ex),
    .is_mret_ex (is_mret_ex ),
    .csr_mtvec  (csr_mtvec  ),
    .csr_mepc   (csr_mepc   ),
    .csr_mstatus_mie(csr_mstatus_mie),
    .csr_mie_mtie(csr_mie_mtie),
    .csr_mip_mtip(csr_mip_mtip),
    .timer_int  (timer_int),  
    .irq_blocked(mem_inflight),
    
    .trap_valid (trap_valid ),
    .timer_irq_taken(timer_irq_taken),
    .mret_valid (mret_valid ),
    .trap_cause (trap_cause ),
    .trap_tval  (trap_tval  )
);

logic [31:0] pc;

fetch u_fetch (
    .clk            (clk        ),
    .rst            (rst        ),
    .stall          (global_stall),
    .redirect_valid (commit_redirect),
    .redirect_addr  (target_pc  ),
    .inst_addr      (inst_addr  ),
    .inst_rdata     (inst       ),
    .inst_ready     (inst_ready ),
    .inst           (fetch_inst ),
    .pc             (pc         ),
    .valid          (fetch_valid),
    .fetch_wait     (fetch_wait )
);

logic inst_valid;
logic [1:0] op1_sel;
logic [1:0] op2_sel;
logic [2:0] alu_ctrl;
logic       is_sub;
logic       is_sra;
logic [3:0] mem_mask;
logic       rd_en;
logic [1:0] wb_sel;
logic      csr_we;
logic      is_ecall;
logic      is_ebreak;
logic      is_mret;

decoder u_decoder(
    .inst       (fetch_inst),
    .inst_valid (inst_valid ),
    .op1_sel    (op1_sel    ),
    .op2_sel    (op2_sel    ),
    .alu_ctrl   (alu_ctrl   ),
    .is_sub     (is_sub     ),
    .is_sra     (is_sra     ),
    .mem_mask   (mem_mask   ),
    .rd_en      (rd_en      ),
    .wb_sel     (wb_sel     ),
    .pc_sel     (pc_sel     ),

    .csr_we     (csr_we     ),
    .is_ecall   (is_ecall   ),
    .is_ebreak  (is_ebreak  ),
    .is_mret    (is_mret    )
);

logic [31:0] rs1_data;
logic [31:0] rs2_data;
logic [31:0] rd_data;

reg_file u_reg_file(
    .clk      (clk         ),
    .rd_we    (commit_wb   ),
    .rd_addr  (rd_addr_wb  ),
    .rd_data  (rd_data     ),
    .rs1_addr (rs1_addr    ),
    .rs2_addr (rs2_addr    ),
    .rs1_data (rs1_data    ),
    .rs2_data (rs2_data    )
);

logic [31:0] rs1;
logic [31:0] rs2;

forward u_forward(
    .rs1_addr     (rs1_addr     ),
    .rs2_addr     (rs2_addr     ),
    .rs1_data     (rs1_data     ),
    .rs2_data     (rs2_data     ),
    .rd_addr_ex   (rd_addr_ex   ),
    .wb_sel_ex    (wb_sel_ex    ),
    .csr_rdata_ex (csr_rdata_ex ),
    .alu_dout     (alu_dout     ),
    .pc_ex        (pc_ex        ),
    .rd_addr_mem  (rd_addr_mem  ),
    .wb_sel_mem   (wb_sel_mem   ),
    .alu_dout_mem (alu_dout_mem ),
    .csr_rdata_mem(csr_rdata_mem),
    .mem_data     (mem_data     ),
    .pc_mem       (pc_mem       ),
    .rd_addr_wb   (rd_addr_wb   ),
    .rd_data      (rd_data      ),
    .rs1          (rs1          ),
    .rs2          (rs2          )
);


csr_file u_csr_file(
    .clk             (clk),
    .rst             (rst),  
    
    // EX 阶段进行 CSR 读写
    .csr_we          (commit_csr),
    .csr_waddr       (inst_ex[31:20]),
    .csr_wdata       (csr_wdata_ex),
    .csr_raddr       (inst_ex[31:20]),
    .csr_rdata       (csr_rdata_ex),
    
    .trap_valid      (trap_valid),
    .mret_valid      (mret_valid),
    .trap_pc         (pc_ex),      // 当前触发异常的指令 PC
    .trap_cause      (trap_cause),
    .trap_tval       (trap_tval),
    .timer_int       (timer_int),
    .timer_irq_taken (timer_irq_taken),
    .retire_valid    (valid_wb),
    .stall_valid     ((stall || mem_wait || fetch_wait) && !commit_redirect),
    
    // 直通输出
    .csr_mepc_out    (csr_mepc),
    .csr_mtvec_out   (csr_mtvec),
    .csr_mstatus_mie (csr_mstatus_mie),
    .csr_mie_mtie    (csr_mie_mtie),
    .csr_mip_mtip    (csr_mip_mtip)
);

logic        is_sra_ex;
logic        is_sub_ex;
logic [ 3:0] mem_mask_ex;
logic [ 2:0] alu_ctrl_ex;
logic [ 1:0] op1_sel_ex;
logic [ 1:0] op2_sel_ex;
logic [31:0] rs1_ex;
logic [31:0] rs2_ex;

assign kill_ex         = trap_valid;
assign commit_ex       = valid_ex && !kill_ex;
assign commit_csr      = csr_we_ex && commit_ex && !mem_wait;
assign commit_wb       = valid_wb && (rd_addr_wb != 5'b0);
assign mem_access_ex   = valid_ex && ((wb_sel_ex == `WB_MEM) || (|mem_mask_ex));
assign mem_en          = mem_access_ex && commit_ex;
assign mem_wait        = mem_en && !mem_ready;
assign global_stall    = stall || mem_wait;
assign commit_redirect = pc_mis && !mem_wait;

always_ff @(posedge clk) begin
    if (rst)
        mem_inflight <= 1'b0;
    else if (mem_inflight && mem_ready)
        mem_inflight <= 1'b0;
    else if (mem_en && !mem_ready)
        mem_inflight <= 1'b1;
end

always_ff @(posedge clk) begin
    if (rst | commit_redirect) begin
        is_sra_ex   <= 1'b0;
        is_sub_ex   <= 1'b0;
        mem_mask_ex <= 4'b0;
        alu_ctrl_ex <= 3'b0;
        op1_sel_ex  <= 2'b0;
        op2_sel_ex  <= 2'b0;
        inst_ex     <= 32'h0;
        rs1_ex      <= 32'h0;
        rs2_ex      <= 32'h0;
        rd_addr_ex  <= 5'b0;
        wb_sel_ex   <= `WB_ALU;
        pc_ex       <= 32'h0;
        pc_sel_ex   <= `PC_N;

        csr_we_ex   <= 1'b0;
        is_ecall_ex <= 1'b0;
        is_ebreak_ex <= 1'b0;
        is_illegal_ex <= 1'b0;
        is_mret_ex  <= 1'b0;
        valid_ex    <= 1'b0;
    end else if (mem_wait) begin
        // A data request is outstanding.  Keep the complete EX request stable
        // until the selected slave asserts mem_ready.
    end else if (stall | !fetch_valid) begin
        is_sra_ex   <= 1'b0;
        is_sub_ex   <= 1'b0;
        mem_mask_ex <= 4'b0;
        alu_ctrl_ex <= 3'b0;
        op1_sel_ex  <= 2'b0;
        op2_sel_ex  <= 2'b0;
        inst_ex     <= 32'h0;
        rs1_ex      <= 32'h0;
        rs2_ex      <= 32'h0;
        rd_addr_ex  <= 5'b0;
        wb_sel_ex   <= `WB_ALU;
        pc_ex       <= 32'h0;
        pc_sel_ex   <= `PC_N;
        csr_we_ex   <= 1'b0;
        is_ecall_ex <= 1'b0;
        is_ebreak_ex <= 1'b0;
        is_illegal_ex <= 1'b0;
        is_mret_ex  <= 1'b0;
        valid_ex    <= 1'b0;
    end else begin
        is_sra_ex   <= is_sra;
        is_sub_ex   <= is_sub;
        mem_mask_ex <= inst_valid ? mem_mask : 4'b0;
        alu_ctrl_ex <= alu_ctrl;
        op1_sel_ex  <= op1_sel;
        op2_sel_ex  <= op2_sel;
        inst_ex     <= fetch_inst;
        rs1_ex      <= rs1;
        rs2_ex      <= rs2;
        rd_addr_ex  <= (inst_valid && rd_en) ? fetch_inst[11:7] : 5'b0;
        wb_sel_ex   <= wb_sel;
        pc_ex       <= pc;
        pc_sel_ex   <= pc_sel;

        csr_we_ex   <= inst_valid && csr_we;
        is_ecall_ex <= inst_valid && is_ecall;
        is_ebreak_ex <= inst_valid && is_ebreak;
        is_illegal_ex <= !inst_valid;
        is_mret_ex  <= inst_valid && is_mret;
        valid_ex    <= 1'b1;
    end
end


ex u_ex(
    .pc       (pc_ex       ), 
    .inst     (inst_ex     ), 
    .alu_dout (alu_dout    ), 
    .alu_cond (alu_cond    ), 
    .rs1_data (rs1_ex      ), 
    .rs2_data (rs2_ex      ), 
    .op1_sel  (op1_sel_ex  ), 
    .op2_sel  (op2_sel_ex  ), 
    .alu_ctrl (alu_ctrl_ex ), 
    .is_sub   (is_sub_ex   ), 
    .is_sra   (is_sra_ex   ),
    .csr_rdata (csr_rdata_ex),
    .csr_wdata (csr_wdata_ex)

);

// RV32I has IALIGN=32.  JALR clears bit 0 before the alignment check.
wire [31:0] imm_j_ex = {{11{inst_ex[31]}}, inst_ex[31], inst_ex[19:12],
                        inst_ex[20], inst_ex[30:21], 1'b0};
wire [31:0] imm_b_ex = {{19{inst_ex[31]}}, inst_ex[31], inst_ex[7],
                        inst_ex[30:25], inst_ex[11:8], 1'b0};
wire [31:0] jal_target_ex    = pc_ex + imm_j_ex;
wire [31:0] branch_target_ex = pc_ex + imm_b_ex;
wire [31:0] jalr_target_ex   = {alu_dout[31:1], 1'b0};

assign inst_misaligned_target_ex =
       (pc_sel_ex == `PC_J) ? jal_target_ex :
       (pc_sel_ex == `PC_B) ? branch_target_ex : jalr_target_ex;

assign inst_addr_misaligned_ex = valid_ex &&
       (((pc_sel_ex == `PC_J)  && (|jal_target_ex[1:0])) ||
        ((pc_sel_ex == `PC_B)  && alu_cond && (|branch_target_ex[1:0])) ||
        ((pc_sel_ex == `PC_JR) && (|jalr_target_ex[1:0])));

assign load_addr_misaligned_ex = valid_ex && (wb_sel_ex == `WB_MEM) &&
       ((((inst_ex[14:12] == `LH) || (inst_ex[14:12] == `LHU)) && alu_dout[0]) ||
        ((inst_ex[14:12] == `LW) && (|alu_dout[1:0])));

assign store_addr_misaligned_ex = valid_ex &&
       (((mem_mask_ex == 4'b0011) && alu_dout[0]) ||
        ((mem_mask_ex == 4'b1111) && (|alu_dout[1:0])));

logic [ 2:0] funct3_mem;
logic [31:0] mem_dout_mem;

always_ff @(posedge clk) begin
    if (rst) begin
        alu_dout_mem <= 32'h0;
        funct3_mem <= 3'b0; 
        wb_sel_mem <= `WB_ALU;
        pc_mem <= 32'h0;
        rd_addr_mem <= 5'b0;
        csr_rdata_mem <= 32'h0;
        mem_dout_mem <= 32'h0;
        valid_mem <= 1'b0;
    end else if (mem_wait) begin
        // The older MEM instruction may retire, but the waiting EX request
        // must not enter MEM until its response is valid.
        alu_dout_mem <= 32'h0;
        funct3_mem <= 3'b0;
        wb_sel_mem <= `WB_ALU;
        pc_mem <= 32'h0;
        rd_addr_mem <= 5'b0;
        csr_rdata_mem <= 32'h0;
        mem_dout_mem <= 32'h0;
        valid_mem <= 1'b0;
    end else begin
        alu_dout_mem <= alu_dout;
        funct3_mem   <= inst_ex[14:12]; 
        wb_sel_mem   <= wb_sel_ex;
        pc_mem       <= pc_ex;
        rd_addr_mem  <= commit_ex ? rd_addr_ex : 5'b0;
        csr_rdata_mem <= csr_rdata_ex;
        mem_dout_mem <= mem_dout;
        valid_mem <= commit_ex;
    end
end

lmb u_lmb(
    .alu_dout     (alu_dout     ),
    .alu_dout_mem (alu_dout_mem ),
    .rs2          (rs2_ex       ),
    .mem_mask     (commit_ex ? mem_mask_ex : 4'b0),
    .funct3       (funct3_mem   ),
    .mem_dout     (mem_dout_mem ),
    .mem_din      (mem_din      ),
    .mem_addr     (mem_addr     ),
    .mem_we       (mem_we       ),
    .mem_data     (mem_data     )
);

logic [31:0] alu_dout_wb;
logic [ 1:0] wb_sel_wb;
logic [31:0] pc_wb;
logic [31:0] mem_data_wb;
logic [31:0] csr_rdata_wb;
always_ff @(posedge clk) begin
    if (rst) begin
        alu_dout_wb <= 32'h0;
        wb_sel_wb <= `WB_ALU;
        rd_addr_wb <= 5'b0;
        pc_wb <= 32'h0;
        mem_data_wb <= 32'h0;
        csr_rdata_wb <= 32'h0;
        valid_wb <= 1'b0;
    end else begin
        alu_dout_wb <= alu_dout_mem;
        wb_sel_wb <= wb_sel_mem;
        rd_addr_wb <= valid_mem ? rd_addr_mem : 5'b0;
        pc_wb <= pc_mem;
        mem_data_wb <= mem_data;
        csr_rdata_wb <= csr_rdata_mem;
        valid_wb <= valid_mem;
    end
end

wb u_wb(
    .wb_sel   (wb_sel_wb   ),
    .alu_dout (alu_dout_wb ),
    .pc       (pc_wb       ),
    .mem_data (mem_data_wb ),
    .csr_rdata (csr_rdata_wb),
    .dout     (rd_data     )
);

`ifdef SIMULATION
`ifdef DUMP_WAVES
initial begin
	$dumpvars(1, stall, pc_mis, target_pc);
    $dumpvars(1, rs1, rs2, rd_data, mem_dout, alu_dout, alu_dout_mem);
    // $dumpvars(1, rd_addr_mem, rd_addr_wb, alu_dout, alu_dout_mem);
    // $dumpvars(1, rs1_data, op1_sel_ex);
    $dumpvars(1, rs2_data, op2_sel_ex);
end
`endif
`endif

endmodule
