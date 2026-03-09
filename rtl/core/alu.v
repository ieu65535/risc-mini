`include "micro.vh"

// Arithmetic Logic Unit
module alu (
    input [3:0] micro,
    input [31:0] dina,
    input [31:0] dinb,
    output reg [31:0] dout
);

always @(*) begin
    case (micro)
        `ALU_ADD:  dout = dina + dinb;
        `ALU_SUB:  dout = dina - dinb;
        `ALU_AND:  dout = dina & dinb;
        `ALU_OR:   dout = dina | dinb;
        `ALU_XOR:  dout = dina ^ dinb;
        `ALU_SLT:  dout = $signed(dina) < $signed(dinb);
        `ALU_SLTU: dout = dina < dinb;
        `ALU_SLL:  dout = dina << dinb[4:0];
        `ALU_SRL:  dout = dina >> dinb[4:0];
        `ALU_SRA:  dout = $signed(dina) >>> dinb[4:0];
        default:   dout = 32'h0;
    endcase
end

endmodule