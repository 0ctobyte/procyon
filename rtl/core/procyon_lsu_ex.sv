/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// LSU execute pipeline stage

`include "procyon_constants.svh"

module procyon_lsu_ex #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_LQ_DEPTH      = 8,
    parameter OPTN_SQ_DEPTH      = 8,
    parameter OPTN_DC_LINE_SIZE  = 32,
    parameter OPTN_ROB_IDX_WIDTH = 5,

    parameter DC_LINE_WIDTH      = OPTN_DC_LINE_SIZE * 8
)(
    input  logic                            clk,
    input  logic                            n_rst,

    input  logic                            i_flush,

    // Inputs from previous pipeline stage
    input  logic                            i_valid,
    input  logic                            i_fill_replay,
    input  logic [`PCYN_OP_WIDTH-1:0]       i_op,
/* verilator lint_off UNUSED */
    input  logic [`PCYN_OP_IS_WIDTH-1:0]    i_op_is,
/* verilator lint_on  UNUSED */
    input  logic [OPTN_LQ_DEPTH-1:0]        i_lq_select,
    input  logic [OPTN_SQ_DEPTH-1:0]        i_sq_select,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]   i_tag,
    input  logic                            i_retire,

    // Inputs from dcache
    input  logic                            i_dc_hit,
    input  logic [OPTN_DATA_WIDTH-1:0]      i_dc_data,
    input  logic                            i_dc_victim_valid,
    input  logic                            i_dc_victim_dirty,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_dc_victim_addr,
    input  logic [DC_LINE_WIDTH-1:0]        i_dc_victim_data,

    // Broadcast CDB results
    output logic                            o_valid,
    output logic [OPTN_DATA_WIDTH-1:0]      o_data,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]   o_tag,

    // Update LQ/SQ
    output logic                            o_update_lq_en,
    output logic [OPTN_LQ_DEPTH-1:0]        o_update_lq_select,
    output logic                            o_update_sq_en,
    output logic [OPTN_SQ_DEPTH-1:0]        o_update_sq_select,
    output logic                            o_update_retry,
    output logic                            o_update_replay,

    // Enqueue victim data
    output logic                            o_victim_en,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_victim_addr,
    output logic [DC_LINE_WIDTH-1:0]        o_victim_data
);

    logic is_fill;
    logic is_not_fill;
    logic is_store;

    assign is_fill = (i_op == `PCYN_OP_FILL);
    assign is_not_fill = ~is_fill;
    assign is_store = i_op_is[`PCYN_OP_IS_ST_IDX];

    logic n_flush;
    assign n_flush = ~i_flush;

    // Stores always complete successfully and the "result" is broadcast over the CDB (except when it's a retiring store)
    // Loads only complete successfully if it hit in the cache (ditto for replaying loads)
    logic valid;
    assign valid = n_flush & i_valid & is_not_fill & ~i_retire & (i_dc_hit | is_store);
    procyon_srff #(1) o_valid_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(valid), .i_reset(1'b0), .o_q(o_valid));

    procyon_ff #(OPTN_ROB_IDX_WIDTH) o_tag_ff (.clk(clk), .i_en(1'b1), .i_d(i_tag), .o_q(o_tag));

    // LB and LH need to sign extend to DATA_WIDTH
    logic [OPTN_DATA_WIDTH-1:0] load_data;

    always_comb begin
        case (i_op)
            `PCYN_OP_LB: load_data = {{(OPTN_DATA_WIDTH-8){i_dc_data[7]}}, i_dc_data[7:0]};
            `PCYN_OP_LH: load_data = {{(OPTN_DATA_WIDTH-OPTN_DATA_WIDTH/2){i_dc_data[OPTN_DATA_WIDTH/2-1]}}, i_dc_data[OPTN_DATA_WIDTH/2-1:0]};
            default:     load_data = i_dc_data;
        endcase
    end

    procyon_ff #(OPTN_DATA_WIDTH) o_data_ff (.clk(clk), .i_en(1'b1), .i_d(load_data), .o_q(o_data));

    // LQ/SQ update signals. Let the LQ or SQ know the load/store missed in the cache and must be retried
    logic update_lq_en;
    assign update_lq_en = n_flush & i_valid & (is_not_fill & ~is_store);
    procyon_srff #(1) o_update_lq_en_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(update_lq_en), .i_reset(1'b0), .o_q(o_update_lq_en));

    logic update_sq_en;
    assign update_sq_en = n_flush & i_valid & i_retire;
    procyon_srff #(1) o_update_sq_en_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(update_sq_en), .i_reset(1'b0), .o_q(o_update_sq_en));

    logic n_dc_hit;
    assign n_dc_hit = ~i_dc_hit;
    procyon_ff #(1) o_update_retry_ff (.clk(clk), .i_en(1'b1), .i_d(n_dc_hit), .o_q(o_update_retry));

    procyon_ff #(OPTN_LQ_DEPTH) o_update_lq_select_ff (.clk(clk), .i_en(1'b1), .i_d(i_lq_select), .o_q(o_update_lq_select));
    procyon_ff #(OPTN_SQ_DEPTH) o_update_sq_select_ff (.clk(clk), .i_en(1'b1), .i_d(i_sq_select), .o_q(o_update_sq_select));
    procyon_ff #(1) o_update_replay_ff (.clk(clk), .i_en(1'b1), .i_d(i_fill_replay), .o_q(o_update_replay));

    // Send victim data to the Victim Buffer
    logic victim_en;
    assign victim_en = i_valid & is_fill & i_dc_victim_valid & i_dc_victim_dirty;
    procyon_srff #(1) o_victim_en_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(victim_en), .i_reset(1'b0), .o_q(o_victim_en));

    procyon_ff #(OPTN_ADDR_WIDTH) o_victim_addr_ff (.clk(clk), .i_en(1'b1), .i_d(i_dc_victim_addr), .o_q(o_victim_addr));
    procyon_ff #(DC_LINE_WIDTH) o_victim_data_ff (.clk(clk), .i_en(1'b1), .i_d(i_dc_victim_data), .o_q(o_victim_data));

endmodule
