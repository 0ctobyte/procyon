/* 
 * Copyright (c) 2019 Sekhar Bhattacharya
 *
 * SPDS-License-Identifier: MIT
 */

// Dispatch module
// Decodes and dispatches instructions over two cycles
// Cycle 1:
// * Decodes instruction
// * Renames destination register in Register Map and reserves and entry in the ROB
// * Lookup source register from the Register Map
// Cycle 2:
// * Registers reservation staton enqueue signals
// * Lookup source register in ROB and merges them with Register Map sources looked up in the previous cycle
// * Enqueue instruction in ROB

`include "procyon_constants.svh"

module procyon_dispatch #(
    parameter OPTN_DATA_WIDTH       = 32,
    parameter OPTN_ADDR_WIDTH       = 32,
    parameter OPTN_REGMAP_IDX_WIDTH = 5,
    parameter OPTN_ROB_IDX_WIDTH    = 5
)(
    input  logic                             clk,
    input  logic                             n_rst,

    input  logic                             i_flush,
    input  logic                             i_rob_stall,
    input  logic                             i_rs_stall,

    // Fetch interface
    input  logic [OPTN_ADDR_WIDTH-1:0]       i_dispatch_pc,
    input  logic [OPTN_DATA_WIDTH-1:0]       i_dispatch_insn,
    input  logic                             i_dispatch_valid,
    output logic                             o_dispatch_stall,

    // Register Map lookup interface
    output logic [OPTN_REGMAP_IDX_WIDTH-1:0] o_regmap_lookup_rsrc [0:1],
    output logic                             o_regmap_lookup_valid,

    // Register Map rename interface
    output logic [OPTN_REGMAP_IDX_WIDTH-1:0] o_regmap_rename_rdest,
    output logic                             o_regmap_rename_en,

    // ROB tag used to rename destination register in the Register Map
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]    i_rob_dst_tag,

    // Override ready signals when ROB looks up source registers
    output logic                             o_rob_lookup_rdy_ovrd [0:1],

    // ROB enqueue interface
    output logic                             o_rob_enq_en,
    output logic [`PCYN_ROB_OP_WIDTH-1:0]    o_rob_enq_op,
    output logic [OPTN_ADDR_WIDTH-1:0]       o_rob_enq_pc,
    output logic [OPTN_REGMAP_IDX_WIDTH-1:0] o_rob_enq_rdest,

    // Reservation Station enqueue interface
    output logic                             o_rs_en,
    output logic [`PCYN_OPCODE_WIDTH-1:0]    o_rs_opcode,
    output logic [OPTN_ADDR_WIDTH-1:0]       o_rs_pc,
    output logic [OPTN_DATA_WIDTH-1:0]       o_rs_insn,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]    o_rs_dst_tag
);

    logic                          rs_en;
    logic [`PCYN_OPCODE_WIDTH-1:0] rs_opcode;
    logic [OPTN_ADDR_WIDTH-1:0]    rs_pc;
    logic [OPTN_DATA_WIDTH-1:0]    rs_insn;
    logic [OPTN_ROB_IDX_WIDTH-1:0] rs_dst_tag;

    assign o_dispatch_stall = i_rob_stall;

    // Decode & Rename (first cycle)
    // - Decodes intstruction
    // - Look up source operands in Register Map (bypassing retired destination register if needed)
    // - Renames destination register of instruction
    procyon_dispatch_dr #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_REGMAP_IDX_WIDTH(OPTN_REGMAP_IDX_WIDTH),
        .OPTN_ROB_IDX_WIDTH(OPTN_ROB_IDX_WIDTH)
    ) procyon_dispatch_dr_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .i_rob_stall(i_rob_stall),
        .i_rs_stall(i_rs_stall),
        .i_dispatch_pc(i_dispatch_pc),
        .i_dispatch_insn(i_dispatch_insn),
        .i_dispatch_valid(i_dispatch_valid),
        .i_rob_dst_tag(i_rob_dst_tag),
        .o_regmap_lookup_rsrc(o_regmap_lookup_rsrc),
        .o_regmap_lookup_valid(o_regmap_lookup_valid),
        .o_regmap_rename_rdest(o_regmap_rename_rdest),
        .o_regmap_rename_en(o_regmap_rename_en),
        .o_rob_lookup_rdy_ovrd(o_rob_lookup_rdy_ovrd),
        .o_rob_enq_en(o_rob_enq_en),
        .o_rob_enq_pc(o_rob_enq_pc),
        .o_rob_enq_op(o_rob_enq_op),
        .o_rob_enq_rdest(o_rob_enq_rdest),
        .o_rs_en(rs_en),
        .o_rs_opcode(rs_opcode),
        .o_rs_pc(rs_pc),
        .o_rs_insn(rs_insn),
        .o_rs_dst_tag(rs_dst_tag)
    );

    // Map & Dispatch (second cycle)
    // - Take Register Map source operand lookup tags and lookup source operands in ROB (bypassing from CDB if needed)
    // - Enqueues instructions in Reorder Buffer
    procyon_dispatch_md #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_ROB_IDX_WIDTH(OPTN_ROB_IDX_WIDTH)
    ) procyon_dispatch_md_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .i_rob_stall(i_rob_stall),
        .i_rs_stall(i_rs_stall),
        .i_rs_en(rs_en),
        .i_rs_opcode(rs_opcode),
        .i_rs_pc(rs_pc),
        .i_rs_insn(rs_insn),
        .i_rs_dst_tag(rs_dst_tag),
        .o_rs_en(o_rs_en),
        .o_rs_opcode(o_rs_opcode),
        .o_rs_pc(o_rs_pc),
        .o_rs_insn(o_rs_insn),
        .o_rs_dst_tag(o_rs_dst_tag)
    );

endmodule
