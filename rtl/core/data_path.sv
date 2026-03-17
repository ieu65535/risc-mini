`include "instructions.vh"
`include "micro.vh"
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
    output logic [ 3:0] mem_we,

    input  logic inst_valid,
    input  logic [1:0] op1_sel,
    input  logic [1:0] op2_sel,
    input  logic [2:0] alu_ctrl,
    input  logic       is_sub,
    input  logic       is_sra,
    input  logic       rd_en,
    input  logic [1:0] wb_sel,
    input  logic [1:0] pc_sel
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

logic [31:0] alu_dina;
logic [31:0] alu_dinb;
logic [31:0] alu_dout;

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
    .cond   (cond   ),
    .dout   (alu_dout   )
);

wire [31:0] load_addr = rs1_data + imm_I;
wire [31:0] shift = mem_dout >> {load_addr[1:0], 3'b0};

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
    mem_addr = 0;
    mem_we = 0;
    mem_din = 0;
    pc_en = 0;
    pc_target = 0;
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
                        pc_target = pc + imm_B;
                        pc_en = 1;
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
                    pc_en = 1;
                    pc_target = pc + imm_J;
                end
                `JALR: begin
                    rd_addr = inst[11:7];
                    pc_en = 1;
                    pc_target = (rs1_data + imm_I) & ~1;
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