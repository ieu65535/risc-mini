`include "instructions.vh"

// Arithmetic Logic Unit
module alu (
    input [31:0] dina,
    input [31:0] dinb,
    input [2:0] funct3,
    input is_sub,
    input is_sra,

    output logic        cond,
    output logic [31:0] dout
);

wire eq = dina == dinb;
wire lt = $signed(dina) < $signed(dinb);
wire ltu = dina < dinb;

always @(*) begin
    case (funct3)
        `ADD: begin
            if (is_sub)
                dout = dina - dinb;
            else
                dout = dina + dinb;
        end
        `SLL: begin
            if (is_sub)
                dout = dina;
            else
                dout = dina << dinb[4:0];
        end
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

always @(*) begin
    cond = 1'b0;
    case (funct3)
        `BEQ: cond = eq;
        `BNE: cond = !eq;
        `BLT: cond = lt;
        `BGE: cond = !lt;
        `BLTU: cond = ltu;
        `BGEU: cond = !ltu;
    endcase
end

endmodule