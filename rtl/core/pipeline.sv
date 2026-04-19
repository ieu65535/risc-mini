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
logic [1:0] pc_sel;

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

    .csr_en     (csr_en     ),
    .csr_op     (csr_op     ),
    .mret       (mret       ),
    .ecall      (ecall      ),
    .ebreak     (ebreak     )
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
    .alu_dout     (alu_dout     ),
    .pc_ex        (pc_ex        ),
    .rd_addr_mem  (rd_addr_mem  ),
    .wb_sel_mem   (wb_sel_mem   ),
    .alu_dout_mem (alu_dout_mem ),
    .mem_data     (mem_data     ),
    .pc_mem       (pc_mem       ),
    .rd_addr_wb   (rd_addr_wb   ),
    .rd_data      (rd_data      ),
    .rs1          (rs1          ),
    .rs2          (rs2          )
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

// D to E register
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
    end
end

logic [31:0] alu_dout;
logic        alu_cond;

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

wire [31:0] mem_din_ex;
wire [ 3:0] mem_we_ex;

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
    .is_sra   (is_sra_ex   )
);

logic [31:0] alu_dout_mem;
logic [ 2:0] funct3_mem;
logic [ 1:0] wb_sel_mem;
logic [31:0] pc_mem;
logic [ 4:0] rd_addr_mem;

logic [31:0] mem_din_mem;
logic [31:0] mem_dout_mem;
logic [ 3:0] mem_we_mem;

logic        csr_we_mem;
logic [11:0] csr_addr_mem;
logic [31:0] csr_wdata_mem;
logic [ 2:0] csr_op_mem;

logic        exception_mem;
logic [ 3:0] exception_code_mem;
logic [31:0] exception_pc_mem;

// E to M register
always_ff @(posedge clk) begin
    if (rst) begin
        alu_dout_mem <= 32'h0;
        funct3_mem <= 3'b0; 
        wb_sel_mem <= `WB_ALU;
        pc_mem <= 32'h0;
        rd_addr_mem <= 5'b0;
    end else begin
        alu_dout_mem <= alu_dout;
        funct3_mem   <= inst_ex[14:12]; 
        wb_sel_mem   <= wb_sel_ex;
        pc_mem       <= pc_ex;
        rd_addr_mem  <= rd_addr_ex;
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
        alu_dout_wb <= 32'h0;
        wb_sel_wb <= `WB_ALU;
        rd_addr_wb <= 5'b0;
        pc_wb <= 32'h0;
        mem_data_wb <= 32'h0;
    end else begin
        alu_dout_wb <= alu_dout_mem;
        wb_sel_wb <= wb_sel_mem;
        rd_addr_wb <= rd_addr_mem;
        pc_wb <= pc_mem;
        mem_data_wb <= mem_data;
    end
end

wb u_wb(
    .wb_sel   (wb_sel_wb   ),
    .alu_dout (alu_dout_wb ),
    .pc       (pc_wb       ),
    .mem_data (mem_data_wb ),
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
