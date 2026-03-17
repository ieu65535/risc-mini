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

data_path u_data_path(
    .clk       (clk       ),
    .rst       (rst       ),
    .pc        (pc        ),
    .inst      (inst      ),
    .pc_en     (pc_en     ),
    .pc_target (pc_target ),
    .mem_dout  (mem_dout  ),
    .mem_din   (mem_din   ),
    .mem_addr  (mem_addr  ),
    .mem_we    (mem_we    )
);

endmodule