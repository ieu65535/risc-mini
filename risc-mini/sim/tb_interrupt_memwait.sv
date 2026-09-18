`timescale 1ns/1ps

module tb_interrupt_memwait;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic timer_int = 1'b0;
    logic [31:0] inst;
    logic [31:0] inst_addr;
    logic [31:0] inst_mem [0:255];
    logic [31:0] data_mem [0:255];
    logic [31:0] mem_dout = 32'b0;
    logic mem_ready = 1'b0;
    logic mem_en;
    logic [31:0] mem_din;
    logic [31:0] mem_addr;
    logic [3:0] mem_we;
    logic pending = 1'b0;
    logic [2:0] delay_count = 3'b0;
    logic [31:0] saved_addr;
    logic [31:0] saved_din;
    logic [3:0] saved_we;
    integer request_count = 0;
    integer write_count = 0;
    integer timer_traps = 0;
    integer cycles = 0;
    integer i;

    assign inst = inst_mem[inst_addr[9:2]];

    pipeline dut (
        .clk(clk), .rst(rst), .timer_int(timer_int),
        .inst(inst), .inst_ready(1'b1), .inst_addr(inst_addr),
        .mem_dout(mem_dout), .mem_ready(mem_ready), .mem_en(mem_en),
        .mem_din(mem_din), .mem_addr(mem_addr), .mem_we(mem_we)
    );

    always #5 clk = ~clk;

    // 四拍延迟的单事务从设备，用来模拟 DDR 控制器等待。
    always_ff @(posedge clk) begin
        mem_ready <= 1'b0;
        if (rst) begin
            pending <= 1'b0;
            request_count <= 0;
            write_count <= 0;
        end else if (mem_ready) begin
            // 避免在响应边沿重新接收仍保持的请求。
        end else if (!pending && mem_en) begin
            pending <= 1'b1;
            delay_count <= 3'd3;
            saved_addr <= mem_addr;
            saved_din <= mem_din;
            saved_we <= mem_we;
            request_count <= request_count + 1;
        end else if (pending && delay_count != 0) begin
            delay_count <= delay_count - 1'b1;
        end else if (pending) begin
            if (saved_we == 4'b0)
                mem_dout <= data_mem[saved_addr[9:2]];
            else begin
                if (saved_we[0]) data_mem[saved_addr[9:2]][7:0] <= saved_din[7:0];
                if (saved_we[1]) data_mem[saved_addr[9:2]][15:8] <= saved_din[15:8];
                if (saved_we[2]) data_mem[saved_addr[9:2]][23:16] <= saved_din[23:16];
                if (saved_we[3]) data_mem[saved_addr[9:2]][31:24] <= saved_din[31:24];
                write_count <= write_count + 1;
            end
            pending <= 1'b0;
            mem_ready <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            cycles <= 0;
            timer_traps <= 0;
        end else begin
            cycles <= cycles + 1;
            if (cycles >= 180)
                $fatal(1, "[TB TIMEOUT] tb_interrupt_memwait");
            if (dut.trap_valid) begin
                if (dut.trap_cause !== 32'h80000007)
                    $fatal(1, "[FAIL] unexpected trap cause=%h", dut.trap_cause);
                timer_traps <= timer_traps + 1;
            end
            if (dut.mem_inflight && dut.trap_valid)
                $fatal(1, "[FAIL] interrupt taken before DDR transaction completed");
        end
    end

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            inst_mem[i] = 32'h00000013;
            data_mem[i] = 32'h0;
        end

        inst_mem[0]  = 32'h08000513; // x10=0x80, mtvec
        inst_mem[1]  = 32'h30551073;
        inst_mem[2]  = 32'h00800593; // mstatus.MIE
        inst_mem[3]  = 32'h3005a073;
        inst_mem[4]  = 32'h08000593; // mie.MTIE
        inst_mem[5]  = 32'h3045a073;
        inst_mem[6]  = 32'h04000093; // x1=0x40
        inst_mem[7]  = 32'h05500113; // x2=0x55
        inst_mem[8]  = 32'h0020a023; // 0x20: sw x2,0(x1)
        inst_mem[9]  = 32'h00100193; // 0x24: 必须在 MRET 后执行
        inst_mem[10] = 32'h0000006f;

        inst_mem[32] = 32'h34202273; // 0x80: mcause -> x4
        inst_mem[33] = 32'h341022f3; // mepc -> x5
        inst_mem[34] = 32'h30200073; // mret，不修改异步中断 mepc

        repeat (4) @(posedge clk);
        rst <= 1'b0;

        wait (dut.mem_inflight && pending);
        @(negedge clk);
        timer_int = 1'b1;
        @(negedge clk);
        timer_int = 1'b0;

        wait (dut.u_reg_file.regs[3] === 32'd1);
        repeat (5) @(posedge clk);

        if (request_count != 1 || write_count != 1 || data_mem[16] !== 32'h55 ||
            timer_traps != 1 || dut.u_reg_file.regs[4] !== 32'h80000007 ||
            dut.u_reg_file.regs[5] !== 32'h24 || dut.csr_mip_mtip)
            $fatal(1, "[FAIL] memwait interrupt req=%0d write=%0d data=%h traps=%0d cause=%h mepc=%h pending=%b",
                   request_count, write_count, data_mem[16], timer_traps,
                   dut.u_reg_file.regs[4], dut.u_reg_file.regs[5], dut.csr_mip_mtip);

        $display("[TB PASS] tb_interrupt_memwait");
        $finish;
    end
endmodule
