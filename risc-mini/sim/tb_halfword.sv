`timescale 1ns/1ps

module tb_halfword;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [31:0] inst;
    logic [31:0] inst_addr;
    logic [31:0] mem_dout;
    logic [31:0] mem_din;
    logic [31:0] mem_addr;
    logic [3:0] mem_we;
    logic mem_en;
    logic [31:0] inst_mem [0:255];
    logic [31:0] data_mem [0:255];
    integer cycles = 0;
    integer trap_count = 0;
    integer store_count = 0;
    integer i;

    assign inst = inst_mem[inst_addr[9:2]];
    assign mem_dout = data_mem[mem_addr[9:2]];

    pipeline dut (
        .clk(clk), .rst(rst), .timer_int(1'b0),
        .inst(inst), .inst_ready(1'b1), .inst_addr(inst_addr),
        .mem_dout(mem_dout), .mem_ready(1'b1), .mem_en(mem_en),
        .mem_din(mem_din), .mem_addr(mem_addr), .mem_we(mem_we)
    );

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (mem_en) begin
            if (mem_we[0]) data_mem[mem_addr[9:2]][7:0]   <= mem_din[7:0];
            if (mem_we[1]) data_mem[mem_addr[9:2]][15:8]  <= mem_din[15:8];
            if (mem_we[2]) data_mem[mem_addr[9:2]][23:16] <= mem_din[23:16];
            if (mem_we[3]) data_mem[mem_addr[9:2]][31:24] <= mem_din[31:24];
        end
    end

    function automatic [31:0] load_inst(
        input [2:0] funct3, input [4:0] rd, input [4:0] rs1, input integer offset
    );
        load_inst = {offset[11:0], rs1, funct3, rd, 7'h03};
    endfunction

    function automatic [31:0] store_inst(
        input [2:0] funct3, input [4:0] rs2, input [4:0] rs1, input integer offset
    );
        store_inst = {offset[11:5], rs2, rs1, funct3, offset[4:0], 7'h23};
    endfunction

    function automatic [31:0] csrw(input [11:0] addr, input [4:0] rs1);
        csrw = {addr, rs1, 3'b001, 5'd0, 7'h73};
    endfunction

    function automatic [31:0] csrr(input [11:0] addr, input [4:0] rd);
        csrr = {addr, 5'd0, 3'b010, rd, 7'h73};
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            cycles <= 0;
            trap_count <= 0;
            store_count <= 0;
        end else begin
            cycles <= cycles + 1;
            if (cycles >= 260)
                $fatal(1, "[TB TIMEOUT] tb_halfword exceeded 260 cycles");
            if (dut.trap_valid) begin
                case (trap_count)
                    0: if (dut.trap_cause !== 32'd4 || dut.pc_ex !== 32'h30 ||
                           dut.trap_tval !== 32'h20000001)
                           $fatal(1, "[FAIL] LH misaligned");
                    1: if (dut.trap_cause !== 32'd4 || dut.pc_ex !== 32'h34 ||
                           dut.trap_tval !== 32'h20000003)
                           $fatal(1, "[FAIL] LHU misaligned");
                    2: if (dut.trap_cause !== 32'd6 || dut.pc_ex !== 32'h38 ||
                           dut.trap_tval !== 32'h20000001)
                           $fatal(1, "[FAIL] SH+1 misaligned");
                    3: if (dut.trap_cause !== 32'd6 || dut.pc_ex !== 32'h3c ||
                           dut.trap_tval !== 32'h20000003)
                           $fatal(1, "[FAIL] SH+3 misaligned");
                    default: $fatal(1, "[FAIL] unexpected extra trap");
                endcase
                if (mem_en || mem_we != 4'b0)
                    $fatal(1, "[FAIL] faulting access reached memory");
                trap_count <= trap_count + 1;
            end
            if (mem_en && |mem_we) begin
                if (store_count == 0 &&
                    (mem_addr !== 32'h20000000 || mem_we !== 4'b0011 ||
                     mem_din !== 32'h000080ff))
                    $fatal(1, "[FAIL] lower SH");
                if (store_count == 1 &&
                    (mem_addr !== 32'h20000002 || mem_we !== 4'b1100 ||
                     mem_din !== 32'h7f010000))
                    $fatal(1, "[FAIL] upper SH");
                if (store_count >= 2)
                    $fatal(1, "[FAIL] unexpected extra Store");
                store_count <= store_count + 1;
            end
        end
    end

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            inst_mem[i] = 32'h00000013;
            data_mem[i] = 32'h0;
        end
        data_mem[0] = 32'h80ff7f01;

        inst_mem[0]  = 32'h200000b7;
        inst_mem[1]  = 32'h10000793;
        inst_mem[2]  = csrw(12'h305, 5'd15);
        inst_mem[3]  = load_inst(3'b001, 5'd2, 5'd1, 0);
        inst_mem[4]  = load_inst(3'b101, 5'd3, 5'd1, 0);
        inst_mem[5]  = load_inst(3'b001, 5'd4, 5'd1, 2);
        inst_mem[6]  = load_inst(3'b101, 5'd5, 5'd1, 2);
        inst_mem[7]  = store_inst(3'b001, 5'd5, 5'd1, 0);
        inst_mem[8]  = store_inst(3'b001, 5'd2, 5'd1, 2);
        inst_mem[9]  = load_inst(3'b010, 5'd6, 5'd1, 0);
        inst_mem[10] = 32'h04d00413;
        inst_mem[11] = 32'h05800493;
        inst_mem[12] = load_inst(3'b001, 5'd8, 5'd1, 1);
        inst_mem[13] = load_inst(3'b101, 5'd9, 5'd1, 3);
        inst_mem[14] = store_inst(3'b001, 5'd5, 5'd1, 1);
        inst_mem[15] = store_inst(3'b001, 5'd2, 5'd1, 3);
        inst_mem[16] = load_inst(3'b010, 5'd10, 5'd1, 0);
        inst_mem[17] = 32'h00100593;
        inst_mem[18] = 32'h0000006f;

        inst_mem[64] = csrr(12'h342, 5'd20);
        inst_mem[65] = csrr(12'h341, 5'd21);
        inst_mem[66] = csrr(12'h343, 5'd22);
        inst_mem[67] = 32'h004a8a93;
        inst_mem[68] = csrw(12'h341, 5'd21);
        inst_mem[69] = 32'h30200073;

        repeat (3) @(negedge clk);
        rst = 1'b0;
        wait (dut.u_reg_file.regs[11] === 32'd1);
        repeat (3) @(negedge clk);

        if (dut.u_reg_file.regs[2] !== 32'h00007f01 ||
            dut.u_reg_file.regs[3] !== 32'h00007f01 ||
            dut.u_reg_file.regs[4] !== 32'hffff80ff ||
            dut.u_reg_file.regs[5] !== 32'h000080ff ||
            dut.u_reg_file.regs[6] !== 32'h7f0180ff ||
            dut.u_reg_file.regs[8] !== 32'd77 ||
            dut.u_reg_file.regs[9] !== 32'd88 ||
            dut.u_reg_file.regs[10] !== 32'h7f0180ff ||
            data_mem[0] !== 32'h7f0180ff || trap_count != 4 || store_count != 2)
            $fatal(1, "[FAIL] halfword result: x2=%h x3=%h x4=%h x5=%h x6=%h x10=%h RAM=%h trap=%0d store=%0d",
                   dut.u_reg_file.regs[2], dut.u_reg_file.regs[3],
                   dut.u_reg_file.regs[4], dut.u_reg_file.regs[5],
                   dut.u_reg_file.regs[6], dut.u_reg_file.regs[10],
                   data_mem[0], trap_count, store_count);

        $display("[TB PASS] tb_halfword");
        $finish;
    end
endmodule
