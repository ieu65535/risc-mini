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
    .pc        (pc        ),
    .stall     (load_use_stall)
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

logic inst_valid;
logic [1:0] op1_sel;
logic [1:0] op2_sel;
logic [2:0] alu_ctrl;
logic       is_sub;
logic       is_sra;
logic [3:0] mem_mask;
logic       rd_en;
logic [1:0] wb_sel;
logic [31:0] mem_din_ex;
logic [ 3:0] mem_we_ex;

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

logic load_use_stall;
logic [31:0] alu_dout_mem;
logic [ 2:0] funct3_mem;
logic [ 1:0] wb_sel_mem;
logic [31:0] pc_mem;
logic [ 4:0] rd_addr_mem;
logic [ 3:0] mem_we_mem; 
logic [31:0] mem_din_mem; 

assign load_use_stall = (wb_sel_mem == `WB_MEM) && (rd_addr_mem != 5'b0) && ((rs1_addr == rd_addr_mem) || (rs2_addr == rd_addr_mem));

logic [31:0] rs1;
logic [31:0] rs2;

always_comb begin
    rs1 = rs1_data; 
    if (rs1_addr != 5'b0) begin
        if (rs1_addr == rd_addr_mem) begin
            rs1 = alu_dout_mem;
        end else if (rs1_addr == rd_addr) begin 
            rs1 = rd_data;
        end
    end
end

always_comb begin
    rs2 = rs2_data;
    if (rs2_addr != 5'b0) begin
        if (rs2_addr == rd_addr_mem) begin
            rs2 = alu_dout_mem;
        end else if (rs2_addr == rd_addr) begin
            rs2 = rd_data;
        end
    end
end

ex u_ex(
    .pc       (pc        ),
    .inst     (inst      ),
    .alu_dout (alu_dout  ),
    .alu_cond (alu_cond  ),
    .rs1_data (rs1 ),
    .rs2_data (rs2 ),
    .mem_din  (mem_din_ex),
    .mem_we   (mem_we_ex ),
    .op1_sel  (op1_sel   ),
    .op2_sel  (op2_sel   ),
    .alu_ctrl (alu_ctrl  ),
    .is_sub   (is_sub    ),
    .is_sra   (is_sra    ),
    .mem_mask (mem_mask  )
);

always_ff @(posedge clk) begin
    if (rst || load_use_stall) begin
        alu_dout_mem <= 32'h0;
        funct3_mem <= 3'b0; 
        wb_sel_mem <= `WB_ALU;
        pc_mem <= 32'h0;
        rd_addr_mem <= 5'b0;
        mem_we_mem <= 4'b0;
        mem_din_mem <= 32'h0;
    end else begin
        alu_dout_mem <= alu_dout;
        funct3_mem <= inst[14:12];
        wb_sel_mem <= wb_sel;
        pc_mem <= pc;
        rd_addr_mem <= rd_en? inst[11:7] : 5'b0;
        mem_we_mem <= mem_we_ex;
        mem_din_mem <= mem_din_ex;
    end
end

logic [31:0] alu_dout_wb;
logic [ 1:0] wb_sel_wb;
logic [31:0] pc_wb;
logic [ 2:0] funct3_wb;

always_ff @(posedge clk) begin
    if (rst) begin
        alu_dout_wb <= 32'h0;
        wb_sel_wb <= `WB_ALU;
        rd_addr <= 5'b0;
        pc_wb <= 32'h0;
        funct3_wb <= 3'b0;
    end else begin
        alu_dout_wb <= alu_dout_mem;
        wb_sel_wb <= wb_sel_mem;
        rd_addr <= rd_addr_mem;
        pc_wb <= pc_mem;
        funct3_wb <= funct3_mem;
    end
end

assign mem_addr = alu_dout_mem;
assign mem_din  = mem_din_mem;
assign mem_we   = mem_we_mem;

wb u_wb(
    .funct3   (funct3_wb   ),
    .wb_sel   (wb_sel_wb   ),
    .alu_dout (alu_dout_wb ),
    .pc       (pc_wb       ),
    .mem_dout (mem_dout    ),
    .dout     (rd_data     )
);

endmodule