`include "instructions.vh"
`include "../config.vh"

module cpu(
    input clk,
    input rst,
    input [31:0] inst,// 指令输入
    output reg [31:0] next_pc,

    // memory bus interface
    input  [31:0] mem_dout,
    output reg [31:0] mem_din,
    output reg [31:0] mem_addr,
    output reg [ 3:0] mem_we
);

wire [6:0] opcode = inst[6:0];
wire [2:0] funct3 = inst[14:12];
wire [6:0] funct7 = inst[31:25];

wire [4:0] rs1_addr = inst[19:15];
wire [4:0] rs2_addr = inst[24:20];
reg  [4:0] rd_addr;

wire [31:0] imm_I = $signed(inst[31:20]);
wire [31:0] imm_B = $signed({inst[31], inst[7], inst[30:25], inst[11:8], 1'b0});
wire [31:0] imm_S = $signed({inst[31:25], inst[11:7]});
wire [31:0] imm_J = $signed({inst[31], inst[19:12], inst[20], inst[30:21], 1'b0});
wire [31:0] imm_U = $signed({inst[31:12], 12'd0});

reg [1:0] state, next_state;
localparam [1:0]
    NORMAL = 2'b00,
    LOAD   = 2'b01,//需要多周期
    EXCEPT = 2'b10;
//状态机，正常执行，加载数据，异常

reg [31:0] regs [0:31];
reg [31:0] rd, pc;
wire [31:0] rs1 = rs1_addr == 0? 0 : regs[rs1_addr];
wire [31:0] rs2 = rs2_addr == 0? 0 : regs[rs2_addr];

reg [31:0] alu_dina, alu_dinb;
wire [31:0] alu_dout;
wire is_sra = funct7[5];
reg is_sub;
always @(*) begin
    is_sub = 0;
    alu_dina = rs1;
    alu_dinb = rs2;
    case (opcode)
        `TYPE_R: begin
            is_sub = funct7[5];
        end
        `TYPE_I: begin
            alu_dinb = imm_I;
        end
    endcase
end

alu u_alu(
    .dina   (alu_dina   ),
    .dinb   (alu_dinb   ),
    .funct3 (funct3 ),
    .is_sub (is_sub ),
    .is_sra (is_sra ),
    .eq     (alu_eq     ),
    .lt     (alu_lt     ),
    .ltu    (alu_ltu    ),
    .dout   (alu_dout   )
);

always @(*) begin
    next_pc = pc + 4;
    if (rst) next_pc = 0;
    rd = 0;
    rd_addr = 0;
    mem_addr = 0;
    mem_we = 0;
    mem_din = 0;
    next_state = NORMAL;
    case (state)
        NORMAL: begin
            case (opcode)//analysis
                `TYPE_R: begin
                    rd_addr = inst[11:7];
                    rd = alu_dout;
                end
                `TYPE_I: begin
                    rd_addr = inst[11:7];
                    rd = alu_dout;
                end
                `TYPE_B: begin
                    case (funct3)
                        `BEQ: next_pc = (rs1 == rs2) ? (pc + imm_B) : (pc + 4);
                        `BNE: next_pc = (rs1 != rs2) ? (pc + imm_B) : (pc + 4);
                        `BLT: next_pc = ($signed(rs1) < $signed(rs2)) ? (pc + imm_B) : (pc + 4);
                        `BGE: next_pc = ($signed(rs1) >= $signed(rs2)) ? (pc + imm_B) : (pc + 4);
                        `BLTU: next_pc = (rs1 < rs2) ? (pc + imm_B) : (pc + 4);
                        `BGEU: next_pc = (rs1 >= rs2) ? (pc + imm_B) : (pc + 4);
                    endcase
                end
                `TYPE_L: begin
                    next_pc = pc;
                    next_state = LOAD;
                    mem_addr = rs1 + imm_I;
                end
                `TYPE_S: begin
                    mem_addr = rs1 + imm_S;
                    case (funct3)
                        `SB: begin
                            case (mem_addr[1:0])
                                2'b00: begin
                                    mem_din = rs2[7:0];
                                    mem_we = 4'b0001;
                                end
                                2'b01: begin
                                    mem_din = {rs2[7:0], 8'b0};
                                    mem_we = 4'b0010;
                                end
                                2'b10: begin
                                    mem_din = {rs2[7:0], 16'b0};
                                    mem_we = 4'b0100;
                                end
                                2'b11: begin
                                    mem_din = {rs2[7:0], 24'b0};
                                    mem_we = 4'b1000;
                                end
                            endcase
                        end
                        `SH: begin
                            case (mem_addr[1:0])
                                2'b00: begin
                                    mem_din = rs2[15:0];
                                    mem_we = 4'b0011;
                                end
                                2'b10: begin
                                    mem_din = {rs2[15:0], 16'b0};
                                    mem_we = 4'b1100;
                                end
                                default: next_state = EXCEPT;
                            endcase
                        end
                        `SW: begin
                            mem_din = rs2;
                            mem_we = 4'b1111;
                        end
                    endcase
                end
                `JAL: begin
                    rd_addr = inst[11:7];
                    rd = pc + 4;
                    next_pc = pc + imm_J;
                end
                `JALR: begin
                    rd_addr = inst[11:7];
                    rd = pc + 4;
                    next_pc = (rs1 + imm_I) & ~1;
                end
                `LUI: begin
                    rd_addr = inst[11:7];
                    rd = imm_U;
                end
                `AUIPC: begin
                    rd_addr = inst[11:7];
                    rd = pc + imm_U;
                end
                default: next_state = EXCEPT;
            endcase
        end
        LOAD: begin
            rd_addr = inst[11:7];
            mem_addr = rs1 + imm_I;
            case (funct3)
                `LB: begin
                    case (mem_addr[1:0])
                        2'b00: rd = $signed(mem_dout[7:0]);
                        2'b01: rd = $signed(mem_dout[15:8]);
                        2'b10: rd = $signed(mem_dout[23:16]);
                        2'b11: rd = $signed(mem_dout[31:24]);
                    endcase
                end
                `LH: begin
                    case (mem_addr[1:0])
                        2'b00: rd = $signed(mem_dout[15:0]);
                        2'b10: rd = $signed(mem_dout[31:16]);
                        default: next_state = EXCEPT;
                    endcase
                end
                `LW: rd = mem_dout;
                `LBU: begin
                    case (mem_addr[1:0])
                        2'b00: rd = mem_dout[7:0];
                        2'b01: rd = mem_dout[15:8];
                        2'b10: rd = mem_dout[23:16];
                        2'b11: rd = mem_dout[31:24];
                    endcase
                end
                `LHU: begin
                    case (mem_addr[1:0])
                        2'b00: rd = mem_dout[15:0];
                        2'b10: rd = mem_dout[31:16];
                        default: next_state = EXCEPT;
                    endcase
                end
            endcase
        end
        EXCEPT: begin
            next_state = EXCEPT;
        end
    endcase
end

//load the updated data(装载更新)
always @(posedge clk) begin
    if (rst) begin
        state <= NORMAL;
        pc <= 0;
    end
    else begin
        state <= next_state;
        pc <= next_pc;
        regs[rd_addr] <= rd;
    end
end

`ifdef SIMULATION
initial begin
	$dumpvars(1, pc, next_pc, state, next_state);
    $dumpvars(1, opcode, funct3, funct7);
end
`endif

endmodule