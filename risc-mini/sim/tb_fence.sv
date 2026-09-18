`timescale 1ns/1ps

module tb_fence;
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
    integer traps = 0;
    integer stores = 0;
    integer fences_retired = 0;
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
            if (mem_we[0]) data_mem[mem_addr[9:2]][7:0] <= mem_din[7:0];
            if (mem_we[1]) data_mem[mem_addr[9:2]][15:8] <= mem_din[15:8];
            if (mem_we[2]) data_mem[mem_addr[9:2]][23:16] <= mem_din[23:16];
            if (mem_we[3]) data_mem[mem_addr[9:2]][31:24] <= mem_din[31:24];
        end
    end

    function automatic [31:0] fence_inst(
        input [3:0] fm, input [3:0] pred, input [3:0] succ,
        input [4:0] rs1, input [4:0] rd
    );
        fence_inst = {fm, pred, succ, rs1, 3'b000, rd, 7'h0f};
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            cycles <= 0;
            traps <= 0;
            stores <= 0;
            fences_retired <= 0;
        end else begin
            cycles <= cycles + 1;
            if (cycles >= 200)
                $fatal(1, "[TB TIMEOUT] tb_fence");
            if (dut.valid_wb &&
                (dut.pc_wb == 32'h18 || dut.pc_wb == 32'h20 || dut.pc_wb == 32'h24))
                fences_retired <= fences_retired + 1;
            if (dut.trap_valid) begin
                if (dut.trap_cause !== 32'd2 || dut.pc_ex !== 32'h2c ||
                    dut.trap_tval !== 32'h0000100f || traps != 0 || mem_en)
                    $fatal(1, "[FAIL] FENCE.I trap cause=%h pc=%h tval=%h",
                           dut.trap_cause, dut.pc_ex, dut.trap_tval);
                traps <= traps + 1;
            end
            if (mem_en && |mem_we) begin
                if (stores != 0 || mem_addr !== 32'h20000000 ||
                    mem_we !== 4'b1111 || mem_din !== 32'h5a)
                    $fatal(1, "[FAIL] Store around FENCE");
                stores <= stores + 1;
            end
        end
    end

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            inst_mem[i] = 32'h00000013;
            data_mem[i] = 32'h0;
        end

        inst_mem[0]  = 32'h200000b7;
        inst_mem[1]  = 32'h10000793;
        inst_mem[2]  = 32'h30579073;
        inst_mem[3]  = 32'h05a00113;
        inst_mem[4]  = 32'h06600293;
        inst_mem[5]  = 32'h0020a023;
        inst_mem[6]  = fence_inst(4'h0, 4'h3, 4'h3, 5'd0, 5'd0);
        inst_mem[7]  = 32'h0000a183;
        inst_mem[8]  = fence_inst(4'h8, 4'h3, 4'h3, 5'd0, 5'd0);
        inst_mem[9]  = fence_inst(4'hf, 4'h3, 4'h3, 5'd6, 5'd5);
        inst_mem[10] = 32'h00700213;
        inst_mem[11] = 32'h0000100f;
        inst_mem[12] = 32'h00100393;
        inst_mem[13] = 32'h0000006f;

        inst_mem[64] = 32'h34202a73;
        inst_mem[65] = 32'h34102af3;
        inst_mem[66] = 32'h34302b73;
        inst_mem[67] = 32'h004a8a93;
        inst_mem[68] = 32'h341a9073;
        inst_mem[69] = 32'h30200073;

        repeat (3) @(negedge clk);
        rst = 1'b0;
        wait (dut.u_reg_file.regs[7] === 32'd1);
        repeat (3) @(negedge clk);
        if (traps != 1 || stores != 1 || fences_retired != 3 ||
            dut.u_reg_file.regs[3] !== 32'h5a || dut.u_reg_file.regs[4] !== 32'd7 ||
            dut.u_reg_file.regs[5] !== 32'h66 || dut.u_reg_file.regs[20] !== 32'd2 ||
            dut.u_reg_file.regs[21] !== 32'h30 || dut.u_reg_file.regs[22] !== 32'h0000100f ||
            data_mem[0] !== 32'h5a)
            $fatal(1, "[FAIL] FENCE result trap=%0d store=%0d retire=%0d",
                   traps, stores, fences_retired);

        $display("[TB PASS] tb_fence");
        $finish;
    end
endmodule
