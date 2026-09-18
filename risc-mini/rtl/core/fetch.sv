`include "instructions.vh"

module fetch (
    input  logic        clk,
    input  logic        rst,
    input  logic        stall,
    input  logic        redirect_valid,
    input  logic [31:0] redirect_addr,

    output logic [31:0] inst_addr,
    input  logic [31:0] inst_rdata,
    input  logic        inst_ready,

    output logic [31:0] inst,
    output logic [31:0] pc,
    output logic        valid,
    output logic        fetch_wait
);

logic [31:0] request_pc;

wire [6:0] opcode = inst_rdata[6:0];
wire [31:0] imm_j = {{11{inst_rdata[31]}}, inst_rdata[31],
                     inst_rdata[19:12], inst_rdata[20],
                     inst_rdata[30:21], 1'b0};
wire [31:0] imm_b = {{19{inst_rdata[31]}}, inst_rdata[31],
                     inst_rdata[7], inst_rdata[30:25],
                     inst_rdata[11:8], 1'b0};

// Preserve the core's existing simple prediction policy: JAL and conditional
// branches are predicted taken. JALR and a not-taken branch are redirected in EX.
logic [31:0] pred_pc;
always @(*) begin
    case (opcode)
        `JAL:    pred_pc = request_pc + imm_j;
        `TYPE_B: pred_pc = request_pc + imm_b;
        default: pred_pc = request_pc + 32'd4;
    endcase
end

assign inst_addr  = request_pc;
assign fetch_wait = !inst_ready;

always_ff @(posedge clk) begin
    if (rst) begin
        request_pc <= 32'b0;
        inst       <= 32'h0000_0013;
        pc         <= 32'b0;
        valid      <= 1'b0;
    end else if (redirect_valid) begin
        request_pc <= redirect_addr;
        inst       <= 32'h0000_0013;
        pc         <= redirect_addr;
        valid      <= 1'b0;
    end else if (!stall) begin
        if (inst_ready) begin
            inst       <= inst_rdata;
            pc         <= request_pc;
            valid      <= 1'b1;
            request_pc <= pred_pc;
        end else begin
            // The previous IF/ID entry has already moved forward. Do not replay
            // it while the next DDR read is pending.
            inst  <= 32'h0000_0013;
            valid <= 1'b0;
        end
    end
end

endmodule
