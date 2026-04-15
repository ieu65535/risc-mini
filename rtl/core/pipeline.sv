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
    .pc_sel     (pc_sel     )
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