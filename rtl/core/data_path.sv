module data_path (
);

reg_file u_reg_file(
    .clk    (clk    ),
    .rst    (rst    ),
    .we     (we     ),
    .waddr  (waddr  ),
    .wdata  (wdata  ),
    .raddr1 (raddr1 ),
    .rdata1 (rdata1 ),
    .raddr2 (raddr2 ),
    .rdata2 (rdata2 )
);


alu u_alu(
    .funct3  (funct3  ),
    .rs1     (rs1     ),
    .rs2     (rs2     ),
    .imm     (imm     ),
    .is_imm  (is_imm  ),
    .sub_rsa (sub_rsa ),
    .dout    (dout    )
);


endmodule