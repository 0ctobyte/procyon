// Integer Execution Unit - Decode Stage

`include "procyon_constants.svh"

module ieu_id #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_ROB_IDX_WIDTH = 5

)(
    input  logic                             clk,
    input  logic                             n_rst,

    input  logic                             i_flush,

    input  logic [`PCYN_OPCODE_WIDTH-1:0]    i_opcode,
    input  logic [OPTN_ADDR_WIDTH-1:0]       i_iaddr,
/* verilator lint_off UNUSED */
    input  logic [OPTN_DATA_WIDTH-1:0]       i_insn,
/* verilator lint_on  UNUSED */
    input  logic [OPTN_DATA_WIDTH-1:0]       i_src_a,
    input  logic [OPTN_DATA_WIDTH-1:0]       i_src_b,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]    i_tag,
    input                                    i_valid,

    output logic [`PCYN_ALU_FUNC_WIDTH-1:0]  o_alu_func,
    output logic [OPTN_DATA_WIDTH-1:0]       o_src_a,
    output logic [OPTN_DATA_WIDTH-1:0]       o_src_b,
    output logic [OPTN_ADDR_WIDTH-1:0]       o_iaddr,
    output logic [OPTN_DATA_WIDTH-1:0]       o_imm_b,
    output logic [`PCYN_ALU_SHAMT_WIDTH-1:0] o_shamt,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]    o_tag,
    output logic                             o_jmp,
    output logic                             o_br,
    output logic                             o_valid
);

    logic [OPTN_DATA_WIDTH-1:0]      imm_i;
    logic [OPTN_DATA_WIDTH-1:0]      imm_b;
    logic [OPTN_DATA_WIDTH-1:0]      imm_u;
    logic [OPTN_DATA_WIDTH-1:0]      imm_j;
    logic [OPTN_DATA_WIDTH-1:0]      src_a_data_mux;
    logic [OPTN_DATA_WIDTH-1:0]      src_b_data_mux;
    logic [`PCYN_ALU_FUNC_WIDTH-1:0] alu_func_srx;
    logic [`PCYN_ALU_FUNC_WIDTH-1:0] alu_func_asx;
    logic [`PCYN_ALU_FUNC_WIDTH-1:0] alu_func;
    logic [1:0]                      alu_func_sel;
    logic                            is_br;
    logic                            is_jal;
    logic                            is_jalr;
    logic                            is_op;
    logic                            is_opimm;
    logic                            is_lui;
    logic                            is_auipc;

    assign is_br        = i_opcode == `PCYN_OPCODE_BRANCH;
    assign is_jal       = i_opcode == `PCYN_OPCODE_JAL;
    assign is_jalr      = i_opcode == `PCYN_OPCODE_JALR;
    assign is_op        = i_opcode == `PCYN_OPCODE_OP;
    assign is_opimm     = i_opcode == `PCYN_OPCODE_OPIMM;
    assign is_lui       = i_opcode == `PCYN_OPCODE_LUI;
    assign is_auipc     = i_opcode == `PCYN_OPCODE_AUIPC;

    assign alu_func_sel = {is_br, is_op | is_opimm};

    // Determine ALU FUNC for certain ops depending on instruction bit 30
    assign alu_func_srx = i_insn[30] ? `PCYN_ALU_FUNC_SRA : `PCYN_ALU_FUNC_SRL;
    assign alu_func_asx = i_insn[30] ? `PCYN_ALU_FUNC_SUB : `PCYN_ALU_FUNC_ADD;

    // Generate immediates
    assign imm_i        = {{(OPTN_DATA_WIDTH-11){i_insn[31]}}, i_insn[30:25], i_insn[24:21], i_insn[20]};
    assign imm_b        = {{(OPTN_DATA_WIDTH-12){i_insn[31]}}, i_insn[7], i_insn[30:25], i_insn[11:8], 1'b0};
    assign imm_u        = {{(OPTN_DATA_WIDTH-31){i_insn[31]}}, i_insn[30:25], i_insn[24:21], i_insn[20], i_insn[19:12], {12{1'b0}}};
    assign imm_j        = {{(OPTN_DATA_WIDTH-20){i_insn[31]}}, i_insn[19:12], i_insn[20], i_insn[30:25], i_insn[24:21], 1'b0};

    function logic [3:0] mux4_4b (
        input logic [3:0] i_data0,
        input logic [3:0] i_data1,
        input logic [3:0] i_data2,
        input logic [3:0] i_data3,
        input logic [1:0] i_sel
    );

        case (i_sel)
            2'b00: mux4_4b = i_data0;
            2'b01: mux4_4b = i_data1;
            2'b10: mux4_4b = i_data2;
            2'b11: mux4_4b = i_data3;
        endcase
    endfunction

    // Decode based on opcode and funct3 fields
    always_comb begin
        case (i_insn[14:12])
            3'b000: alu_func = mux4_4b(`PCYN_ALU_FUNC_ADD, alu_func_asx, `PCYN_ALU_FUNC_EQ, `PCYN_ALU_FUNC_ADD, {is_br, is_op});
            3'b001: alu_func = mux4_4b(`PCYN_ALU_FUNC_ADD, `PCYN_ALU_FUNC_SLL, `PCYN_ALU_FUNC_NE, `PCYN_ALU_FUNC_ADD, alu_func_sel);
            3'b010: alu_func = is_op | is_opimm ? `PCYN_ALU_FUNC_LT : `PCYN_ALU_FUNC_ADD;
            3'b011: alu_func = is_op | is_opimm ? `PCYN_ALU_FUNC_LTU : `PCYN_ALU_FUNC_ADD;
            3'b100: alu_func = mux4_4b(`PCYN_ALU_FUNC_ADD, `PCYN_ALU_FUNC_XOR, `PCYN_ALU_FUNC_LT, `PCYN_ALU_FUNC_ADD, alu_func_sel);
            3'b101: alu_func = mux4_4b(`PCYN_ALU_FUNC_ADD, alu_func_srx, `PCYN_ALU_FUNC_GE, `PCYN_ALU_FUNC_ADD, alu_func_sel);
            3'b110: alu_func = mux4_4b(`PCYN_ALU_FUNC_ADD, `PCYN_ALU_FUNC_OR, `PCYN_ALU_FUNC_LTU, `PCYN_ALU_FUNC_ADD, alu_func_sel);
            3'b111: alu_func = mux4_4b(`PCYN_ALU_FUNC_ADD, `PCYN_ALU_FUNC_AND, `PCYN_ALU_FUNC_GEU, `PCYN_ALU_FUNC_ADD, alu_func_sel);
        endcase
    end

    always_comb begin
        logic [1:0] src_a_data_sel;
        logic [1:0] src_b_data_sel;

        src_a_data_sel = {is_auipc | is_jal, is_lui};
        src_b_data_sel = {is_op | is_br, is_opimm | is_jalr};
        case (src_a_data_sel)
            2'b00: src_a_data_mux = i_src_a;
            2'b01: src_a_data_mux = {(OPTN_DATA_WIDTH){1'b0}};
            2'b10: src_a_data_mux = i_iaddr;
            2'b11: src_a_data_mux = i_src_a;
        endcase

        case (src_b_data_sel)
            2'b00: src_b_data_mux = is_jal ? imm_j : imm_u;
            2'b01: src_b_data_mux = imm_i;
            2'b10: src_b_data_mux = i_src_b;
            2'b11: src_b_data_mux = i_src_b;
        endcase
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_valid <= 1'b0;
        else        o_valid <= ~i_flush & i_valid;
    end

    always_ff @(posedge clk) begin
        o_alu_func <= alu_func;
        o_src_a    <= src_a_data_mux;
        o_src_b    <= src_b_data_mux;
        o_iaddr    <= i_iaddr;
        o_imm_b    <= imm_b;
        o_shamt    <= is_op ? i_src_b[4:0] : i_insn[24:20];
        o_tag      <= i_tag;
        o_jmp      <= is_jal | is_jalr;
        o_br       <= is_br & (i_insn[14:12] != 3'b010) & (i_insn[14:12] != 3'b011);
    end

endmodule
