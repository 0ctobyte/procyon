/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// LSU dcache hit check & write data stage

`include "procyon_constants.svh"

module procyon_lsu_dw #(
    parameter OPTN_DATA_WIDTH      = 32,
    parameter OPTN_ADDR_WIDTH      = 32,
    parameter OPTN_LQ_DEPTH        = 8,
    parameter OPTN_SQ_DEPTH        = 8,
    parameter OPTN_ROB_IDX_WIDTH   = 5,
    parameter OPTN_DC_OFFSET_WIDTH = 5
)(
    input  logic                                          clk,
    input  logic                                          n_rst,

    input  logic                                          i_flush,

    // Fill interface to check for fill address conflicts
    input  logic                                          i_mhq_fill_en,
    input  logic [OPTN_ADDR_WIDTH-1:OPTN_DC_OFFSET_WIDTH] i_mhq_fill_addr,

    // Inputs from previous pipeline stage
    input  logic                                          i_valid,
    input  logic                                          i_fill_replay,
    input  logic [`PCYN_OP_WIDTH-1:0]                     i_op,
    input  logic [`PCYN_OP_IS_WIDTH-1:0]                  i_op_is,
    input  logic [OPTN_LQ_DEPTH-1:0]                      i_lq_select,
    input  logic [OPTN_SQ_DEPTH-1:0]                      i_sq_select,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]                 i_tag,
    input  logic [OPTN_ADDR_WIDTH-1:0]                    i_addr,
    input  logic [OPTN_DATA_WIDTH-1:0]                    i_retire_data,
    input  logic                                          i_retire,
    input  logic                                          i_replay,

    // Input from LQ for allocated entry select
    input  logic [OPTN_LQ_DEPTH-1:0]                      i_alloc_lq_select,

    // Outputs to next pipeline stage
    output logic                                          o_valid,
    output logic                                          o_mhq_lookup_valid,
    output logic                                          o_fill_replay,
    output logic [`PCYN_OP_WIDTH-1:0]                     o_op,
    output logic [`PCYN_OP_IS_WIDTH-1:0]                  o_op_is,
    output logic [OPTN_LQ_DEPTH-1:0]                      o_lq_select,
    output logic [OPTN_SQ_DEPTH-1:0]                      o_sq_select,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]                 o_tag,
    output logic [OPTN_ADDR_WIDTH-1:0]                    o_addr,
    output logic [OPTN_DATA_WIDTH-1:0]                    o_retire_data,
    output logic                                          o_retire
);

    logic n_flush;
    assign n_flush = ~i_flush;

    logic valid;
    assign valid = n_flush & i_valid;
    procyon_srff #(1) o_valid_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(valid), .i_reset(1'b0), .o_q(o_valid));

    // Assert fill_replay if a fill request was asserted on the same cycle as a conflicting load/store in the DT or DW stages
    // These ops should not enqueue in the MHQ and should immediately replay
    logic fill_replay;
    assign fill_replay = i_fill_replay | (i_mhq_fill_en & (i_mhq_fill_addr == i_addr[OPTN_ADDR_WIDTH-1:OPTN_DC_OFFSET_WIDTH]));
    procyon_ff #(1) o_fill_replay_ff (.clk(clk), .i_en(1'b1), .i_d(fill_replay), .o_q(o_fill_replay));

    // If the load is being replayed, don't register i_alloc_lq_select for the next stage
    logic [OPTN_LQ_DEPTH-1:0] lq_select;
    assign lq_select = i_replay ? i_lq_select : i_alloc_lq_select;
    procyon_ff #(OPTN_LQ_DEPTH) o_lq_select_ff (.clk(clk), .i_en(1'b1), .i_d(lq_select), .o_q(o_lq_select));

    procyon_ff #(OPTN_SQ_DEPTH) o_sq_select_ff (.clk(clk), .i_en(1'b1), .i_d(i_sq_select), .o_q(o_sq_select));
    procyon_ff #(`PCYN_OP_WIDTH) o_op_ff (.clk(clk), .i_en(1'b1), .i_d(i_op), .o_q(o_op));
    procyon_ff #(`PCYN_OP_IS_WIDTH) o_op_is_ff (.clk(clk), .i_en(1'b1), .i_d(i_op_is), .o_q(o_op_is));
    procyon_ff #(OPTN_ROB_IDX_WIDTH) o_tag_ff (.clk(clk), .i_en(1'b1), .i_d(i_tag), .o_q(o_tag));
    procyon_ff #(OPTN_ADDR_WIDTH) o_addr_ff (.clk(clk), .i_en(1'b1), .i_d(i_addr), .o_q(o_addr));
    procyon_ff #(OPTN_DATA_WIDTH) o_retire_data_ff (.clk(clk), .i_en(1'b1), .i_d(i_retire_data), .o_q(o_retire_data));
    procyon_ff #(1) o_retire_ff (.clk(clk), .i_en(1'b1), .i_d(i_retire), .o_q(o_retire));

    // The MHQ should not lookup and enqueue/allocate if the op is marked as needing to replay due to a conflicting fill
    logic mhq_lookup_valid;
    assign mhq_lookup_valid = n_flush & i_valid & ~fill_replay;
    procyon_srff #(1) o_mhq_lookup_valid_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(mhq_lookup_valid), .i_reset(1'b0), .o_q(o_mhq_lookup_valid));

endmodule
