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

logic [31:0] pc;
logic        pc_en;
logic [31:0] pc_target;

pc_reg u_pc_reg(
    .clk       (clk       ),
    .rst       (rst       ),
    .pc_en     (pc_en     ),
    .pc_target (pc_target ),
    .inst_addr (inst_addr ),
    .pc        (pc        )
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

data_path u_data_path(
    .clk       (clk       ),
    .rst       (rst       ),
    .pc        (pc        ),
    .inst      (inst      ),
    .pc_en     (pc_en     ),
    .pc_target (pc_target ),
    .dout      (rd_data   ),
    .rs1_addr  (rs1_addr  ),
    .rs2_addr  (rs2_addr  ),
    .rs1_data  (rs1_data  ),
    .rs2_data  (rs2_data  ),
    .rd_addr   (rd_addr   ),
    .mem_dout  (mem_dout  ),
    .mem_din   (mem_din   ),
    .mem_addr  (mem_addr  ),
    .mem_we    (mem_we    )
);

endmodule