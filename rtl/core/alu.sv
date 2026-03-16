`include "instructions.vh"

// Arithmetic Logic Unit
module alu (
    input [31:0] dina,
    input [31:0] dinb,
    input [2:0] funct3,
    input is_sub,
    input is_sra,

    output eq,
    output lt,
    output ltu,
    output reg [31:0] dout
);

assign eq = dina == dinb;
assign lt = $signed(dina) < $signed(dinb);
assign ltu = dina < dinb;

always @(*) begin
    case (funct3)
        `ADD: begin
            if (is_sub)
                dout = dina - dinb;
            else
                dout = dina + dinb;
        end
        `SLL:   dout = dina << dinb[4:0];
        `SLT:   dout = lt;
        `SLTU:  dout = ltu;
        `XOR:   dout = dina ^ dinb;
        `SR: begin
            if (is_sra)
                dout = $signed(dina) >>> dinb[4:0];
            else
                dout = dina >> dinb[4:0];
        end
        `OR:    dout = dina | dinb;
        `AND:   dout = dina & dinb;
        default:   dout = 32'h0;
    endcase
end

endmodule