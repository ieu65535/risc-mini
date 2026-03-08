module reset_sync (
    input clk,
    input rst_n,
    output reg rst
);

reg rst_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rst_r <= 1'b1;
        rst <= 1'b1;
    end
    else begin
        rst_r <= 1'b0;
        rst <= rst_r;
    end
end

endmodule