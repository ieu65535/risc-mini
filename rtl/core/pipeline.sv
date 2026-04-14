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
logic [1:0] pc_sel_ex;
logic [31:0] id_inst;

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

wire [ 4:0] rs1_addr = inst[19:15];
wire [ 4:0] rs2_addr = inst[24:20];
logic [31:0] rs1_data;
logic [31:0] rs2_data;
logic [ 4:0] rd_addr_wb;
logic [31:0] rd_data;
logic [31:0] jump_addr;
logic        do_jump;

logic pc_mis;
logic [31:0] target_pc;

always_comb begin
    case (pc_sel_ex)
        `PC_N: pc_mis = 0;
        `PC_J: pc_mis = 0;
        `PC_B: pc_mis = !alu_cond;
        `PC_JR: pc_mis = 1;
    endcase
end

wire [31:0] jr_addr = {alu_dout[31:1], 1'b0};
always_comb begin
    case (pc_sel_ex)
        `PC_N: target_pc = 0;
        `PC_J: target_pc = 0;
        `PC_B: target_pc = pc_ex + 4;
        `PC_JR: target_pc = jr_addr;
    endcase
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

// for test
logic predict_jump;
assign predict_jump = (pc_sel == `PC_B) || (pc_sel == `PC_J);

assign stall = (wb_sel_ex == `WB_MEM) && (rd_addr_ex != 5'b0) && ((rs1_addr == rd_addr_ex) || (rs2_addr == rd_addr_ex));

logic [31:0] alu_dout_mem;
logic [ 1:0] wb_sel_mem;
logic [ 4:0] rd_addr_mem;
logic [ 1:0] pc_sel_mem;
logic        alu_cond_mem;

logic        is_sra_ex;
logic        is_sub_ex;
logic [ 3:0] mem_mask_ex;
logic [ 2:0] alu_ctrl_ex;
logic [ 1:0] op1_sel_ex;
logic [ 1:0] op2_sel_ex;
logic [31:0] inst_ex;
logic [31:0] rs1_data_ex;
logic [31:0] rs2_data_ex;
logic [ 4:0] rd_addr_ex;
logic [ 1:0] wb_sel_ex;
logic [31:0] pc_ex;

always_ff @(posedge clk) begin
    if(rst | stall | pc_mis) begin
        is_sra_ex   <= 1'b0;
        is_sub_ex   <= 1'b0;
        mem_mask_ex <= 4'b0;
        alu_ctrl_ex <= 3'b0;
        op1_sel_ex  <= 2'b0;
        op2_sel_ex  <= 2'b0;
        inst_ex     <= 32'h0;
        rs1_data_ex <= 32'h0;
        rs2_data_ex <= 32'h0;
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
        rs1_data_ex <= rs1_data;
        rs2_data_ex <= rs2_data;
        rd_addr_ex  <= rd_en? inst[11:7] : 5'b0;
        wb_sel_ex   <= wb_sel;
        pc_ex       <= pc;
        pc_sel_ex   <= pc_sel;
        inst_ex     <= inst;
    end
end

wire [4:0] rs1_addr_ex = inst_ex[19:15];
wire [4:0] rs2_addr_ex = inst_ex[24:20];
logic [31:0] rs1;
logic [31:0] rs2;

always_comb begin
    if (rs1_addr_ex == 0) 
        rs1 = 0;
    // 正常 ALU 结果前推
    else if ((wb_sel_mem == `WB_ALU) && (rs1_addr_ex == rd_addr_mem))
        rs1 = alu_dout_mem; 
    // JAL/JALR 的 PC+4 前推
    else if ((wb_sel_mem == `WB_PC4) && (rs1_addr_ex == rd_addr_mem))
        rs1 = pc_mem + 4; 
    // 从 WB 阶段前推
    else if (rs1_addr_ex == rd_addr_wb)
        rs1 = rd_data;      
    else
        rs1 = rs1_data_ex;
end

always_comb begin
    if (rs2_addr_ex == 0) 
        rs2 = 0;
    else if ((wb_sel_mem == `WB_ALU) && (rs2_addr_ex == rd_addr_mem))
        rs2 = alu_dout_mem;
    else if ((wb_sel_mem == `WB_PC4) && (rs2_addr_ex == rd_addr_mem))
        rs2 = pc_mem + 4;
    else if (rs2_addr_ex == rd_addr_wb)
        rs2 = rd_data;
    else
        rs2 = rs2_data_ex;
end

ex u_ex(
    .pc       (pc_ex       ), 
    .inst     (inst_ex     ), 
    .alu_dout (alu_dout    ), 
    .alu_cond (alu_cond    ), 
    .rs1_data (rs1         ), 
    .rs2_data (rs2         ), 
    .op1_sel  (op1_sel_ex  ), 
    .op2_sel  (op2_sel_ex  ), 
    .alu_ctrl (alu_ctrl_ex ), 
    .is_sub   (is_sub_ex   ), 
    .is_sra   (is_sra_ex   )
);

assign mem_addr = alu_dout;
assign mem_din = rs2 << {mem_addr[1:0], 3'b0};
assign mem_we = mem_mask_ex << mem_addr[1:0];


logic [ 3:0] funct3_mem;
logic [31:0] pc_mem;

always_ff @(posedge clk) begin
    if (rst) begin
        alu_dout_mem <= 32'h0;
        funct3_mem <= 3'b0; 
        wb_sel_mem <= `WB_ALU;
        pc_mem <= 32'h0;
        rd_addr_mem <= 5'b0;
        pc_sel_mem   <= `PC_N; 
        alu_cond_mem <= 1'b0;
    end else begin
        alu_dout_mem <= alu_dout;
        funct3_mem   <= inst_ex[14:12]; 
        wb_sel_mem   <= wb_sel_ex;
        pc_mem       <= pc_ex;
        rd_addr_mem  <= rd_addr_ex;
        pc_sel_mem   <= pc_sel_ex;
        alu_cond_mem <= alu_cond;
    end
end

logic [31:0] alu_dout_wb;
logic [ 2:0] funct3_wb;
logic [ 1:0] wb_sel_wb;
logic [31:0] pc_wb;
logic [31:0] mem_dout_wb;

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