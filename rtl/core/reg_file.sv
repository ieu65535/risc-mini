module reg_file (
    input  logic        clk,

    input  logic [ 4:0] rd_addr,
    input  logic [31:0] rd_data,

    input  logic [ 4:0] rs1_addr,
    input  logic [ 4:0] rs2_addr,
    output logic [31:0] rs1_data,
    output logic [31:0] rs2_data
);

logic [31:0] regs [0:31];

initial begin
    for(int i=0; i<32; i++) begin
        regs[i] = 32'b0;
    end
end

always_ff @(posedge clk) begin
    regs[rd_addr] <= rd_data;
end

always_comb begin
    if (rs1_addr == 5'd0) begin
        rs1_data = 32'b0; 
    end else if ((rs1_addr == rd_addr) && (rd_addr != 5'd0)) begin
        rs1_data = rd_data;  
    end else begin
        rs1_data = regs[rs1_addr]; 
    end
end

always_comb begin
    if (rs2_addr == 5'd0) begin
        rs2_data = 32'b0;
    end else if ((rs2_addr == rd_addr) && (rd_addr != 5'd0)) begin
        rs2_data = rd_data;
    end else begin
        rs2_data = regs[rs2_addr];
    end
end

endmodule