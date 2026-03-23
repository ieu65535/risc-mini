`include "instructions.vh"
`include "micro.vh"
module wb (
    input  logic [ 2:0] funct3,
    input  logic [ 1:0] wb_sel,
    input  logic [31:0] alu_dout,
    input  logic [31:0] pc,
    input  logic [31:0] mem_dout,
    output logic [31:0] dout
);

wire  [31:0] shift = mem_dout >> {alu_dout[1:0], 3'b0};
logic [31:0] mem_data;

always @(*) begin
    case (wb_sel)
        `WB_ALU: dout = alu_dout;
        `WB_MEM: begin
            case (funct3)
                `LB: dout = $signed(shift[7:0]);
                `LH: dout = $signed(shift[15:0]);
                `LW: dout = mem_dout;
                `LBU: dout = shift[7:0];
                `LHU: dout = shift[15:0];
                default: dout = 0;
            endcase
        end
        `WB_PC4: dout = pc + 4;
        `WB_CSR: dout = 0;
    endcase
end

endmodule