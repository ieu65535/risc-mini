`include "instructions.vh"
`include "micro.vh"
module ctrl (
    input logic [31:0] inst,

    output logic inst_valid,
    output logic [1:0] op1_sel,
    output logic [1:0] op2_sel,
    output logic [2:0] alu_ctrl,
    output logic       is_sub,
    output logic       is_sra,
    output logic       rd_en,
    output logic [1:0] wb_sel,
    output logic [1:0] pc_sel
);
wire [6:0] opcode = inst[6:0];
wire [2:0] funct3 = inst[14:12];
wire     funct7_5 = inst[30];

always_comb begin
    inst_valid = 1;
    op1_sel = `OP1_RS1;
    op2_sel = `OP2_RS2;
    alu_ctrl = `ADD;
    is_sub = 0;
    is_sra = funct7_5;
    rd_en = 0;
    wb_sel = `WB_ALU;
    pc_sel = `PC_N;
    case (opcode)
        `TYPE_R: begin
            alu_ctrl = funct3;
            is_sub = funct7_5;
            rd_en = 1;
        end
        `TYPE_I: begin
            op2_sel = `OP2_IMI;
            alu_ctrl = funct3;
            rd_en = 1;
        end
        `TYPE_B: begin
            alu_ctrl = funct3;
            pc_sel = `PC_B;
        end
        `TYPE_L: begin
            op2_sel = `OP2_IMI;
            rd_en = 1;
            wb_sel = `WB_MEM;
        end
        `TYPE_S: begin
            op2_sel = `OP2_IMS;
        end
        `JAL: begin
            rd_en = 1;
            wb_sel = `WB_PC4;
            pc_sel = `PC_J;
        end
        `JALR: begin
            op2_sel = `OP2_IMI;
            rd_en = 1;
            wb_sel = `WB_PC4;
            pc_sel = `PC_JR;
        end
        `LUI: begin
            op1_sel = `OP1_IMU;
            alu_ctrl = `SLL;
            is_sub = 1;
            rd_en = 1;
        end
        `AUIPC: begin
            op1_sel = `OP1_IMU;
            op2_sel = `OP2_PC;
            rd_en = 1;
        end
        default: inst_valid = 0;
    endcase
end

endmodule