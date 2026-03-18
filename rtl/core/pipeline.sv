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

logic [31:0] pc;
logic [31:0] alu_dout;
logic        alu_cond;
logic [ 1:0] pc_sel;

pc_reg u_pc_reg(
    .clk       (clk       ),
    .rst       (rst       ),
    .inst      (inst      ),
    .alu_dout  (alu_dout  ),
    .alu_cond  (alu_cond  ),
    .pc_sel    (pc_sel    ),
    .inst_addr (inst_addr ),
    .pc        (pc        )
);

wire [ 4:0] rs1_addr = inst[19:15];
wire [ 4:0] rs2_addr = inst[24:20];
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

logic [31:0] rs1;
logic [31:0] rs2;
always_comb begin
    if (rs1_addr == 0) rs1 = 0;
    else begin
        if (rs1_addr == rd_addr)
            rs1 = rd_data;
        else
            rs1 = rs1_data;
    end
end
always_comb begin
    if (rs2_addr == 0) rs2 = 0;
    else begin
        if (rs2_addr == rd_addr)
            rs2 = rd_data;
        else
            rs2 = rs2_data;
    end
end

logic inst_valid;
logic [1:0] op1_sel;
logic [1:0] op2_sel;
logic [2:0] alu_ctrl;
logic       is_sub;
logic       is_sra;
logic [3:0] mem_mask;
logic       rd_en;
logic [1:0] wb_sel;

ctrl u_ctrl(
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

ex u_ex(
    .pc       (pc       ),
    .inst     (inst     ),
    .alu_dout (alu_dout ),
    .alu_cond (alu_cond ),
    .rs1_data (rs1 ),
    .rs2_data (rs2 ),
    .mem_din  (mem_din  ),
    .mem_we   (mem_we   ),
    .op1_sel  (op1_sel  ),
    .op2_sel  (op2_sel  ),
    .alu_ctrl (alu_ctrl ),
    .is_sub   (is_sub   ),
    .is_sra   (is_sra   ),
    .mem_mask (mem_mask )
);

assign mem_addr = alu_dout;

logic [31:0] alu_dout_wb;
logic [ 2:0] funct3_wb;
logic [ 1:0] wb_sel_wb;
logic [31:0] pc_wb;

always_ff @(posedge clk) begin
    if (rst) begin
        alu_dout_wb <= 32'h0;
        funct3_wb <= 3'b0; 
        wb_sel_wb <= `WB_ALU;
        pc_wb <= 32'h0;
        rd_addr <= 5'b0;
    end else begin
        alu_dout_wb <= alu_dout;
        funct3_wb <= inst[14:12];
        wb_sel_wb <= wb_sel;
        pc_wb <= pc;
        rd_addr <= rd_en? inst[11:7] : 5'b0;
    end
end

wb u_wb(
    .funct3   (funct3_wb   ),
    .wb_sel   (wb_sel_wb   ),
    .alu_dout (alu_dout_wb ),
    .pc       (pc_wb       ),
    .mem_dout (mem_dout ),
    .dout     (rd_data     )
);

endmodule