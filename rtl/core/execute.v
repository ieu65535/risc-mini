`include "instructions.vh"

module execute(
    input clk,
    input rst,

    input [6:0] op,
    input [6:0] fun7,
    input [2:0] fun3,
    input [31:0] dina,
    input [31:0] dinb,

    output reg cond,
    output reg [31:0] dout
);

always @(posedge clk) begin
    if (rst) begin
    end
    else begin
        case (op)
            `TYPE_R, `TYPE_I: begin
                case (fun3)
                    `ADD: begin
                        if (op == `TYPE_R && fun7[5])
                            dout <= dina - dinb;
                        else
                            dout <= dina + dinb;
                    end
                    `SLL: dout <= dina << dinb[4:0];
                    `SLT: dout <= $signed(dina) < $signed(dinb);
                    `SLTU: dout <= dina < dinb;
                    `XOR: dout <= dina ^ dinb;
                    `SR: begin
                        if (fun7[5])
                            dout <= $signed(dina) >> dinb[4:0];
                        else
                            dout <= dina >> dinb[4:0];
                    end
                    `OR: dout <= dina | dinb;
                    `AND: dout <= dina & dinb;
                endcase
            end

            // BRANCH
            `TYPE_B: begin
                case (fun3)
                    `BEQ: cond <= dina == dinb;
                    `BNE: cond <= dina != dinb;
                    `BLT: cond <= $signed(dina) < $signed(dinb);
                    `BGE: cond <= $signed(dina) >= $signed(dinb);
                    `BLTU: cond <= dina < dinb;
                    `BGEU: cond <= dina >= dinb;
                endcase
            end

            // ST, LD
            7'b0000011, 7'b0100111: dout <= dina + dinb;


            7'b1101111: dout <= dina; // JAL
            7'b1100111: dout <= dina; // JALR
            7'b0110111: dout <= dina; // LUI
            7'b0010111: dout <= dina; // AUIPC
        endcase
    end
end

endmodule