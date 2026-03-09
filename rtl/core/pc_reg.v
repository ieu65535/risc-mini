module pc_reg(
    input clk,
    input rst,

    output [31:0] inst_addr
);

reg [31:0] pc;

always @(posedge clk) begin
    if (rst) begin
        pc <= 0;
    end else begin
        pc <= pc + 4;
    end
end

endmodule