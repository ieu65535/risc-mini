`timescale 1ns/1ps

module tb_trap_mix;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic timer_int = 1'b0;
    logic [31:0] inst = 32'h00000013;
    logic [31:0] inst_addr;
    logic [31:0] mem_dout;
    logic [31:0] mem_din;
    logic [31:0] mem_addr;
    logic [3:0] mem_we;
    logic [31:0] inst_mem [0:1023];
    string rom_path;
    string data_path;
    integer rom_words;
    integer data_words;
    integer cycles = 0;
    integer timer_traps = 0;
    integer ecall_traps = 0;
    integer ecall_timer_collisions = 0;
    integer pulses_sent = 0;
    logic [31:0] pulse_pc_hash = 32'd0;
    integer pulse_store_overlap = 0;
    integer pulse_load_overlap = 0;
    integer i;
    integer delay_cycles;
    logic [31:0] seed = 32'h2468ace0;
    logic [31:0] prng;

    pipeline dut (
        .clk(clk), .rst(rst), .timer_int(timer_int),
        .inst(inst), .mem_dout(mem_dout), .inst_addr(inst_addr),
        .mem_din(mem_din), .mem_addr(mem_addr), .mem_we(mem_we)
    );

    ram u_ram (
        .clk(clk), .addr(mem_addr), .din(mem_din),
        .we(mem_we), .dout(mem_dout)
    );

    always #5 clk = ~clk;
    always_ff @(posedge clk)
        inst <= inst_mem[inst_addr[11:2]];

    always @(posedge clk) begin
        if (rst)
            cycles <= 0;
        else begin
            cycles <= cycles + 1;
            if (cycles >= 20000)
                $fatal(1, "[TB TIMEOUT] tb_trap_mix exceeded 20000 cycles");
            if (inst_addr[31:12] !== 20'd0)
                $fatal(1, "[TB FAIL] fetch outside ROM: %h", inst_addr);
            if (timer_int) begin
                pulse_pc_hash <= {pulse_pc_hash[26:0], pulse_pc_hash[31:27]} ^ dut.pc_ex;
                if (dut.valid_ex && dut.mem_mask_ex != 4'b0000)
                    pulse_store_overlap <= pulse_store_overlap + 1;
                if (dut.valid_ex && dut.wb_sel_ex == 2'b01)
                    pulse_load_overlap <= pulse_load_overlap + 1;
            end
            if (dut.trap_valid) begin
                if (dut.trap_tval !== 32'd0)
                    $fatal(1, "[TB FAIL] unexpected mtval input: %h", dut.trap_tval);
                case (dut.trap_cause)
                    32'd11: begin
                        ecall_traps <= ecall_traps + 1;
                        if (timer_int)
                            ecall_timer_collisions <= ecall_timer_collisions + 1;
                    end
                    32'h80000007: timer_traps <= timer_traps + 1;
                    default: $fatal(1, "[TB FAIL] unexpected trap cause=%h pc=%h",
                                    dut.trap_cause, dut.pc_ex);
                endcase
            end
            if (dut.valid_ex && dut.mem_mask_ex != 4'b0000 &&
                (^mem_we) === 1'bx)
                $fatal(1, "[TB FAIL] unknown Store write enable");
            if ((|mem_we) === 1'b1) begin
                if (mem_addr[31:12] !== 20'h20000 ||
                    (^mem_addr[11:0]) === 1'bx)
                    $fatal(1, "[TB FAIL] Store outside RAM: %h", mem_addr);
                if (mem_addr[11:0] >= 12'hffc) begin
                    if (mem_addr !== 32'h20000ffc || mem_we !== 4'b1111)
                        $fatal(1, "[TB FAIL] malformed result Store: %h we=%b",
                               mem_addr, mem_we);
                    if (mem_din !== 32'd1)
                        $fatal(1, "[TB FAIL] software reported failure code=%h", mem_din);
                    if (pulses_sent != 18 || timer_traps != 18 ||
                        ecall_traps != 8 || ecall_timer_collisions < 1 ||
                        pulse_store_overlap < 1 || pulse_load_overlap < 1)
                        $fatal(1, "[TB FAIL] pulse=%0d timer=%0d ecall=%0d collision=%0d",
                               pulses_sent, timer_traps, ecall_traps,
                               ecall_timer_collisions);
                    if (u_ram.ram[0] !== 32'd64 ||
                        u_ram.ram[1] !== 32'd18 || u_ram.ram[2] !== 32'd8)
                        $fatal(1, "[TB FAIL] RAM counter=%h timer=%h ecall=%h",
                               u_ram.ram[0], u_ram.ram[1], u_ram.ram[2]);
                    $display("[TB PASS] tb_trap_mix seed=%h cycles=%0d timer=%0d ecall=%0d collision=%0d pc_hash=%h store_pulses=%0d load_pulses=%0d",
                             seed, cycles, timer_traps, ecall_traps,
                             ecall_timer_collisions, pulse_pc_hash,
                             pulse_store_overlap, pulse_load_overlap);
                    $finish;
                end
            end
        end
    end

    initial begin
        if (!$value$plusargs("ROM=%s", rom_path) ||
            !$value$plusargs("DATA=%s", data_path) ||
            !$value$plusargs("WORDS=%d", rom_words) ||
            !$value$plusargs("DATA_WORDS=%d", data_words))
            $fatal(1, "[TB FAIL] provide ROM, DATA, WORDS and DATA_WORDS");
        if (rom_words < 1 || rom_words > 1024 || data_words != 6)
            $fatal(1, "[TB FAIL] invalid image sizes ROM=%0d DATA=%0d",
                   rom_words, data_words);
        for (i = 0; i < 1024; i = i + 1) begin
            inst_mem[i] = 32'h00000013;
            u_ram.ram[i] = 32'h00000000;
        end
        $readmemh(rom_path, inst_mem, 0, rom_words - 1);
        $readmemh(data_path, u_ram.ram, 0, data_words - 1);
        repeat (3) @(negedge clk);
        rst = 1'b0;
    end

    initial begin
        if (!$value$plusargs("SEED=%h", seed))
            seed = 32'h2468ace0;
        prng = seed;
        wait (rst === 1'b0);
        wait (dut.csr_mstatus_mie === 1'b1 && dut.csr_mie_mtie === 1'b1);
        wait (dut.valid_ex && dut.is_ecall_ex);
        @(negedge clk);
        timer_int = 1'b1;
        pulses_sent = 1;
        @(negedge clk);
        timer_int = 1'b0;
        wait (timer_traps == 1);

        // Force one pulse onto a live Load EX slot while MIE is enabled.
        wait (dut.csr_mstatus_mie && dut.valid_ex && dut.wb_sel_ex == 2'b01);
        @(negedge clk);
        timer_int = 1'b1;
        pulses_sent = 2;
        @(negedge clk);
        timer_int = 1'b0;
        wait (timer_traps == 2);

        for (int pulse = 3; pulse <= 18; pulse = pulse + 1) begin
            prng = prng * 32'd1664525 + 32'd1013904223;
            delay_cycles = 1 + ((prng >> 16) & 7);
            repeat (delay_cycles) @(negedge clk);
            timer_int = 1'b1;
            pulses_sent = pulse;
            @(negedge clk);
            timer_int = 1'b0;
            wait (timer_traps == pulse);
        end
    end
endmodule
