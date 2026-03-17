`include "instructions.vh"
`include "../config.vh"

module data_path(
    input  logic        clk,
    input  logic        rst,
    input  logic [31:0] pc,
    input  logic [31:0] inst,

    output logic        pc_en,
    output logic [31:0] pc_target,
    output logic [31:0] dout,

    output logic [ 4:0] rs1_addr,
    output logic [ 4:0] rs2_addr,
    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,
    output logic [ 4:0] rd_addr,

    // memory bus interface
    input  logic [31:0] mem_dout,
    output logic [31:0] mem_din,
    output logic [31:0] mem_addr,
    output logic [ 3:0] mem_we
);

wire [6:0] opcode = inst[6:0];
wire [2:0] funct3 = inst[14:12];
wire [6:0] funct7 = inst[31:25];

assign rs1_addr = inst[19:15];
assign rs2_addr = inst[24:20];

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

reg [31:0] alu_dina, alu_dinb;
wire [31:0] alu_dout;
wire is_sra = funct7[5];
reg is_sub;
always @(*) begin
    is_sub = 0;
    alu_dina = rs1_data;
    alu_dinb = rs2_data;
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

logic [31:0] shift;

always @(*) begin
    dout = 0;
    rd_addr = 0;
    mem_addr = 0;
    mem_we = 0;
    mem_din = 0;
    pc_en = 0;
    pc_target = 0;
    next_state = NORMAL;
    shift = 0;
    case (state)
        NORMAL: begin
            case (opcode)//analysis
                `TYPE_R: begin
                    rd_addr = inst[11:7];
                    dout = alu_dout;
                end
                `TYPE_I: begin
                    rd_addr = inst[11:7];
                    dout = alu_dout;
                end
                `TYPE_B: begin
                    case (funct3)
                        `BEQ: pc_en = alu_eq;
                        `BNE: pc_en = !alu_eq;
                        `BLT: pc_en = alu_lt;
                        `BGE: pc_en = !alu_lt;
                        `BLTU: pc_en = alu_ltu;
                        `BGEU: pc_en = !alu_ltu;
                    endcase
                    if (pc_en) begin
                        pc_target = pc + imm_B;
                    end
                end
                `TYPE_L: begin
                    pc_en = 1;
                    pc_target = pc;
                    next_state = LOAD;
                    mem_addr = rs1_data + imm_I;
                end
                `TYPE_S: begin
                    mem_addr = rs1_data + imm_S;
                    mem_din = rs2_data;
                    case (funct3)
                        `SB: mem_we = 4'b0001;
                        `SH: mem_we = 4'b0011;
                        `SW: mem_we = 4'b1111;
                    endcase
                    mem_din = mem_din << {mem_addr[1:0], 3'b0};
                    mem_we = mem_we << mem_addr[1:0];
                end
                `JAL: begin
                    rd_addr = inst[11:7];
                    dout = pc + 4;
                    pc_en = 1;
                    pc_target = pc + imm_J;
                end
                `JALR: begin
                    rd_addr = inst[11:7];
                    dout = pc + 4;
                    pc_en = 1;
                    pc_target = (rs1_data + imm_I) & ~1;
                end
                `LUI: begin
                    rd_addr = inst[11:7];
                    dout = imm_U;
                end
                `AUIPC: begin
                    rd_addr = inst[11:7];
                    dout = pc + imm_U;
                end
                default: next_state = EXCEPT;
            endcase
        end
        LOAD: begin
            rd_addr = inst[11:7];
            mem_addr = rs1_data + imm_I;
            shift = mem_dout >> {mem_addr[1:0], 3'b0};
            case (funct3)
                `LB: dout = $signed(shift[7:0]);
                `LH: dout = $signed(shift[15:0]);
                `LW: dout = mem_dout;
                `LBU: dout = shift[7:0];
                `LHU: dout = shift[15:0];
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
    end
    else begin
        state <= next_state;
    end
end

`ifdef SIMULATION
initial begin
	$dumpvars(1, state, next_state);
    $dumpvars(1, opcode, funct3, funct7);
end
`endif

endmodule