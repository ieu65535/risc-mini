`include "instructions.vh"
`include "micro.vh"
module decoder (
    input logic [31:0] inst,

    output logic inst_valid,
    output logic [1:0] op1_sel,
    output logic [1:0] op2_sel,
    output logic [2:0] alu_ctrl,
    output logic       is_sub,
    output logic       is_sra,
    output logic [3:0] mem_mask,
    output logic       rd_en,
    output logic [1:0] wb_sel,
    output logic [1:0] pc_sel,

    output logic       csr_we,     // 写 CSR 使能
    output logic       is_ecall,   // 产生环境调用异常
    output logic       is_mret     // 异常返回
);
wire [6:0] opcode = inst[6:0];
wire [2:0] funct3 = inst[14:12];
wire     funct7_5 = inst[30];
wire [6:0] funct7 = inst[31:25];


always_comb begin
    inst_valid = 0;
    op1_sel = `OP1_RS1;
    op2_sel = `OP2_RS2;
    alu_ctrl = `ADD;
    is_sub = 0;
    is_sra = funct7_5;
    mem_mask = 4'b0;
    rd_en = 0;
    wb_sel = `WB_ALU;
    pc_sel = `PC_N;

    csr_we = 0;
    is_ecall = 0;
    is_mret = 0;
    case (opcode)
        `TYPE_R: begin
            if ((funct7 == 7'b0000000) ||
                ((funct7 == 7'b0100000) &&
                 ((funct3 == `ADD) || (funct3 == `SR)))) begin
                inst_valid = 1;
                alu_ctrl = funct3;
                is_sub = funct7_5;
                rd_en = 1;
            end
        end
        `TYPE_I: begin
            if (((funct3 == `SLL) && (funct7 == 7'b0000000)) ||
                ((funct3 == `SR) &&
                 ((funct7 == 7'b0000000) || (funct7 == 7'b0100000))) ||
                ((funct3 != `SLL) && (funct3 != `SR))) begin
                inst_valid = 1;
                op2_sel = `OP2_IMI;
                alu_ctrl = funct3;
                rd_en = 1;
            end
        end
        `TYPE_B: begin
            if ((funct3 == `BEQ) || (funct3 == `BNE) ||
                (funct3 == `BLT) || (funct3 == `BGE) ||
                (funct3 == `BLTU) || (funct3 == `BGEU)) begin
                inst_valid = 1;
                alu_ctrl = funct3;
                pc_sel = `PC_B;
            end
        end
        `TYPE_L: begin
            if ((funct3 == `LB) || (funct3 == `LH) ||
                (funct3 == `LW) || (funct3 == `LBU) ||
                (funct3 == `LHU)) begin
                inst_valid = 1;
                op2_sel = `OP2_IMI;
                rd_en = 1;
                wb_sel = `WB_MEM;
            end
        end
        `TYPE_S: begin
            case (funct3)
                `SB: begin inst_valid = 1; mem_mask = 4'b0001; end
                `SH: begin inst_valid = 1; mem_mask = 4'b0011; end
                `SW: begin inst_valid = 1; mem_mask = 4'b1111; end
                default: begin inst_valid = 0; mem_mask = 4'b0000; end
            endcase
            op2_sel = `OP2_IMS;
        end
        `JAL: begin
            inst_valid = 1;
            rd_en = 1;
            wb_sel = `WB_PC4;
            pc_sel = `PC_J;
        end
        `JALR: begin
            if (funct3 == 3'b000) begin
                inst_valid = 1;
                op2_sel = `OP2_IMI;
                rd_en = 1;
                wb_sel = `WB_PC4;
                pc_sel = `PC_JR;
            end
        end
        `LUI: begin
            inst_valid = 1;
            op1_sel = `OP1_IMU;
            alu_ctrl = `SLL;
            is_sub = 1;
            rd_en = 1;
        end
        `AUIPC: begin
            inst_valid = 1;
            op1_sel = `OP1_IMU;
            op2_sel = `OP2_PC;
            rd_en = 1;
        end
        `SYSTEM: begin
            if (funct3 == 3'b000) begin
                if (inst == 32'h00000073) begin
                    inst_valid = 1;
                    is_ecall = 1;
                end else if (inst == 32'h30200073) begin
                    inst_valid = 1;
                    is_mret = 1;
                end
            end else if ((funct3 == `INST_CSRRW) ||
                         (funct3 == `INST_CSRRS) ||
                         (funct3 == `INST_CSRRC) ||
                         (funct3 == `INST_CSRRWI) ||
                         (funct3 == `INST_CSRRSI) ||
                         (funct3 == `INST_CSRRCI)) begin
                inst_valid = 1;
                csr_we = 1;
                rd_en = 1;
                wb_sel = `WB_CSR;
            end
        end
        default: begin end
    endcase
end

endmodule
