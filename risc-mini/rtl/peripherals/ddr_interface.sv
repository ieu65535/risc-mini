module ddr_interface (
    input  logic         clk,
    input  logic         rst,
    input  logic         ddr_init_done,

    input  logic [31:0]  inst_addr,
    output logic [31:0]  inst_dout,
    output logic         inst_ready,

    input  logic [31:0]  data_addr,
    input  logic [31:0]  data_din,
    input  logic [ 3:0]  data_we,
    input  logic         data_en,
    output logic [31:0]  data_dout,
    output logic         data_ready,
    output logic         busy,

    output logic [27:0]  axi_awaddr,
    output logic         axi_awuser_ap,
    output logic [ 3:0]  axi_awuser_id,
    output logic [ 3:0]  axi_awlen,
    input  logic         axi_awready,
    output logic         axi_awvalid,

    output logic [255:0] axi_wdata,
    output logic [31:0]  axi_wstrb,
    input  logic         axi_wready,
    input  logic [ 3:0]  axi_wusero_id,
    input  logic         axi_wusero_last,

    output logic [27:0]  axi_araddr,
    output logic         axi_aruser_ap,
    output logic [ 3:0]  axi_aruser_id,
    output logic [ 3:0]  axi_arlen,
    input  logic         axi_arready,
    output logic         axi_arvalid,

    input  logic [255:0] axi_rdata,
    input  logic [ 3:0]  axi_rid,
    input  logic         axi_rlast,
    input  logic         axi_rvalid
);

// The DDR user address is a 32-bit-word address.  One AXI beat contains
// eight words (256 bits), so every request is aligned to a 32-byte line.
typedef enum logic [2:0] {
    IDLE,
    READ_ADDR,
    READ_DATA,
    WRITE_ADDR,
    WRITE_DATA
} state_t;

state_t state;

logic [31:0]  request_addr;
logic         request_is_inst;
logic [255:0] request_wdata;
logic [31:0]  request_wstrb;

logic         inst_line_valid;
logic [26:0]  inst_line_tag;
logic [255:0] inst_line_data;
logic         data_line_valid;
logic [26:0]  data_line_tag;
logic [255:0] data_line_data;
logic         write_done;

wire inst_hit = inst_line_valid && (inst_line_tag == inst_addr[31:5]);
wire data_hit = data_line_valid && (data_line_tag == data_addr[31:5]);

function automatic [31:0] select_word(
    input logic [255:0] line,
    input logic [2:0]   index
);
    begin
        case (index)
            3'd0: select_word = line[ 31:  0];
            3'd1: select_word = line[ 63: 32];
            3'd2: select_word = line[ 95: 64];
            3'd3: select_word = line[127: 96];
            3'd4: select_word = line[159:128];
            3'd5: select_word = line[191:160];
            3'd6: select_word = line[223:192];
            default: select_word = line[255:224];
        endcase
    end
endfunction

function automatic [255:0] place_word(
    input logic [31:0] word,
    input logic [2:0]  index
);
    begin
        place_word = 256'b0;
        case (index)
            3'd0: place_word[ 31:  0] = word;
            3'd1: place_word[ 63: 32] = word;
            3'd2: place_word[ 95: 64] = word;
            3'd3: place_word[127: 96] = word;
            3'd4: place_word[159:128] = word;
            3'd5: place_word[191:160] = word;
            3'd6: place_word[223:192] = word;
            3'd7: place_word[255:224] = word;
        endcase
    end
endfunction

function automatic [31:0] place_strobe(
    input logic [3:0] strobe,
    input logic [2:0] index
);
    begin
        place_strobe = 32'b0;
        case (index)
            3'd0: place_strobe[ 3: 0] = strobe;
            3'd1: place_strobe[ 7: 4] = strobe;
            3'd2: place_strobe[11: 8] = strobe;
            3'd3: place_strobe[15:12] = strobe;
            3'd4: place_strobe[19:16] = strobe;
            3'd5: place_strobe[23:20] = strobe;
            3'd6: place_strobe[27:24] = strobe;
            3'd7: place_strobe[31:28] = strobe;
        endcase
    end
endfunction

always @(*) begin
    inst_dout = inst_hit ? select_word(inst_line_data, inst_addr[4:2]) : 32'h0000_0013;
    inst_ready = ddr_init_done && inst_hit;
    data_dout = data_hit ? select_word(data_line_data, data_addr[4:2]) : 32'b0;
    data_ready = ddr_init_done && data_en &&
                 ((|data_we) ? write_done : data_hit);

    axi_awaddr    = {request_addr[29:5], 3'b000};
    axi_awuser_ap = 1'b0;
    axi_awuser_id = 4'b0;
    axi_awlen     = 4'b0;
    axi_awvalid   = (state == WRITE_ADDR);

    axi_wdata     = request_wdata;
    axi_wstrb     = request_wstrb;

    axi_araddr    = {request_addr[29:5], 3'b000};
    axi_aruser_ap = 1'b0;
    axi_aruser_id = 4'b0;
    axi_arlen     = 4'b0;
    axi_arvalid   = (state == READ_ADDR);

    busy = !ddr_init_done || !inst_hit || (state != IDLE) ||
           (data_en && !data_ready);
end

integer byte_index;
always_ff @(posedge clk) begin
    if (rst) begin
        state            <= IDLE;
        request_addr     <= 32'b0;
        request_is_inst  <= 1'b0;
        request_wdata    <= 256'b0;
        request_wstrb    <= 32'b0;
        inst_line_valid  <= 1'b0;
        inst_line_tag    <= 27'b0;
        inst_line_data   <= 256'b0;
        data_line_valid  <= 1'b0;
        data_line_tag    <= 27'b0;
        data_line_data   <= 256'b0;
        write_done       <= 1'b0;
    end else begin
        // A completed write is acknowledged for one cycle.  The idle cycle
        // after it prevents a request held by the CPU from being issued twice.
        write_done <= 1'b0;
        case (state)
            IDLE: begin
                if (ddr_init_done) begin
                    // Instruction fetch has priority so sequential execution can
                    // benefit from the 32-byte instruction line buffer.
                    if (!inst_hit) begin
                        request_addr    <= inst_addr;
                        request_is_inst <= 1'b1;
                        state           <= READ_ADDR;
                    end else if (data_en && (|data_we) && !write_done) begin
                        request_addr    <= data_addr;
                        request_is_inst <= 1'b0;
                        request_wdata   <= place_word(data_din, data_addr[4:2]);
                        request_wstrb   <= place_strobe(data_we, data_addr[4:2]);
                        state           <= WRITE_ADDR;
                    end else if (data_en && !data_hit) begin
                        request_addr    <= data_addr;
                        request_is_inst <= 1'b0;
                        state           <= READ_ADDR;
                    end
                end
            end

            READ_ADDR: begin
                if (axi_arready)
                    state <= READ_DATA;
            end

            READ_DATA: begin
                if (axi_rvalid) begin
                    if (request_is_inst) begin
                        inst_line_valid <= 1'b1;
                        inst_line_tag   <= request_addr[31:5];
                        inst_line_data  <= axi_rdata;
                    end else begin
                        data_line_valid <= 1'b1;
                        data_line_tag   <= request_addr[31:5];
                        data_line_data  <= axi_rdata;
                    end
                    state <= IDLE;
                end
            end

            WRITE_ADDR: begin
                if (axi_awready)
                    state <= WRITE_DATA;
            end

            WRITE_DATA: begin
                if (axi_wready) begin
                    // Keep either buffered copy coherent with a completed write.
                    if (inst_line_valid && (inst_line_tag == request_addr[31:5])) begin
                        for (byte_index = 0; byte_index < 32; byte_index = byte_index + 1)
                            if (request_wstrb[byte_index])
                                inst_line_data[byte_index*8 +: 8] <= request_wdata[byte_index*8 +: 8];
                    end
                    if (data_line_valid && (data_line_tag == request_addr[31:5])) begin
                        for (byte_index = 0; byte_index < 32; byte_index = byte_index + 1)
                            if (request_wstrb[byte_index])
                                data_line_data[byte_index*8 +: 8] <= request_wdata[byte_index*8 +: 8];
                    end
                    write_done <= 1'b1;
                    state <= IDLE;
                end
            end

            default: state <= IDLE;
        endcase
    end
end

// These return-side metadata signals are unused for single-beat, ID-zero requests.
wire unused_axi_return = &{1'b0, axi_wusero_id, axi_wusero_last,
                           axi_rid, axi_rlast};

endmodule
