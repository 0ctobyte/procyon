/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Integer Execution Unit - Decode Stage

`include "procyon_constants.svh"

module procyon_ieu_id #(
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

    // opcode comparators
    logic is_br;
    logic is_jal;
    logic is_jalr;
    logic is_op;
    logic is_opimm;
    logic is_lui;
    logic is_auipc;

    assign is_br = i_opcode == `PCYN_OPCODE_BRANCH;
    assign is_jal = i_opcode == `PCYN_OPCODE_JAL;
    assign is_jalr = i_opcode == `PCYN_OPCODE_JALR;
    assign is_op = i_opcode == `PCYN_OPCODE_OP;
    assign is_opimm = i_opcode == `PCYN_OPCODE_OPIMM;
    assign is_lui = i_opcode == `PCYN_OPCODE_LUI;
    assign is_auipc = i_opcode == `PCYN_OPCODE_AUIPC;

    procyon_ff #(OPTN_ADDR_WIDTH) o_iaddr_ff (.clk(clk), .i_en(1'b1), .i_d(i_iaddr), .o_q(o_iaddr));
    procyon_ff #(OPTN_ROB_IDX_WIDTH) o_tag_ff (.clk(clk), .i_en(1'b1), .i_d(i_tag), .o_q(o_tag));

    logic [OPTN_DATA_WIDTH-1:0] imm_b;
    assign imm_b = {{(OPTN_DATA_WIDTH-12){i_insn[31]}}, i_insn[7], i_insn[30:25], i_insn[11:8], 1'b0};
    procyon_ff #(OPTN_DATA_WIDTH) o_imm_b_ff (.clk(clk), .i_en(1'b1), .i_d(imm_b), .o_q(o_imm_b));

    logic [`PCYN_ALU_SHAMT_WIDTH-1:0] shamt;
    assign shamt = is_op ? i_src_b[4:0] : i_insn[24:20];
    procyon_ff #(`PCYN_ALU_SHAMT_WIDTH) o_shamt_ff (.clk(clk), .i_en(1'b1), .i_d(shamt), .o_q(o_shamt));

    logic jmp;
    assign jmp = is_jal | is_jalr;
    procyon_ff #(1) o_jmp_ff (.clk(clk), .i_en(1'b1), .i_d(jmp), .o_q(o_jmp));

    logic br;
    assign br = is_br & (i_insn[14:12] != 3'b010) & (i_insn[14:12] != 3'b011);
    procyon_ff #(1) o_br_ff (.clk(clk), .i_en(1'b1), .i_d(br), .o_q(o_br));

    logic valid;
    assign valid = ~i_flush & i_valid;
    procyon_srff #(1) o_valid_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(valid), .i_reset(1'b0), .o_q(o_valid));

    // Decode based on opcode and funct3 fields
    logic [`PCYN_ALU_FUNC_WIDTH-1:0] alu_func_mux;

    always_comb begin
        logic [1:0] alu_func_sel;
        logic [`PCYN_ALU_FUNC_WIDTH-1:0] alu_func_srx_mux;
        logic [`PCYN_ALU_FUNC_WIDTH-1:0] alu_func_asx_mux;

        alu_func_sel = {is_br, is_op | is_opimm};

        // Determine ALU FUNC for certain ops depending on instruction bit 30
        alu_func_srx_mux = i_insn[30] ? `PCYN_ALU_FUNC_SRA : `PCYN_ALU_FUNC_SRL;
        alu_func_asx_mux = i_insn[30] ? `PCYN_ALU_FUNC_SUB : `PCYN_ALU_FUNC_ADD;

        case (i_insn[14:12])
            3'b000: alu_func_mux = mux4_4b(`PCYN_ALU_FUNC_ADD, alu_func_asx_mux, `PCYN_ALU_FUNC_EQ, `PCYN_ALU_FUNC_ADD, {is_br, is_op});
            3'b001: alu_func_mux = mux4_4b(`PCYN_ALU_FUNC_ADD, `PCYN_ALU_FUNC_SLL, `PCYN_ALU_FUNC_NE, `PCYN_ALU_FUNC_ADD, alu_func_sel);
            3'b010: alu_func_mux = is_op | is_opimm ? `PCYN_ALU_FUNC_LT : `PCYN_ALU_FUNC_ADD;
            3'b011: alu_func_mux = is_op | is_opimm ? `PCYN_ALU_FUNC_LTU : `PCYN_ALU_FUNC_ADD;
            3'b100: alu_func_mux = mux4_4b(`PCYN_ALU_FUNC_ADD, `PCYN_ALU_FUNC_XOR, `PCYN_ALU_FUNC_LT, `PCYN_ALU_FUNC_ADD, alu_func_sel);
            3'b101: alu_func_mux = mux4_4b(`PCYN_ALU_FUNC_ADD, alu_func_srx_mux, `PCYN_ALU_FUNC_GE, `PCYN_ALU_FUNC_ADD, alu_func_sel);
            3'b110: alu_func_mux = mux4_4b(`PCYN_ALU_FUNC_ADD, `PCYN_ALU_FUNC_OR, `PCYN_ALU_FUNC_LTU, `PCYN_ALU_FUNC_ADD, alu_func_sel);
            3'b111: alu_func_mux = mux4_4b(`PCYN_ALU_FUNC_ADD, `PCYN_ALU_FUNC_AND, `PCYN_ALU_FUNC_GEU, `PCYN_ALU_FUNC_ADD, alu_func_sel);
        endcase
    end

    procyon_ff #(`PCYN_ALU_FUNC_WIDTH) o_alu_func_ff (.clk(clk), .i_en(1'b1), .i_d(alu_func_mux), .o_q(o_alu_func));

    // First source data mux
    logic [OPTN_DATA_WIDTH-1:0] src_a_data_mux;

    always_comb begin
        logic [1:0] src_a_data_sel;
        src_a_data_sel = {is_auipc | is_jal, is_lui};

        case (src_a_data_sel)
            2'b00: src_a_data_mux = i_src_a;
            2'b01: src_a_data_mux = '0;
            2'b10: src_a_data_mux = i_iaddr;
            2'b11: src_a_data_mux = i_src_a;
        endcase
    end

    procyon_ff #(OPTN_DATA_WIDTH) o_src_a_ff (.clk(clk), .i_en(1'b1), .i_d(src_a_data_mux), .o_q(o_src_a));

    // Second source data mux
    logic [OPTN_DATA_WIDTH-1:0] src_b_data_mux;

    always_comb begin
        logic [1:0] src_b_data_sel;
        logic [OPTN_DATA_WIDTH-1:0] imm_i;
        logic [OPTN_DATA_WIDTH-1:0] imm_u;
        logic [OPTN_DATA_WIDTH-1:0] imm_j;

        // Generate immediates
        imm_i = {{(OPTN_DATA_WIDTH-11){i_insn[31]}}, i_insn[30:25], i_insn[24:21], i_insn[20]};
        imm_u = {{(OPTN_DATA_WIDTH-31){i_insn[31]}}, i_insn[30:25], i_insn[24:21], i_insn[20], i_insn[19:12], {12{1'b0}}};
        imm_j = {{(OPTN_DATA_WIDTH-20){i_insn[31]}}, i_insn[19:12], i_insn[20], i_insn[30:25], i_insn[24:21], 1'b0};

        src_b_data_sel = {is_op | is_br, is_opimm | is_jalr};

        case (src_b_data_sel)
            2'b00: src_b_data_mux = is_jal ? imm_j : imm_u;
            2'b01: src_b_data_mux = imm_i;
            2'b10: src_b_data_mux = i_src_b;
            2'b11: src_b_data_mux = i_src_b;
        endcase
    end

    procyon_ff #(OPTN_DATA_WIDTH) o_src_b_ff (.clk(clk), .i_en(1'b1), .i_d(src_b_data_mux), .o_q(o_src_b));

endmodule
