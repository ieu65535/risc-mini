`include "instructions.vh"

module decoder(
    input [31:0] inst,
    
    output [ 6:0] opcode,
    output [ 2:0] funct3,
    output [ 6:0] funct7,
    output reg [31:0] imm,
    output is_imm,

    // register file interface
    output [ 4:0] srcA,
    output [ 4:0] srcB,
    input  [31:0] valA,
    input  [31:0] valB,

    output [ 4:0] dst
);

assign opcode = inst[6:0];
assign funct3 = inst[14:12];
assign funct7 = inst[31:25];

assign srcA = inst[19:15];
assign srcB = inst[24:20];
assign dst = (opcode == `TYPE_R) || (opcode == `TYPE_I) || (opcode == `TYPE_L) ? inst[11:7] : 0;

assign is_imm = (opcode == `TYPE_I);
assign jump = (opcode == `TYPE_B) || (opcode == `JAL);

wire [31:0] imm_I = $signed(inst[31:20]);
wire [31:0] imm_B = $signed({inst[31], inst[7], inst[30:25], inst[11:8], 1'b0});
wire [31:0] imm_S = $signed({inst[31:25], inst[11:7]});
wire [31:0] imm_J = $signed({inst[31], inst[19:12], inst[20], inst[30:21], 1'b0});
wire [31:0] imm_U = $signed({inst[31:12], 12'd0});

always @(*) begin
    case (opcode)
        `TYPE_I, `TYPE_L, `JALR: imm = $signed(inst[31:20]);
        `TYPE_B: imm = $signed({inst[31], inst[7], inst[30:25], inst[11:8], 1'b0});
        `JAL: imm = $signed({inst[31], inst[19:12], inst[20], inst[30:21], 1'b0});
        `TYPE_S: imm = $signed({inst[31:25], inst[11:7]});
        `LUI, `AUIPC: imm = $signed({inst[31:12], 12'd0});
        default: imm = 32'd0;
    endcase
end

always @(*) begin
    case (opcode)
        `TYPE_R: begin
            rd_addr = inst[11:7];
            case (funct3)
                `ADD: begin
                    case (funct7)
                        7'b0000000: rd = rs1 + rs2;
                        7'b0100000: rd = rs1 - rs2;
                    endcase
                end
                `SLL: rd = rs1 << rs2[4:0];
                `SLT: rd = $signed(rs1) < $signed(rs2);
                `SLTU: rd = rs1 < rs2;
                `XOR: rd = rs1 ^ rs2;
                `SR: begin
                    case (funct7)
                        7'b0000000: rd = rs1 >> rs2[4:0];
                        7'b0100000: rd = $signed(rs1) >>> rs2[4:0];
                    endcase
                end
                `OR: rd = rs1 | rs2;
                `AND: rd = rs1 & rs2;
            endcase
    endcase
end

endmodule