// wb_sel
`define WB_ALU   2'b00
`define WB_MEM   2'b01
`define WB_PC4   2'b10
`define WB_CSR   2'b11

// op1_sel
`define OP1_RS1  2'b00
`define OP1_IMU  2'b01

// op2_sel
`define OP2_RS2  2'b00
`define OP2_IMI  2'b01
`define OP2_IMS  2'b10
`define OP2_PC   2'b11

// pc_sel
`define PC_N     2'b00
`define PC_J     2'b01
`define PC_JR    2'b10
`define PC_B     2'b11
