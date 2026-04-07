`include "micro.vh"

module pipeline(
    input  logic clk,
    input  logic rst,

    input  logic [31:0] inst,
    output logic [31:0] inst_addr,

    input  logic [31:0] mem_dout,
    output logic [31:0] mem_din,
    output logic [31:0] mem_addr,
    output logic [ 3:0] mem_we,

    input logic rxd
);

logic        stall;
logic [31:0] pc;
logic [31:0] alu_dout;
logic        alu_cond;
logic [ 1:0] pc_sel;
logic [ 1:0] pc_sel_de;
logic [31:0] id_inst;

wire [31:0] imm_B_id = $signed({id_inst[31], id_inst[7], id_inst[30:25], id_inst[11:8], 1'b0});
wire [31:0] imm_J_id = $signed({id_inst[31], id_inst[19:12], id_inst[20], id_inst[30:21], 1'b0});

logic        predict_jump;
logic [31:0] predict_addr;
logic        mispredict;
logic [31:0] recovery_addr;
logic [ 1:0] pc_sel_mem;
logic        alu_cond_mem;
logic [31:0] pc_mem;
logic [31:0] alu_dout_mem;

wire  interrupt_taken;
logic interrupt_valid;

wire [31:0] interrupt_vector;

// trap request from EX (combinational)
logic        exception_de;
logic [ 3:0] exception_code_de;
logic [31:0] exception_pc_de;

// registered trap request
logic        exception_r;
logic [ 3:0] exception_code_r;
logic [31:0] exception_pc_r;

wire exception_valid = exception_wb;

assign predict_jump = (pc_sel == `PC_B) || (pc_sel == `PC_J);

always_comb begin
    if (pc_sel == `PC_B) begin
        predict_addr = pc + imm_B_id;
    end else if (pc_sel == `PC_J) begin
        predict_addr = pc + imm_J_id;
    end else begin
        predict_addr = 32'b0;
    end
end

pc_reg u_pc_reg(
    .clk             (clk             ),
    .rst             (rst             ),
    .stall           (stall           ),
    .predict_jump    (predict_jump    ),
    .predict_addr    (predict_addr    ),
    .mispredict      (mispredict      ),
    .recovery_addr   (recovery_addr   ),
    .mem_inst        (inst            ),
    .id_inst         (id_inst         ),
    .inst_addr       (inst_addr       ),
    .pc              (pc              ),
    .interrupt       (interrupt_valid ),
    .interrupt_vector(interrupt_vector),
    .exception       (exception_valid )
);

wire [ 4:0] rs1_addr = id_inst[19:15];
wire [ 4:0] rs2_addr = id_inst[24:20];
logic [31:0] rs1_data;
logic [31:0] rs2_data;
logic [ 4:0] rd_addr_wb;
logic [31:0] rd_data;

logic mret_mem;
wire [31:0] mepc_out;

always_comb begin
    mispredict = 1'b0;
    recovery_addr = 32'b0;

    if (pc_sel_mem == `PC_B && !alu_cond_mem) begin
        mispredict = 1'b1;
        recovery_addr = pc_mem + 4;
    end else if (pc_sel_mem == `PC_JR) begin
        mispredict = 1'b1;
        recovery_addr = alu_dout_mem & 32'hFFFF_FFFE;
    end else if (mret_wb) begin
        mispredict = 1'b1;
        recovery_addr = mepc_out;
    end
end

reg_file u_reg_file(
    .clk      (clk       ),
    .rd_addr  (rd_addr_wb),
    .rd_data  (rd_data   ),
    .rs1_addr (rs1_addr  ),
    .rs2_addr (rs2_addr  ),
    .rs1_data (rs1_data  ),
    .rs2_data (rs2_data  )
);

// CSR interface
wire [11:0] csr_addr;
wire [31:0] csr_wdata;
wire [ 2:0] csr_op;
wire        csr_we;
logic [ 2:0] csr_op_de;
wire         csr_en;
logic        csr_en_de;
wire         mret;
wire         ecall;
wire         ebreak;

wire [31:0] csr_rdata;
wire        csr_illegal;

logic rxd_sync1, rxd_sync2;
always_ff @(posedge clk) begin
    rxd_sync1 <= rxd;
    rxd_sync2 <= rxd_sync1;
end
wire rxd_test = !rxd_sync2;

// interrupt is also treated as one-cycle request to IF
always_comb begin
    interrupt_valid = interrupt_taken;
end

csr_regfile u_csr_regfile(
    .clk              (clk               ),
    .rst              (rst               ),
    .mepc_out         (mepc_out          ),
    .csr_raddr         (csr_addr       ),   
    .csr_waddr         (csr_addr_wb       ),   // WB 阶段写地址
    .csr_wdata        (csr_wdata_wb      ),
    .csr_op           (csr_op_wb         ),
    .csr_we           (csr_we_wb         ),
    .csr_rdata        (csr_rdata         ),
    .csr_illegal      (csr_illegal       ),
    .mret             (mret_wb           ),
    .exception        (exception_wb      ),
    .exception_pc     (exception_pc_wb   ),
    .exception_code   (exception_code_wb ),
    .interrupt_taken  (interrupt_taken   ),
    .interrupt_vector (interrupt_vector  ),
    .ext_irq          (rxd_test          )
);

logic       inst_valid;
logic [1:0] op1_sel;
logic [1:0] op2_sel;
logic [2:0] alu_ctrl;
logic       is_sub;
logic       is_sra;
logic [3:0] mem_mask;
logic       rd_en;
logic [1:0] wb_sel;

ctrl u_ctrl(
    .inst       (id_inst    ),
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

    .csr_en     (csr_en     ),
    .csr_op     (csr_op     ),
    .mret       (mret       ),
    .ecall      (ecall      ),
    .ebreak     (ebreak     )
);

logic [31:0] inst_de;
logic [ 1:0] wb_sel_de;
logic        rd_en_de;

wire [4:0] rd_addr_de = inst_de[11:7];
assign stall = (wb_sel_de == `WB_MEM) && rd_en_de && (rd_addr_de != 5'b0) &&
               ((rs1_addr == rd_addr_de) || (rs2_addr == rd_addr_de));

logic [ 1:0] wb_sel_mem;
logic [ 4:0] rd_addr_mem;

logic        is_sra_de;
logic        is_sub_de;
logic [ 3:0] mem_mask_de;
logic [ 2:0] alu_ctrl_de;
logic [ 1:0] op1_sel_de;
logic [ 1:0] op2_sel_de;
logic [31:0] rs1_data_de;
logic [31:0] rs2_data_de;
logic [31:0] pc_de;

// CSR/system related signals in DE stage
logic        mret_de;
logic        ecall_de;
logic        ebreak_de;
logic        inst_valid_de;

// D to E register
always_ff @(posedge clk) begin
    if (rst || mispredict || interrupt_valid || exception_valid) begin
        is_sra_de      <= 1'b0;
        is_sub_de      <= 1'b0;
        mem_mask_de    <= 4'b0;
        alu_ctrl_de    <= 3'b0;
        op1_sel_de     <= 2'b0;
        op2_sel_de     <= 2'b0;
        rs1_data_de    <= 32'h0;
        rs2_data_de    <= 32'h0;
        rd_en_de       <= 1'b0;
        wb_sel_de      <= `WB_ALU;
        pc_de          <= 32'h0;
        pc_sel_de      <= `PC_N;
        inst_de        <= 32'h0000_0013;

        csr_en_de      <= 1'b0;
        csr_op_de      <= 3'b0;
        mret_de        <= 1'b0;
        ecall_de       <= 1'b0;
        ebreak_de      <= 1'b0;
        inst_valid_de  <= 1'b0;
    end else if (stall) begin
        is_sra_de      <= is_sra_de;
        is_sub_de      <= is_sub_de;
        mem_mask_de    <= mem_mask_de;
        alu_ctrl_de    <= alu_ctrl_de;
        op1_sel_de     <= op1_sel_de;
        op2_sel_de     <= op2_sel_de;
        rs1_data_de    <= rs1_data_de;
        rs2_data_de    <= rs2_data_de;
        rd_en_de       <= rd_en_de;
        wb_sel_de      <= wb_sel_de;
        pc_de          <= pc_de;
        pc_sel_de      <= pc_sel_de;
        inst_de        <= inst_de;

        csr_en_de      <= csr_en_de;
        csr_op_de      <= csr_op_de;
        mret_de        <= mret_de;
        ecall_de       <= ecall_de;
        ebreak_de      <= ebreak_de;
        inst_valid_de  <= inst_valid_de;
    end else begin
        is_sra_de      <= is_sra;
        is_sub_de      <= is_sub;
        mem_mask_de    <= mem_mask;
        alu_ctrl_de    <= alu_ctrl;
        op1_sel_de     <= op1_sel;
        op2_sel_de     <= op2_sel;
        rs1_data_de    <= rs1_data;
        rs2_data_de    <= rs2_data;
        rd_en_de       <= rd_en;
        wb_sel_de      <= wb_sel;
        pc_de          <= pc;
        pc_sel_de      <= pc_sel;
        inst_de        <= id_inst;

        csr_en_de      <= csr_en;
        csr_op_de      <= csr_op;
        mret_de        <= mret;
        ecall_de       <= ecall;
        ebreak_de      <= ebreak;
        inst_valid_de  <= inst_valid;
    end
end

wire [4:0] rs1_addr_de = inst_de[19:15];
wire [4:0] rs2_addr_de = inst_de[24:20];
logic [31:0] rs1_fwd;
logic [31:0] rs2_fwd;

logic [31:0] csr_rd_data_mem;

always_comb begin
    if (rs1_addr_de == 5'b0)
        rs1_fwd = 32'h0;
    else if ((wb_sel_mem == `WB_ALU) && (rs1_addr_de == rd_addr_mem))
        rs1_fwd = alu_dout_mem;
    else if ((wb_sel_mem == `WB_PC4) && (rs1_addr_de == rd_addr_mem))
        rs1_fwd = pc_mem + 4;
    else if ((wb_sel_mem == `WB_CSR) && (rs1_addr_de == rd_addr_mem))
        rs1_fwd = csr_rd_data_mem;
    else if (rs1_addr_de == rd_addr_wb)
        rs1_fwd = rd_data;
    else
        rs1_fwd = rs1_data_de;
end

always_comb begin
    if (rs2_addr_de == 5'b0)
        rs2_fwd = 32'h0;
    else if ((wb_sel_mem == `WB_ALU) && (rs2_addr_de == rd_addr_mem))
        rs2_fwd = alu_dout_mem;
    else if ((wb_sel_mem == `WB_PC4) && (rs2_addr_de == rd_addr_mem))
        rs2_fwd = pc_mem + 4;
    else if ((wb_sel_mem == `WB_CSR) && (rs2_addr_de == rd_addr_mem))
        rs2_fwd = csr_rd_data_mem;
    else if (rs2_addr_de == rd_addr_wb)
        rs2_fwd = rd_data;
    else
        rs2_fwd = rs2_data_de;
end

logic [31:0] csr_rd_data;
logic [31:0] csr_rdata_fwd;

always_comb begin
    // 如果 MEM 阶段有指令正在写当前我们需要读的 CSR 地址，直接截胡 MEM 阶段的数据
    if (csr_we_mem && (csr_addr_mem == csr_addr)) begin
        csr_rdata_fwd = csr_wdata_mem;
    end 
    // 如果 WB 阶段有指令正在写，截胡 WB 阶段的数据
    else if (csr_we_wb && (csr_addr_wb == csr_addr)) begin
        csr_rdata_fwd = csr_wdata_wb;
    end 
    // 否则正常从物理寄存器堆读取
    else begin
        csr_rdata_fwd = csr_rdata;
    end
end

ex u_ex(
    .pc              (pc_de             ),
    .inst            (inst_de           ),
    .alu_dout        (alu_dout          ),
    .alu_cond        (alu_cond          ),
    .rs1_data        (rs1_fwd           ),
    .rs2_data        (rs2_fwd           ),
    .mem_din         (mem_din           ),
    .mem_we          (mem_we            ),
    .op1_sel         (op1_sel_de        ),
    .op2_sel         (op2_sel_de        ),
    .alu_ctrl        (alu_ctrl_de       ),
    .is_sub          (is_sub_de         ),
    .is_sra          (is_sra_de         ),
    .mem_mask        (mem_mask_de       ),

    .csr_en          (csr_en_de         ),
    .csr_op          (csr_op_de         ),
    .csr_rdata       (csr_rdata_fwd     ),
    .csr_wdata       (csr_wdata         ),
    .csr_addr        (csr_addr          ),
    .csr_rd_data     (csr_rd_data       ),
    .csr_we          (csr_we            ),

    .mret_de         (mret_de           ),
    .ecall_de        (ecall_de          ),
    .ebreak_de       (ebreak_de         ),
    .inst_valid      (inst_valid_de     ),
    .csr_illegal     (csr_illegal       ),
    .exception       (exception_de      ),
    .exception_code  (exception_code_de ),
    .exception_pc    (exception_pc_de   )
);

assign mem_addr = alu_dout;

logic [2:0] funct3_mem;

logic        csr_we_mem;
logic [11:0] csr_addr_mem;
logic [31:0] csr_wdata_mem;
logic [ 2:0] csr_op_mem;

logic        exception_mem;
logic [ 3:0] exception_code_mem;
logic [31:0] exception_pc_mem;

// E to M register
always_ff @(posedge clk) begin
    if (rst || mispredict || interrupt_valid || exception_valid) begin
        alu_dout_mem    <= 32'h0;
        funct3_mem      <= 3'b0;
        wb_sel_mem      <= `WB_ALU;
        pc_mem          <= 32'h0;
        rd_addr_mem     <= 5'b0;
        pc_sel_mem      <= `PC_N;
        alu_cond_mem    <= 1'b0;

        csr_rd_data_mem <= 32'h0;
        mret_mem        <= 1'b0;

        csr_we_mem      <= 1'b0;
        csr_addr_mem    <= 12'b0;
        csr_wdata_mem   <= 32'b0;
        csr_op_mem      <= 3'b0;
        exception_mem   <= 1'b0;
        exception_code_mem <= 4'b0;
        exception_pc_mem   <= 32'b0;
    end else begin
        alu_dout_mem    <= alu_dout;
        funct3_mem      <= inst_de[14:12];
        wb_sel_mem      <= wb_sel_de;
        pc_mem          <= pc_de;
        rd_addr_mem     <= rd_en_de ? inst_de[11:7] : 5'b0;
        pc_sel_mem      <= pc_sel_de;
        alu_cond_mem    <= alu_cond;

        csr_rd_data_mem <= csr_rd_data;
        mret_mem        <= mret_de;

        csr_we_mem      <= csr_we;          // 来自 u_ex 的输出
        csr_addr_mem    <= csr_addr;        // 来自 u_ex 的输出
        csr_wdata_mem   <= csr_wdata;       // 来自 u_ex 的输出
        csr_op_mem      <= csr_op_de;       // 你的解码信号
        exception_mem   <= exception_de;    // 来自 u_ex 的异常
        exception_code_mem <= exception_code_de;
        exception_pc_mem   <= exception_pc_de;
    end
end

logic [31:0] alu_dout_wb;
logic [ 2:0] funct3_wb;
logic [ 1:0] wb_sel_wb;
logic [31:0] pc_wb;
logic [31:0] mem_dout_wb;
logic [31:0] csr_rd_data_wb;

logic        csr_we_wb;
logic [11:0] csr_addr_wb;
logic [31:0] csr_wdata_wb;
logic [ 2:0] csr_op_wb;
logic        mret_wb;

logic        exception_wb;
logic [ 3:0] exception_code_wb;
logic [31:0] exception_pc_wb;

// M to W register
always_ff @(posedge clk) begin
    if (rst) begin
        alu_dout_wb    <= 32'h0;
        funct3_wb      <= 3'b0;
        wb_sel_wb      <= `WB_ALU;
        rd_addr_wb     <= 5'b0;
        pc_wb          <= 32'h0;
        mem_dout_wb    <= 32'h0;
        csr_rd_data_wb <= 32'h0;

        csr_we_wb       <= 1'b0;
        csr_addr_wb     <= 12'b0;
        csr_wdata_wb    <= 32'b0;
        csr_op_wb       <= 3'b0;
        mret_wb         <= 1'b0;
        exception_wb    <= 1'b0;
        exception_code_wb <= 4'b0;
        exception_pc_wb   <= 32'b0;
    end else begin
        alu_dout_wb    <= alu_dout_mem;
        funct3_wb      <= funct3_mem;
        wb_sel_wb      <= wb_sel_mem;
        rd_addr_wb     <= rd_addr_mem;
        pc_wb          <= pc_mem;
        mem_dout_wb    <= mem_dout;
        csr_rd_data_wb <= csr_rd_data_mem;

        csr_we_wb       <= csr_we_mem;
        csr_addr_wb     <= csr_addr_mem;
        csr_wdata_wb    <= csr_wdata_mem;
        csr_op_wb       <= csr_op_mem;
        mret_wb         <= mret_mem;
        exception_wb    <= exception_mem;
        exception_code_wb <= exception_code_mem;
        exception_pc_wb   <= exception_pc_mem;
    end
end

wb u_wb(
    .funct3   (funct3_wb     ),
    .wb_sel   (wb_sel_wb     ),
    .alu_dout (alu_dout_wb   ),
    .pc       (pc_wb         ),
    .mem_dout (mem_dout_wb   ),
    .csr_data (csr_rd_data_wb),
    .dout     (rd_data       )
);

endmodule
