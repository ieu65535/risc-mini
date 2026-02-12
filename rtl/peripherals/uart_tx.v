`include "../config.vh"

module uart_tx (
    input clk,
    input rst,
    input en,
    input [15:0] prescale,
    //clk frequency / baud rate - 1 = prescale
    input [7:0] din,
    output reg txd,
    output busy
);

reg [7:0] data;

reg [1:0] state;
localparam [1:0]
    IDLE  = 2'b00,
    START = 2'b01,
    DATA  = 2'b10,
    STOP  = 2'b11;

reg [15:0] baud_cnt;
reg [2:0] bit_idx;

// Update baud counter
always @(posedge clk) begin
    if (state == IDLE)
        baud_cnt <= 16'd0;
    else begin
        if (baud_cnt < prescale)
            baud_cnt <= baud_cnt + 16'd1;
        else
            baud_cnt <= 16'd0;
    end
end

// Update bit index
always @(posedge clk) begin
    if (state == DATA) begin
        if (baud_cnt == prescale) 
            bit_idx <= bit_idx + 1;
    end
    else
        bit_idx <= 3'h0;
end

// Update txd
always @(posedge clk) begin
    case (state)
        IDLE: txd <= 1'b1;
        START: txd <= 1'b0;
        DATA: txd <= data[bit_idx];
        STOP: txd <= 1'b1;
    endcase
end

assign busy = (state!= IDLE);

// Finite State Machine
always @(posedge clk) begin
    if (rst) begin
        state <= IDLE;
    end
    else begin
        case (state)
            IDLE: begin
                if (en) begin
                    state <= START;
                    data <= din;
                `ifdef SIMULATION
                    $write("%c", din);
                    $fflush();
                `endif
                end
            end
            START:
                if (baud_cnt == prescale)
                    state <= DATA;
            DATA:
                if (baud_cnt == prescale && bit_idx == 3'h7)
                    state <= STOP;
            STOP: if (baud_cnt == prescale) state <= IDLE;
        endcase
    end
end

`ifdef SIMULATION
initial begin
	$dumpvars(1, en, din);
end
`endif

endmodule