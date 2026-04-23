`include "instructions.vh"
module lmb(
    input  logic [31:0] alu_dout,
    input  logic [31:0] alu_dout_mem,
    input  logic [31:0] rs2,
    input  logic [ 3:0] mem_mask,
    input  logic [ 2:0] funct3,

    input  logic [31:0] mem_dout,
    output logic [31:0] mem_din,
    output logic [31:0] mem_addr,
    output logic [ 3:0] mem_we,

    output logic [31:0] mem_data
);

assign mem_addr = alu_dout;
assign mem_din = rs2 << {mem_addr[1:0], 3'b0};
assign mem_we = mem_mask << mem_addr[1:0];

wire  [31:0] shift = mem_dout >> {alu_dout_mem[1:0], 3'b0};

always @(*) begin
    case (funct3)
        `LB: mem_data = $signed(shift[7:0]);
        `LH: mem_data = $signed(shift[15:0]);
        `LW: mem_data = mem_dout;
        `LBU: mem_data = shift[7:0];
        `LHU: mem_data = shift[15:0];
        default: mem_data = 0;
    endcase
end

endmodule