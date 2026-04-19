`include "micro.vh"
<<<<<<< HEAD
module ctrl (
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

    // CSR相关输出
    output logic        csr_en,          // CSR使能
    output logic [ 2:0] csr_op,          // CSR操作
    output logic        mret,            // MRET指令
    output logic        ecall,           // ECALL指令
    output logic        ebreak           // EBREAK指令
=======
module ctrl(
    input  logic [ 4:0] rs1_addr,
    input  logic [ 4:0] rs2_addr,
    input  logic [ 4:0] rd_addr_ex,
    input  logic [ 1:0] wb_sel_ex,
    input  logic [ 1:0] pc_sel_ex,
    input  logic        alu_cond,
    input  logic [31:0] alu_dout,
    input  logic [31:0] pc_ex,
    output logic        stall,
    output logic        pc_mis,
    output logic [31:0] target_pc
>>>>>>> origin/ieu-dev
);

assign stall = (wb_sel_ex == `WB_MEM) && (rd_addr_ex != 5'b0) && ((rs1_addr == rd_addr_ex) || (rs2_addr == rd_addr_ex));

<<<<<<< HEAD

always @(*) begin
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

    //for csr
    csr_en = 1'b0;
    csr_op = 3'b000;
    mret = 1'b0;
    ecall = 1'b0;
    ebreak = 1'b0;

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
        
        `TYPE_CSR: begin
            if (inst[14:12] != 3'b000) begin
                // Zicsr instructions
                csr_en = 1'b1;
                rd_en  = 1'b1;
                wb_sel = `WB_CSR;
                csr_op = inst[14:12];
            end
            else begin
                // SYSTEM privilege instructions
                if (inst == 32'h30200073) begin
                    mret = 1'b1;    // MRET指令
                end 
                else if (inst == 32'h00000073) begin
                    ecall = 1'b1;   // ECALL指令
                end
                else if (inst == 32'h00100073) begin
                    ebreak = 1'b1;  // EBREAK指令
                end
                else begin
                    inst_valid = 1'b0;
                end
            end
        end
        default: inst_valid = 0;
=======
always_comb begin
    case (pc_sel_ex)
        `PC_N: pc_mis = 0;
        `PC_J: pc_mis = 0;
        `PC_B: pc_mis = !alu_cond;
        `PC_JR: pc_mis = 1;
    endcase
end

wire [31:0] jr_addr = {alu_dout[31:1], 1'b0};
always_comb begin
    case (pc_sel_ex)
        `PC_N: target_pc = 0;
        `PC_J: target_pc = 0;
        `PC_B: target_pc = pc_ex + 4;
        `PC_JR: target_pc = jr_addr;
>>>>>>> origin/ieu-dev
    endcase
end

endmodule