`include "instructions.vh"
module wb (
    input  logic        is_load,
    input  logic [ 2:0] funct3,
    input  logic [31:0] ex_dout,
    input  logic [31:0] mem_addr,
    input  logic [31:0] mem_dout,
    output logic [31:0] dout
);

logic [31:0] shift = mem_dout >> {mem_addr[1:0], 3'b00};
logic [31:0] mem_data;

always @(*) begin
    unique case (funct3)
        `LB: mem_data = $signed(shift[7:0]);
        `LH: mem_data = $signed(shift[15:0]);
        `LW: mem_data = mem_dout;
        `LBU: mem_data = shift[7:0];
        `LHU: mem_data = shift[15:0];
        default: mem_data = 32'h0;
    endcase
end

assign dout = is_load? mem_data : ex_dout;

endmodule