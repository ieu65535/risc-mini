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
wire [11:0] csr_addr = inst[31:20];


always_comb begin
    inst_valid = 1;
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
            case (funct3)
                `SB: mem_mask = 4'b0001;
                `SH: mem_mask = 4'b0011;
                `SW: mem_mask = 4'b1111;
            endcase
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
        `SYSTEM: begin
            
            if (funct3 == 3'b000) begin
                // 特权指令
                if (csr_addr == 12'h000) begin
                    is_ecall = 1;
                end else if (csr_addr == 12'h302) begin
                    is_mret = 1;
                end
            end else begin
                // CSR 读写指令 (CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI)
                csr_we = 1;
                rd_en = 1;
                wb_sel = `WB_CSR; // 将 CSR 读出的数据写回通用寄存器 rd
                
            end
        end
        default: inst_valid = 0;
    endcase
end

endmodule