module uart_rx (
    input clk,
    input rst,
    input rxd,
    input [15:0] prescale,
    //clk frequency / baud rate - 1 = prescale
    output reg [7:0] dout,
    output reg valid
);

reg [1:0] rxd_r;

// Synchronize RXD input to clk
always @(posedge clk) begin
    if (rst)
        rxd_r <= 2'b11;
    else
        rxd_r <= {rxd_r[0], rxd};
end
    
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

wire [15:0] cnt_mid = prescale >> 1;
reg [7:0] data;

// Update data register
always @(posedge clk) begin
    if (state == DATA) begin
        if (baud_cnt == cnt_mid) 
            data[bit_idx] <= rxd_r[1];
    end
end

// Update valid register
always @(posedge clk) begin
    if (state == STOP && baud_cnt == cnt_mid) begin
        dout <= data;
        valid <= 1;
    end
    else 
        valid <= 0;
end

// Finite State Machine
always @(posedge clk) begin
    if (rst) begin
        state <= IDLE;
    end
    else begin
        case (state)
            IDLE: if (!rxd_r[1]) state <= START;
            START: begin
                if (baud_cnt < cnt_mid && rxd_r[1])
                    state <= IDLE;
                else if (baud_cnt == prescale)
                    state <= DATA;
            end
            DATA:
                if (baud_cnt == prescale && bit_idx == 3'h7)
                    state <= STOP;
            STOP: if (baud_cnt == cnt_mid) state <= IDLE;
        endcase
    end
end

endmodule