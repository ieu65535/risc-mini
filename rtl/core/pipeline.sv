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
logic [31:0] pc;
logic [31:0] alu_dout;
logic        alu_cond;
logic [ 1:0] pc_sel;
logic [1:0] pc_sel_de;
logic [31:0] id_inst;

wire [31:0] imm_B_id = $signed({id_inst[31], id_inst[7], id_inst[30:25], id_inst[11:8], 1'b0});
wire [31:0] imm_J_id = $signed({id_inst[31], id_inst[19:12], id_inst[20], id_inst[30:21], 1'b0});

logic predict_jump;
logic [31:0] predict_addr;

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
    .clk            (clk          ),
    .rst            (rst          ),
    .stall          (stall        ),
    .predict_jump   (predict_jump ), 
    .predict_addr   (predict_addr ), 
    .mispredict     (mispredict   ), 
    .recovery_addr  (recovery_addr), 
    .mem_inst       (inst         ), 
    .id_inst        (id_inst      ), 
    .inst_addr      (inst_addr    ),
    .pc             (pc           )
);

wire [ 4:0] rs1_addr = id_inst[19:15];
wire [ 4:0] rs2_addr = id_inst[24:20];
logic [31:0] rs1_data;
logic [31:0] rs2_data;
logic [ 4:0] rd_addr_wb;
logic [31:0] rd_data;
logic [31:0] jump_addr;
logic        do_jump;

logic mispredict;
logic [31:0] recovery_addr;

always_comb begin
    mispredict = 1'b0;
    recovery_addr = 32'b0;

    if (pc_sel_mem == `PC_B && !alu_cond_mem) begin
        mispredict = 1'b1;
        recovery_addr = pc_mem + 4;
    end else if (pc_sel_mem == `PC_JR) begin
        mispredict = 1'b1;
        recovery_addr = alu_dout_mem & 32'hFFFFFFFE; 
    end
end

reg_file u_reg_file(
    .clk      (clk         ),
    .rd_addr  (rd_addr_wb  ),
    .rd_data  (rd_data     ),
    .rs1_addr (rs1_addr    ),
    .rs2_addr (rs2_addr    ),
    .rs1_data (rs1_data    ),
    .rs2_data (rs2_data    )
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
    .pc_sel     (pc_sel     )
);

wire [4:0] rd_addr_de = inst_de[11:7];
assign stall = (wb_sel_de == `WB_MEM) && rd_en_de && (rd_addr_de != 5'b0) && ((rs1_addr == rd_addr_de) || (rs2_addr == rd_addr_de));

logic [31:0] alu_dout_mem;
logic [ 1:0] wb_sel_mem;
logic [ 4:0] rd_addr_mem;
logic [ 1:0] pc_sel_mem;
logic        alu_cond_mem;

logic        is_sra_de;
logic        is_sub_de;
logic [ 3:0] mem_mask_de;
logic [ 2:0] alu_ctrl_de;
logic [ 1:0] op1_sel_de;
logic [ 1:0] op2_sel_de;
logic [31:0] inst_de;
logic [31:0] rs1_data_de;
logic [31:0] rs2_data_de;
logic        rd_en_de;
logic [ 1:0] wb_sel_de;
logic [31:0] pc_de;

wire is_branch_ex = (pc_sel_de == `PC_B);
wire is_jump_ex   = (pc_sel_de == `PC_J) || (pc_sel_de == `PC_JR);

always_ff @(posedge clk) begin
    if(rst | stall | mispredict) begin
        is_sra_de   <= 1'b0;
        is_sub_de   <= 1'b0;
        mem_mask_de <= 4'b0;
        alu_ctrl_de <= 3'b0;
        op1_sel_de  <= 2'b0;
        op2_sel_de  <= 2'b0;
        inst_de     <= 32'h0;
        rs1_data_de <= 32'h0;
        rs2_data_de <= 32'h0;
        rd_en_de    <= 1'b0;
        wb_sel_de   <= `WB_ALU;
        pc_de       <= 32'h0;
        pc_sel_de   <= `PC_N;
        inst_de     <= 32'h00000013; // NOP
    end else begin
        is_sra_de   <= is_sra;
        is_sub_de   <= is_sub;
        mem_mask_de <= mem_mask;
        alu_ctrl_de <= alu_ctrl;
        op1_sel_de  <= op1_sel;
        op2_sel_de  <= op2_sel;
        rs1_data_de <= rs1_data;
        rs2_data_de <= rs2_data;
        rd_en_de    <= rd_en;
        wb_sel_de   <= wb_sel;
        pc_de       <= pc;
        pc_sel_de   <= pc_sel;
        inst_de     <= id_inst;
    end
end

wire [4:0] rs1_addr_de = inst_de[19:15];
wire [4:0] rs2_addr_de = inst_de[24:20];
logic [31:0] rs1_fwd;
logic [31:0] rs2_fwd;

always_comb begin
    if (rs1_addr_de == 0) 
        rs1_fwd = 0;
    // 正常 ALU 结果前推
    else if ((wb_sel_mem == `WB_ALU) && (rs1_addr_de == rd_addr_mem))
        rs1_fwd = alu_dout_mem; 
    // JAL/JALR 的 PC+4 前推
    else if ((wb_sel_mem == `WB_PC4) && (rs1_addr_de == rd_addr_mem))
        rs1_fwd = pc_mem + 4; 
    // 从 WB 阶段前推
    else if (rs1_addr_de == rd_addr_wb)
        rs1_fwd = rd_data;      
    else
        rs1_fwd = rs1_data_de;
end

always_comb begin
    if (rs2_addr_de == 0) 
        rs2_fwd = 0;
    else if ((wb_sel_mem == `WB_ALU) && (rs2_addr_de == rd_addr_mem))
        rs2_fwd = alu_dout_mem;
    else if ((wb_sel_mem == `WB_PC4) && (rs2_addr_de == rd_addr_mem))
        rs2_fwd = pc_mem + 4;
    else if (rs2_addr_de == rd_addr_wb)
        rs2_fwd = rd_data;
    else
        rs2_fwd = rs2_data_de;
end

ex u_ex(
    .pc       (pc_de       ), 
    .inst     (inst_de     ), 
    .alu_dout (alu_dout    ), 
    .alu_cond (alu_cond    ), 
    .rs1_data (rs1_fwd     ), 
    .rs2_data (rs2_fwd     ), 
    .mem_din  (mem_din     ), 
    .mem_we   (mem_we      ), 
    .op1_sel  (op1_sel_de  ), 
    .op2_sel  (op2_sel_de  ), 
    .alu_ctrl (alu_ctrl_de ), 
    .is_sub   (is_sub_de   ), 
    .is_sra   (is_sra_de   ), 
    .mem_mask (mem_mask_de )
);

assign mem_addr = alu_dout;

logic [ 3:0] funct3_mem;
logic [31:0] pc_mem;

//E to M register
always_ff @(posedge clk) begin
    if (rst | mispredict) begin
        alu_dout_mem <= 32'h0;
        funct3_mem <= 3'b0; 
        wb_sel_mem <= `WB_ALU;
        pc_mem <= 32'h0;
        rd_addr_mem <= 5'b0;
        pc_sel_mem   <= `PC_N; 
        alu_cond_mem <= 1'b0;
    end else begin
        alu_dout_mem <= alu_dout;
        funct3_mem   <= inst_de[14:12]; 
        wb_sel_mem   <= wb_sel_de;
        pc_mem       <= pc_de;
        rd_addr_mem  <= rd_en_de ? inst_de[11:7] : 5'b0;
        pc_sel_mem   <= pc_sel_de;
        alu_cond_mem <= alu_cond;
    end
end

logic [31:0] alu_dout_wb;
logic [ 2:0] funct3_wb;
logic [ 1:0] wb_sel_wb;
logic [31:0] pc_wb;
logic [31:0] mem_dout_wb;

//M to W register
always_ff @(posedge clk) begin
    if (rst) begin
        alu_dout_wb <= 32'h0;
        funct3_wb <= 3'b0;
        wb_sel_wb <= `WB_ALU;
        rd_addr_wb <= 5'b0;
        pc_wb <= 32'h0;
        mem_dout_wb <= 32'h0;
    end else begin
        alu_dout_wb <= alu_dout_mem;
        funct3_wb <= funct3_mem;
        wb_sel_wb <= wb_sel_mem;
        rd_addr_wb <= rd_addr_mem;
        pc_wb <= pc_mem;
        mem_dout_wb <= mem_dout;
    end
end

wb u_wb(
    .funct3   (funct3_wb   ),
    .wb_sel   (wb_sel_wb   ),
    .alu_dout (alu_dout_wb ),
    .pc       (pc_wb       ),
    .mem_dout (mem_dout_wb ),
    .dout     (rd_data     )
);

endmodule