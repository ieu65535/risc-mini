`include "instructions.vh"

// Arithmetic Logic Unit
module jump (
    input [2:0] funct3,
    input [31:0] rs1,
    input [31:0] rs2,
    output reg cond
);

always @(*) begin
    case (funct3)
        `BEQ: cond = rs1 == rs2;
        `BNE: cond = rs1 != rs2;
        `BLT: cond = $signed(rs1) < $signed(rs2);
        `BGE: cond = $signed(rs1) >= $signed(rs2);
        `BLTU: cond = rs1 < rs2;
        `BGEU: cond = rs1 >= rs2;
    endcase
end

endmodule