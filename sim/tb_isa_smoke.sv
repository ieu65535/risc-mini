`timescale 1ns/1ps

module tb_isa_smoke;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [31:0] inst = 32'h00000013;
    logic [31:0] inst_addr;
    logic [31:0] mem_dout;
    logic [31:0] mem_din;
    logic [31:0] mem_addr;
    logic [3:0] mem_we;
    logic [31:0] inst_mem [0:1023];
    logic [31:0] expected_ram [0:1022];
    string rom_path;
    string data_path;
    string expected_path;
    string test_name;
    integer rom_words;
    integer data_words;
    integer expected_words = 0;
    integer max_cycles = 8000;
    integer cycles = 0;
    integer i;
    integer check_i;

    pipeline dut (
        .clk(clk), .rst(rst), .timer_int(1'b0),
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
            if (cycles >= max_cycles)
                $fatal(1, "[ISA TIMEOUT] %s exceeded %0d cycles", test_name, max_cycles);
            if (inst_addr[31:12] !== 20'd0)
                $fatal(1, "[ISA FAIL] %s fetched outside 4 KiB ROM: %h", test_name, inst_addr);
            if (dut.trap_valid)
                $fatal(1, "[ISA FAIL] %s unexpected trap cause=%h pc=%h",
                       test_name, dut.trap_cause, dut.pc_ex);
            if (dut.valid_ex && dut.mem_mask_ex != 4'b0000 &&
                (^mem_we) === 1'bx)
                $fatal(1, "[ISA FAIL] %s unknown Store write enable", test_name);
            if (dut.valid_ex && dut.wb_sel_ex == 2'b01 &&
                (mem_addr[31:12] !== 20'h20000 ||
                 (^mem_addr[11:0]) === 1'bx || mem_addr[11:0] >= 12'hffc))
                $fatal(1, "[ISA FAIL] %s Load outside data RAM: %h", test_name, mem_addr);
            if ((|mem_we) === 1'b1) begin
                if (mem_addr[31:12] !== 20'h20000 ||
                    (^mem_addr[11:0]) === 1'bx)
                    $fatal(1, "[ISA FAIL] %s Store outside data RAM: %h", test_name, mem_addr);
                if (mem_addr[11:0] >= 12'hffc) begin
                    if (mem_addr[11:0] != 12'hffc)
                        $fatal(1, "[ISA FAIL] %s Store overlaps result word: %h", test_name, mem_addr);
                    if (mem_we !== 4'b1111)
                        $fatal(1, "[ISA FAIL] %s result Store has wrong mask: %b", test_name, mem_we);
                    if (mem_din !== 32'd1)
                        $fatal(1, "[ISA FAIL] %s upstream subtest encoded failure=%h",
                               test_name, mem_din);
                    for (check_i = 0; check_i < expected_words; check_i = check_i + 1)
                        if (u_ram.ram[check_i] !== expected_ram[check_i])
                            $fatal(1, "[ISA FAIL] %s RAM[%0d]=%h expected=%h",
                                   test_name, check_i, u_ram.ram[check_i], expected_ram[check_i]);
                    $display("[TB PASS] tb_isa_smoke %s cycles=%0d", test_name, cycles);
                    $finish;
                end
            end
        end
    end

    initial begin
        if (!$value$plusargs("ROM=%s", rom_path) ||
            !$value$plusargs("TEST=%s", test_name) ||
            !$value$plusargs("WORDS=%d", rom_words) ||
            !$value$plusargs("DATA_WORDS=%d", data_words))
            $fatal(1, "[ISA FAIL] provide ROM, TEST, WORDS and DATA_WORDS");
        if (rom_words < 1 || rom_words > 1024)
            $fatal(1, "[ISA FAIL] invalid ROM word count %0d", rom_words);
        if (data_words < 0 || data_words > 1023)
            $fatal(1, "[ISA FAIL] invalid data RAM word count %0d", data_words);
        if ($value$plusargs("EXPECTED_WORDS=%d", expected_words) &&
            (expected_words < 0 || expected_words > 1023))
            $fatal(1, "[ISA FAIL] invalid expected RAM word count %0d", expected_words);
        if ($value$plusargs("MAX_CYCLES=%d", max_cycles) &&
            (max_cycles < 1 || max_cycles > 1000000))
            $fatal(1, "[ISA FAIL] invalid cycle limit %0d", max_cycles);
        for (i = 0; i < 1024; i = i + 1)
            inst_mem[i] = 32'h00000013;
        for (i = 0; i < 1024; i = i + 1)
            u_ram.ram[i] = 32'h00000000;
        $readmemh(rom_path, inst_mem, 0, rom_words - 1);
        if (data_words > 0) begin
            if (!$value$plusargs("DATA=%s", data_path))
                $fatal(1, "[ISA FAIL] provide +DATA=<hex> for nonempty data RAM");
            $readmemh(data_path, u_ram.ram, 0, data_words - 1);
        end
        if (expected_words > 0) begin
            if (!$value$plusargs("EXPECTED_RAM=%s", expected_path))
                $fatal(1, "[ISA FAIL] provide +EXPECTED_RAM=<hex>");
            $readmemh(expected_path, expected_ram, 0, expected_words - 1);
        end
        repeat (3) @(negedge clk);
        rst = 1'b0;
    end
endmodule
