`include "micro.vh"
module pipeline(
    input  logic clk,
    input  logic rst,

    input  logic [31:0] inst,
    output logic [31:0] inst_addr,

    input  logic [31:0] mem_dout,
    output logic [31:0] mem_din,
    output logic [31:0] mem_addr,
    output logic [ 3:0] mem_we
);

logic        stall;
logic        pc_mis;
logic [31:0] target_pc;

ctrl u_ctrl(
    .rs1_addr   (rs1_addr   ),
    .rs2_addr   (rs2_addr   ),
    .rd_addr_ex (rd_addr_ex ),
    .wb_sel_ex  (wb_sel_ex  ),
    .pc_sel_ex  (pc_sel_ex  ),
    .alu_cond   (alu_cond   ),
    .alu_dout   (alu_dout   ),
    .pc_ex      (pc_ex      ),
    .stall      (stall      ),
    .pc_mis     (pc_mis     ),
    .target_pc  (target_pc  )
);

logic [31:0] pc;

pc_reg u_pc_reg(
    .clk       (clk       ),
    .rst       (rst       ),
    .stall     (stall     ),
    .inst      (inst      ),
    .pc_mis    (pc_mis    ),
    .target_pc (target_pc ),
    .pc_sel    (pc_sel    ),
    .inst_addr (inst_addr ),
    .pc        (pc        )
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
logic [1:0] pc_sel;
logic      csr_we;
logic      is_ecall;
logic      is_mret;

decoder u_decoder(
    .inst       (inst    ),
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
    .is_mret    (is_mret    )
);

wire  [ 4:0] rs1_addr = inst[19:15];
wire  [ 4:0] rs2_addr = inst[24:20];
logic [31:0] rs1_data;
logic [31:0] rs2_data;
logic [31:0] rd_data;

reg_file u_reg_file(
    .clk      (clk         ),
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


logic [31:0] csr_rdata_ex;
logic [31:0] csr_wdata_ex;
logic [31:0] csr_mepc;
logic [31:0] csr_mtvec;
logic        csr_mstatus_mie;
logic csr_we_ex;
logic is_ecall_ex;
logic is_mret_ex;

csr_file u_csr_file(
    .clk             (clk),
    .rst_n           (~rst),  // 注意你的 rst 是高有效，csr_file 里用的是低有效
    
    // EX 阶段进行 CSR 读写
    .csr_we          (csr_we_ex),
    .csr_waddr       (inst_ex[31:20]),
    .csr_wdata       (csr_wdata_ex),
    .csr_raddr       (inst_ex[31:20]),
    .csr_rdata       (csr_rdata_ex),
    
    // 异常/中断相关 (目前先接 0，第二阶段再处理)
    .trap_valid      (1'b0), 
    .mret_valid      (1'b0),
    .trap_pc         (32'h0),
    .trap_cause      (32'h0),
    
    // 直通输出
    .csr_mepc_out    (csr_mepc),
    .csr_mtvec_out   (csr_mtvec),
    .csr_mstatus_mie (csr_mstatus_mie)
);

logic        is_sra_ex;
logic        is_sub_ex;
logic [ 3:0] mem_mask_ex;
logic [ 2:0] alu_ctrl_ex;
logic [ 1:0] op1_sel_ex;
logic [ 1:0] op2_sel_ex;
logic [31:0] inst_ex;
logic [31:0] rs1_ex;
logic [31:0] rs2_ex;
logic [ 4:0] rd_addr_ex;
logic [ 1:0] wb_sel_ex;
logic [31:0] pc_ex;
logic [ 1:0] pc_sel_ex;

always_ff @(posedge clk) begin
    if(rst | stall | pc_mis) begin
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
        is_mret_ex  <= 1'b0;
    end else begin
        is_sra_ex   <= is_sra;
        is_sub_ex   <= is_sub;
        mem_mask_ex <= mem_mask;
        alu_ctrl_ex <= alu_ctrl;
        op1_sel_ex  <= op1_sel;
        op2_sel_ex  <= op2_sel;
        inst_ex     <= inst;
        rs1_ex      <= rs1;
        rs2_ex      <= rs2;
        rd_addr_ex  <= rd_en? inst[11:7] : 5'b0;
        wb_sel_ex   <= wb_sel;
        pc_ex       <= pc;
        pc_sel_ex   <= pc_sel;

        csr_we_ex   <= csr_we;
        is_ecall_ex <= is_ecall;
        is_mret_ex  <= is_mret;
    end
end


logic [31:0] alu_dout;
logic        alu_cond;

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

logic [31:0] alu_dout_mem;
logic [ 2:0] funct3_mem;
logic [ 1:0] wb_sel_mem;
logic [31:0] pc_mem;
logic [ 4:0] rd_addr_mem;
logic [31:0] csr_rdata_mem;

always_ff @(posedge clk) begin
    if (rst) begin
        alu_dout_mem <= 32'h0;
        funct3_mem <= 3'b0; 
        wb_sel_mem <= `WB_ALU;
        pc_mem <= 32'h0;
        rd_addr_mem <= 5'b0;
        csr_rdata_mem <= 32'h0;
    end else begin
        alu_dout_mem <= alu_dout;
        funct3_mem   <= inst_ex[14:12]; 
        wb_sel_mem   <= wb_sel_ex;
        pc_mem       <= pc_ex;
        rd_addr_mem  <= rd_addr_ex;
        csr_rdata_mem <= csr_rdata_ex;
    end
end

logic [31:0] mem_data;

lmb u_lmb(
    .alu_dout     (alu_dout     ),
    .alu_dout_mem (alu_dout_mem ),
    .rs2          (rs2_ex       ),
    .mem_mask     (mem_mask_ex  ),
    .funct3       (funct3_mem   ),
    .mem_dout     (mem_dout     ),
    .mem_din      (mem_din      ),
    .mem_addr     (mem_addr     ),
    .mem_we       (mem_we       ),
    .mem_data     (mem_data     )
);

logic [31:0] alu_dout_wb;
logic [ 1:0] wb_sel_wb;
logic [ 4:0] rd_addr_wb;
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
    end else begin
        alu_dout_wb <= alu_dout_mem;
        wb_sel_wb <= wb_sel_mem;
        rd_addr_wb <= rd_addr_mem;
        pc_wb <= pc_mem;
        mem_data_wb <= mem_data;
        csr_rdata_wb <= csr_rdata_mem;
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
initial begin
	$dumpvars(1, stall, pc_mis, target_pc);
    $dumpvars(1, rs1, rs2, rd_data, mem_dout, alu_dout, alu_dout_mem);
    // $dumpvars(1, rd_addr_mem, rd_addr_wb, alu_dout, alu_dout_mem);
    // $dumpvars(1, rs1_data, op1_sel_ex);
    $dumpvars(1, rs2_data, op2_sel_ex);
end
`endif

endmodule