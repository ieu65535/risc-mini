`include "instructions.vh"
`include "micro.vh"
`include "../config.vh"

module data_path(
    input  logic        clk,
    input  logic        rst,
    input  logic [31:0] inst,
    output logic [31:0] inst_addr,

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
    output logic [ 3:0] mem_we,

    input  logic inst_valid,
    input  logic [1:0] op1_sel,
    input  logic [1:0] op2_sel,
    input  logic [2:0] alu_ctrl,
    input  logic       is_sub,
    input  logic       is_sra,
    input  logic [3:0] mem_mask,
    input  logic       rd_en,
    input  logic [1:0] wb_sel,
    input  logic [1:0] pc_sel
);

wire [6:0] opcode = inst[6:0];
wire [2:0] funct3 = inst[14:12];
wire [6:0] funct7 = inst[31:25];

assign rs1_addr = inst[19:15];
assign rs2_addr = inst[24:20];
wire [31:0] rs1 = (rs1_addr == 0)? 0 : rs1_data;
wire [31:0] rs2 = (rs2_addr == 0)? 0 : rs2_data;

wire [31:0] imm_I = $signed(inst[31:20]);
wire [31:0] imm_B = $signed({inst[31], inst[7], inst[30:25], inst[11:8], 1'b0});
wire [31:0] imm_S = $signed({inst[31:25], inst[11:7]});
wire [31:0] imm_J = $signed({inst[31], inst[19:12], inst[20], inst[30:21], 1'b0});
wire [31:0] imm_U = $signed({inst[31:12], 12'd0});

logic [31:0] pc, next_pc;
assign inst_addr = next_pc;
logic [ 1:0] state, next_state;
localparam [1:0]
    NORMAL = 2'b00,
    LOAD   = 2'b01,//需要多周期
    EXCEPT = 2'b10;
//状态机，正常执行，加载数据，异常

logic [31:0] alu_dina;
logic [31:0] alu_dinb;
logic [31:0] alu_dout;

always_comb begin
    case (op1_sel)
        `OP1_RS1: alu_dina = rs1;
        `OP1_IMU: alu_dina = imm_U;
        default: alu_dina = rs1;
    endcase
end

always_comb begin
    case (op2_sel)
        `OP2_RS2: alu_dinb = rs2;
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
    .cond   (cond   ),
    .dout   (alu_dout   )
);

assign mem_addr = alu_dout;
assign mem_din = rs2 << {mem_addr[1:0], 3'b0};
assign mem_we = mem_mask << mem_addr[1:0];
wire [31:0] shift = mem_dout >> {mem_addr[1:0], 3'b0};

always @(*) begin
    dout = 0;
    case (state)
        NORMAL: begin
            case (wb_sel)
                `WB_ALU: dout = alu_dout;
                `WB_MEM: dout = 0;
                `WB_PC4: dout = pc + 4;
                `WB_CSR: dout = 0;
            endcase
        end
        LOAD: begin
            case (funct3)
                `LB: dout = $signed(shift[7:0]);
                `LH: dout = $signed(shift[15:0]);
                `LW: dout = mem_dout;
                `LBU: dout = shift[7:0];
                `LHU: dout = shift[15:0];
            endcase
        end
    endcase
end

always @(*) begin
    rd_addr = 0;
    next_pc = pc + 4;
    next_state = NORMAL;
    case (state)
        NORMAL: begin
            case (opcode)//analysis
                `TYPE_R: begin
                    rd_addr = inst[11:7];
                end
                `TYPE_I: begin
                    rd_addr = inst[11:7];
                end
                `TYPE_B: begin
                    if (cond) begin
                        next_pc = pc + imm_B;
                    end
                end
                `TYPE_L: begin
                    next_pc = pc;
                    next_state = LOAD;
                end
                `TYPE_S: ;
                `JAL: begin
                    rd_addr = inst[11:7];
                    next_pc = pc + imm_J;
                end
                `JALR: begin
                    rd_addr = inst[11:7];
                    next_pc = (rs1 + imm_I) & ~1;
                end
                `LUI: begin
                    rd_addr = inst[11:7];
                end
                `AUIPC: begin
                    rd_addr = inst[11:7];
                end
                default: next_state = EXCEPT;
            endcase
        end
        LOAD: begin
            rd_addr = inst[11:7];
        end
        EXCEPT: begin
            next_state = EXCEPT;
        end
    endcase
end

always_ff @(posedge clk) begin
    if (rst) begin
        pc <= -4;
    end else begin
        pc <= next_pc;
    end
end

always_ff @(posedge clk) begin
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