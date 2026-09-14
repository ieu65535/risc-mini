`include "instructions.vh"
`include "micro.vh"
module wb (
    input  logic [ 1:0] wb_sel,
    input  logic [31:0] alu_dout,
    input  logic [31:0] pc,
    input  logic [31:0] mem_data,
    input  logic [31:0] csr_rdata,

    output logic [31:0] dout
);

always @(*) begin
    case (wb_sel)
        `WB_ALU: dout = alu_dout;
        `WB_MEM: dout = mem_data;
        `WB_PC4: dout = pc + 4;
        `WB_CSR: dout = csr_rdata;
    endcase
end

endmodule