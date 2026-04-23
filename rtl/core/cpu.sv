module cpu(
    input  logic clk,
    input  logic rst,

    input  logic [31:0] inst,
    output logic [31:0] inst_addr,

    input  logic [31:0] mem_dout,
    output logic [31:0] mem_din,
    output logic [31:0] mem_addr,
    output logic [ 3:0] mem_we
);

logic [ 4:0] rs1_addr;
logic [ 4:0] rs2_addr;
logic [31:0] rs1_data;
logic [31:0] rs2_data;
logic [ 4:0] rd_addr;
logic [31:0] rd_data;
reg_file u_reg_file(
    .clk      (clk      ),
    .rd_addr  (rd_addr  ),
    .rd_data  (rd_data  ),
    .rs1_addr (rs1_addr ),
    .rs2_addr (rs2_addr ),
    .rs1_data (rs1_data ),
    .rs2_data (rs2_data )
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
    .inst       (inst       ),
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

data_path u_data_path(
    .clk        (clk        ),
    .rst        (rst        ),
    .inst       (inst       ),
    .inst_addr  (inst_addr  ),
    .dout       (rd_data    ),
    .rs1_addr   (rs1_addr   ),
    .rs2_addr   (rs2_addr   ),
    .rs1_data   (rs1_data   ),
    .rs2_data   (rs2_data   ),
    .rd_addr    (rd_addr    ),
    .mem_dout   (mem_dout   ),
    .mem_din    (mem_din    ),
    .mem_addr   (mem_addr   ),
    .mem_we     (mem_we     ),
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

endmodule