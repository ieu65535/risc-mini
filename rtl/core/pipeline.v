module pipeline(
    input clk,
    input rst,
    input [31:0] inst,
    output [31:0] inst_addr,

    // memory bus interface
    input  [31:0] mem_din,
    output [31:0] mem_dout,
    output [31:0] mem_addr,
    output [ 3:0] mem_we
);

// instruction fetch stage
pc_reg u_pc_reg(
    .clk       (clk       ),
    .rst       (rst       ),
    .inst_addr (inst_addr )
);

reg [31:0] pc_F;
always @(posedge clk) begin
    pc_F <= inst_addr;
end

// instruction decode stage
wire [4:0] rs1_addr;
wire [4:0] rs2_addr;
wire [4:0] rd_addr;
wire [31:0] imm;
wire [6:0] opcode;
wire [2:0] funct3;
wire [6:0] funct7;
decoder u_decoder(
    .inst     (inst     ),
    .opcode   (opcode   ),
    .funct3   (funct3   ),
    .funct7   (funct7   ),
    .imm      (imm      ),
    .is_imm   (is_imm   ),
    .rs1_addr (rs1_addr ),
    .rs2_addr (rs2_addr ),
    .rd_addr  (rd_addr  )
);

wire [31:0] rs1_data;
wire [31:0] rs2_data;
wire [ 4:0] waddr;
wire [31:0] wdata;

reg_file u_reg_file(
    .clk      (clk      ),
    .waddr    (waddr    ),
    .wdata    (wdata    ),
    .rs1_addr (rs1_addr ),
    .rs2_addr (rs2_addr ),
    .rs1_data (rs1_data ),
    .rs2_data (rs2_data )
);

reg [31:0] rs1_D, rs2_D, imm_D, pc_D;
reg [ 4:0] rs1_addr_D, rs2_addr_D;
reg [ 2:0] funct3_D;
reg sub_rsa, is_imm_D;
always @(posedge clk) begin
    rs1_D <= rs1_data;
    rs2_D <= rs2_data;
    imm_D <= imm;
    funct3_D <= funct3;
    sub_rsa <= (funct7[5]);
    is_imm_D <= is_imm;
    pc_D <= pc_F;
    rs1_addr_D <= rs1_addr;
    rs2_addr_D <= rs2_addr;
end

// execute stage
wire [31:0] douta, doutb;
bypass u_bypass(
    .rd_addr  (rd_addr_E ),
    .rs1_addr (rs1_addr_D),
    .rs2_addr (rs2_addr_D),
    .rd_data  (rd_E      ),
    .rs1_data (rs1_D     ),
    .rs2_data (rs2_D     ),
    .douta    (douta     ),
    .doutb    (doutb     )
);

wire [31:0] dout;
alu u_alu(
    .funct3  (funct3_D),
    .rs1     (douta   ),
    .rs2     (doutb   ),
    .imm     (imm_D   ),
    .is_imm  (is_imm_D),
    .sub_rsa (sub_rsa ),
    .dout    (dout    )
);

reg [31:0] rd_E;
reg [ 4:0] rd_addr_E;
always @(posedge clk) begin
    rd_E <= dout;
    rd_addr_E <= rd_addr;
end

// write back
assign wdata = rd_E;
assign waddr = rd_addr_E;

endmodule