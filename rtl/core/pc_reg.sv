`include "micro.vh"

module pc_reg(
    input  logic        clk,
    input  logic        rst,
    input  logic        stall,
    
    input  logic        do_jump,   
    input  logic [31:0] jump_addr, 

    input  logic [31:0] mem_inst,  
    output logic [31:0] id_inst,   

    output logic [31:0] inst_addr, 
    output logic [31:0] pc
);

logic [31:0] fetch_pc; 
logic [31:0] next_pc;

always_comb begin
    if (do_jump) begin
        next_pc = jump_addr; 
    end
    else if (stall) begin
        next_pc = fetch_pc;       
    end
    else begin
        next_pc = fetch_pc + 4;
    end
end

assign inst_addr = next_pc;

always_ff @(posedge clk) begin
    if (rst) begin
        fetch_pc <= 32'hFFFFFFFC;
    end else begin
        fetch_pc <= next_pc;
    end
end

logic [31:0] id_pc;
always_ff @(posedge clk) begin
    if (rst) begin
        id_pc <= 32'h0;
    end else begin
        id_pc <= inst_addr; 
    end
end

assign pc = id_pc; 

assign id_inst = do_jump ? 32'h00000013 : mem_inst; 

endmodule