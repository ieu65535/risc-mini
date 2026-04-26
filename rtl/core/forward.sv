`include "micro.vh"

module forward(
    // ID stage
    input  logic [ 4:0] rs1_addr,
    input  logic [ 4:0] rs2_addr,
    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,

    // EX stage
    input  logic [ 4:0] rd_addr_ex,
    input  logic [ 1:0] wb_sel_ex,
    input  logic [31:0] alu_dout,
    input  logic [31:0] pc_ex,
    input  logic [31:0] csr_rdata_ex,

    // MEM stage
    input  logic [ 4:0] rd_addr_mem,
    input  logic [ 1:0] wb_sel_mem,
    input  logic [31:0] alu_dout_mem,
    input  logic [31:0] mem_data,
    input  logic [31:0] pc_mem,
    input  logic [31:0] csr_rdata_mem,

    // WB stage
    input  logic [ 4:0] rd_addr_wb,
    input  logic [31:0] rd_data,

    output logic [31:0] rs1,
    output logic [31:0] rs2
);

always_comb begin
    if (rs1_addr == 0) rs1 = 0;
    else begin
        if (rs1_addr == rd_addr_ex) begin
            case (wb_sel_ex)
                `WB_ALU: rs1 = alu_dout;
                `WB_MEM: rs1 = 0;
                `WB_PC4: rs1 = pc_ex + 4;
                `WB_CSR: rs1 = csr_rdata_ex;
                default: rs1 = 0;
            endcase
        end
        else begin
            if (rs1_addr == rd_addr_mem) begin
                case (wb_sel_mem)
                    `WB_ALU: rs1 = alu_dout_mem;
                    `WB_MEM: rs1 = mem_data;
                    `WB_PC4: rs1 = pc_mem + 4;
                    `WB_CSR: rs1 = csr_rdata_mem;
                    default: rs1 = 0;
                endcase
            end
            else begin
                if (rs1_addr == rd_addr_wb)
                    rs1 = rd_data;
                else
                    rs1 = rs1_data;
            end
        end
    end
end

always_comb begin
    if (rs2_addr == 0) rs2 = 0;
    else begin
        if (rs2_addr == rd_addr_ex) begin
            case (wb_sel_ex)
                `WB_ALU: rs2 = alu_dout;
                `WB_MEM: rs2 = 0;
                `WB_PC4: rs2 = pc_ex + 4;
                `WB_CSR: rs2 = csr_rdata_ex;
                default: rs2 = 0;
            endcase
        end
        else begin
            if (rs2_addr == rd_addr_mem) begin
                case (wb_sel_mem)
                    `WB_ALU: rs2 = alu_dout_mem;
                    `WB_MEM: rs2 = mem_data;
                    `WB_PC4: rs2 = pc_mem + 4;
                    `WB_CSR: rs2 = csr_rdata_mem;
                    default: rs2 = 0;
                endcase
            end
            else begin
                if (rs2_addr == rd_addr_wb)
                    rs2 = rd_data;
                else
                    rs2 = rs2_data;
            end
        end
    end
end

endmodule