`include "instructions.vh"
`include "micro.vh"
`include "../config.vh"

module ex(
    input  logic [31:0] pc,
    input  logic [31:0] inst,

    output logic [31:0] alu_dout,
    output logic        alu_cond,

    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,

    input  logic [1:0] op1_sel,
    input  logic [1:0] op2_sel,
    input  logic [2:0] alu_ctrl,
    input  logic       is_sub,
    input  logic       is_sra
);

wire [31:0] imm_I = $signed(inst[31:20]);
wire [31:0] imm_S = $signed({inst[31:25], inst[11:7]});
wire [31:0] imm_U = $signed({inst[31:12], 12'd0});

logic [31:0] alu_dina;
logic [31:0] alu_dinb;

logic [31:0] csr_operand;
logic [1:0] temp;
assign csr_operand = csr_op[2]? {27'b0, inst[19:15]} : rs1_data;
assign temp = csr_op[1:0];

logic [4:0] csr_uimm;
assign csr_uimm = inst[19:15];

always @(*) begin
    csr_we = 1'b0;
    if (csr_en) begin
        case (csr_op)
            3'b001: csr_we = 1'b1;                    // CSRRW
            3'b101: csr_we = 1'b1;                    // CSRRWI
            3'b010: csr_we = (inst[19:15] != 5'b0);  // CSRRS
            3'b011: csr_we = (inst[19:15] != 5'b0);  // CSRRC
            3'b110: csr_we = (csr_uimm != 5'b0);     // CSRRSI
            3'b111: csr_we = (csr_uimm != 5'b0);     // CSRRCI
                //不写逻辑
            default: csr_we = 1'b0;
        endcase
    end
end

// CSR operation
always_comb begin
    if (csr_en) begin
        case (temp)
            2'b01: csr_wdata = csr_operand;
            2'b10: csr_wdata = csr_rdata | csr_operand;
            2'b11: csr_wdata = csr_rdata & ~csr_operand;
            default: csr_wdata = csr_rdata;
        endcase
    end else begin
        csr_wdata = 32'h0;
    end
end
assign csr_rd_data = csr_en ? csr_rdata : 32'h0;
assign csr_addr = inst[31:20];

always_comb begin
    exception = 1'b0;
    exception_code = 4'b0;
    if (ecall_de) begin
        exception = 1'b1;
        exception_code = `CAUSE_ECALL_M;
    end else if (ebreak_de) begin
        exception = 1'b1;
        exception_code = `CAUSE_BREAKPOINT;
    end else if (!inst_valid && (inst != 32'h00000013)) begin
        exception = 1'b1;
        exception_code = `CAUSE_ILLEGAL_INSTR;
    end else if (csr_illegal && csr_en) begin
        exception = 1'b1;
        exception_code = `CAUSE_ILLEGAL_INSTR;
    end
    exception_pc = pc;
end

always_comb begin
    case (op1_sel)
        `OP1_RS1: alu_dina = rs1_data;
        `OP1_IMU: alu_dina = imm_U;
        default: alu_dina = rs1_data;
    endcase
end

always_comb begin
    case (op2_sel)
        `OP2_RS2: alu_dinb = rs2_data;
        `OP2_IMI: alu_dinb = imm_I;
        `OP2_IMS: alu_dinb = imm_S;
        `OP2_PC:  alu_dinb = pc;
    endcase
end

alu u_alu(
    .dina   (alu_dina   ),
    .dinb   (alu_dinb   ),
    .funct3 (alu_ctrl ),
    .is_sub (is_sub ),
    .is_sra (is_sra ),
    .cond   (alu_cond   ),
    .dout   (alu_dout   )
);

endmodule