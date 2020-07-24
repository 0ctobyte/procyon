/* 
 * Copyright (c) 2019 Sekhar Bhattacharya
 *
 * SPDS-License-Identifier: MIT
 */

// Integer Execution Unit
// Encapsulates the ID and EX stages
// Writes the result of the EX stage to the CDB when it is available

`include "procyon_constants.svh"

module procyon_ieu #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_ROB_IDX_WIDTH = 5
)(
    input  logic                          clk,
    input  logic                          n_rst,

    input  logic                          i_flush,

    // Common Data Bus
    output logic                          o_cdb_en,
    output logic                          o_cdb_redirect,
    output logic [OPTN_DATA_WIDTH-1:0]    o_cdb_data,
    output logic [OPTN_ADDR_WIDTH-1:0]    o_cdb_addr,
    output logic [OPTN_ROB_IDX_WIDTH-1:0] o_cdb_tag,

    // Reservation station interface
    input  logic                          i_fu_valid,
    input  logic [`PCYN_OPCODE_WIDTH-1:0] i_fu_opcode,
    input  logic [OPTN_ADDR_WIDTH-1:0]    i_fu_iaddr,
    input  logic [OPTN_DATA_WIDTH-1:0]    i_fu_insn,
    input  logic [OPTN_DATA_WIDTH-1:0]    i_fu_src_a,
    input  logic [OPTN_DATA_WIDTH-1:0]    i_fu_src_b,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0] i_fu_tag,
    output logic                          o_fu_stall
);

    // ID -> EX pipeline registers
    logic [`PCYN_ALU_FUNC_WIDTH-1:0]  alu_func;
    logic [OPTN_DATA_WIDTH-1:0]       src_a;
    logic [OPTN_DATA_WIDTH-1:0]       src_b;
    logic [OPTN_ADDR_WIDTH-1:0]       iaddr;
    logic [OPTN_DATA_WIDTH-1:0]       imm_b;
    logic [`PCYN_ALU_SHAMT_WIDTH-1:0] shamt;
    logic [OPTN_ROB_IDX_WIDTH-1:0]    tag;
    logic                             jmp;
    logic                             br;
    logic                             valid;

    assign o_fu_stall = 1'b0;

    procyon_ieu_id #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_ROB_IDX_WIDTH(OPTN_ROB_IDX_WIDTH)
    ) procyon_ieu_id_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .i_opcode(i_fu_opcode),
        .i_iaddr(i_fu_iaddr),
        .i_insn(i_fu_insn),
        .i_src_a(i_fu_src_a),
        .i_src_b(i_fu_src_b),
        .i_tag(i_fu_tag),
        .i_valid(i_fu_valid),
        .o_alu_func(alu_func),
        .o_src_a(src_a),
        .o_src_b(src_b),
        .o_iaddr(iaddr),
        .o_imm_b(imm_b),
        .o_shamt(shamt),
        .o_tag(tag),
        .o_jmp(jmp),
        .o_br(br),
        .o_valid(valid)
    );

    procyon_ieu_ex #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_ROB_IDX_WIDTH(OPTN_ROB_IDX_WIDTH)
    ) procyon_ieu_ex_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .i_alu_func(alu_func),
        .i_src_a(src_a),
        .i_src_b(src_b),
        .i_iaddr(iaddr),
        .i_imm_b(imm_b),
        .i_shamt(shamt),
        .i_tag(tag),
        .i_jmp(jmp),
        .i_br(br),
        .i_valid(valid),
        .o_data(o_cdb_data),
        .o_addr(o_cdb_addr),
        .o_tag(o_cdb_tag),
        .o_redirect(o_cdb_redirect),
        .o_valid(o_cdb_en)
    );

endmodule
