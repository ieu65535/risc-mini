module io (
    input clk,
    input rst,
    input [31:0] addr,  //地址总线
    input [31:0] din,
    input wr,           //写使能
    output reg [31:0] dout,

    input rxd,
    output txd,
    output logic [7:0] led
);

// uart registers
reg [31:0] USR;   // 状态寄存器
reg [31:0] UDR;   // 数据寄存器
reg [31:0] UBRR;  // 波特率寄存器
reg [31:0] UCR1;  // 控制寄存器
//对应地址
//0x00:状态寄存器 0x04:数据寄存器 0x08:波特率寄存器 0x0C:控制寄存器

localparam RXNE = 5;  // 接收非空标志位
localparam TC   = 6;  // 发送完成标志位

// gpio registers
logic [31:0] PORTA;
assign led = PORTA[7:0];

// uart
wire [7:0] RDR; // 串口接收数据
wire valid;     // 接收有效标志位
wire busy;      // 串口忙标志位
reg  en;        // 串口发送使能

always @ (posedge clk) begin
    if (rst) begin
        en <= 0;
    end
    else en <= (wr && addr[7:0] == 8'h04)? 1 : 0;
    //同时判断是否有写使能和地址是否为数据寄存器地址
end

reg [31:0] next_USR;
always @(*) begin
    next_USR = USR;
    next_USR[TC] = !busy;

    if (valid)
        next_USR[RXNE] = 1'b1;
    if (addr[7:0] == 8'h04 && !wr)
        next_USR[RXNE] = 1'b0;
    if (wr && addr[7:0] == 8'h00)
        next_USR = din;
end

always @ (posedge clk) begin
    if (rst) begin
        USR <= 0;
        UDR <= 0;
        UBRR <= 0;
        UCR1 <= 0;
    end
    else begin
        USR <= next_USR;
        if (wr) begin
            case (addr[7:0])
                8'h04: UDR <= din;
                8'h08: UBRR <= din;
                8'h0C: UCR1 <= din;
                8'h20: PORTA <= din;
            endcase
        end
    end
end

always @ (posedge clk) begin
    case (addr[7:0])
        8'h00: dout <= USR;
        8'h04: dout <= {24'h0, RDR};
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