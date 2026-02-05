module io (
    input clk,
    input rst,
    input [31:0] addr,
    input [31:0] din,
    input wr,
    output reg [31:0] dout
);

// uart registers
reg [31:0] USR;
reg [31:0] UDR;
reg [31:0] UBRR;
reg [31:0] UCR1;

localparam RXNE = 5;
localparam TC   = 6;

// gpio registers
reg [31:0] PORTA;

// uart
wire [7:0] RDR;
wire valid;
wire busy;
reg  en;

always @ (posedge clk) begin
    if (rst) begin
        en <= 0;
    end
    else en <= (wr && addr[7:0] == 8'h04)? 1 : 0;
end

always @ (posedge clk) begin
    if (valid)
        USR[RXNE] <= 1;
end

always @ (posedge clk) begin
    USR[TC] <= !busy;
end

always @ (posedge clk) begin
    if (rst) begin
        USR <= 0;
        UDR <= 0;
        UBRR <= 0;
        UCR1 <= 0;
    end
    else if (wr) begin
        case (addr[7:0])
            8'h00: USR <= din;
            8'h04: UDR <= din;
            8'h08: UBRR <= din;
            8'h0C: UCR1 <= din;
        endcase
    end
end

always @ (posedge clk) begin
    case (addr[7:0])
        8'h00: dout <= USR;
        8'h04: begin
            dout <= {24'h0, RDR};
            USR[RXNE] <= 0;
        end
        
        8'h08: dout <= UBRR;
        8'h0C: dout <= UCR1;
    endcase
end

uart_tx u_uart_tx(
    .clk      (clk      ),
    .rst      (rst      ),
    .en       (en       ),
    .prescale (UBRR[15:0] ),
    .din      (UDR[7:0] ),
    .txd      (txd      ),
    .busy     (busy     )
);

uart_rx u_uart_rx(
    .clk      (clk      ),
    .rst      (rst      ),
    .rxd      (rxd      ),
    .prescale (UBRR[15:0] ),
    .dout     (RDR      ),
    .valid    (valid    )
);

`ifdef SIMULATION
initial begin
	$dumpvars(1, wr, addr);
end
`endif

endmodule