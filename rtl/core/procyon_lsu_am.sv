/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// LSU address generation and mux stage

`include "procyon_constants.svh"

module procyon_lsu_am #(
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

    // Full signal inputs from LQ/SQ
    input  logic                            i_lq_full,
    input  logic                            i_sq_full,

    // Inputs from reservation station
    input                                   i_valid,
    input  logic [`PCYN_OP_WIDTH-1:0]       i_op,
    input  logic [`PCYN_OP_IS_WIDTH-1:0]    i_op_is,
    input  logic [OPTN_DATA_WIDTH-1:0]      i_imm,
    input  logic [OPTN_DATA_WIDTH-1:0]      i_src [0:1],
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]   i_tag,
    output logic                            o_stall,

    // Input from MHQ on a fill
    input  logic                            i_mhq_fill_en,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_mhq_fill_addr,
    input  logic [DC_LINE_WIDTH-1:0]        i_mhq_fill_data,
    input  logic                            i_mhq_fill_dirty,

    // Input from SQ on a store-retire
    input  logic                            i_sq_retire_en,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]   i_sq_retire_tag,
    input  logic [OPTN_DATA_WIDTH-1:0]      i_sq_retire_data,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_sq_retire_addr,
    input  logic [`PCYN_OP_WIDTH-1:0]       i_sq_retire_op,
    input  logic [OPTN_SQ_DEPTH-1:0]        i_sq_retire_select,
    output logic                            o_sq_retire_stall,

    // Input from LQ on a load-replay
    input  logic                            i_lq_replay_en,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]   i_lq_replay_tag,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_lq_replay_addr,
    input  logic [`PCYN_OP_WIDTH-1:0]       i_lq_replay_op,
    input  logic [OPTN_LQ_DEPTH-1:0]        i_lq_replay_select,
    output logic                            o_lq_replay_stall,

    // Outputs to next pipeline stage
    output logic [`PCYN_OP_WIDTH-1:0]       o_op,
    output logic [`PCYN_OP_IS_WIDTH-1:0]    o_op_is,
    output logic [OPTN_LQ_DEPTH-1:0]        o_lq_select,
    output logic [OPTN_SQ_DEPTH-1:0]        o_sq_select,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]   o_tag,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_addr,
    output logic [OPTN_DATA_WIDTH-1:0]      o_retire_data,
    output logic                            o_retire,
    output logic                            o_replay,
    output logic                            o_valid,

    // Send read/write request to Dcache
    output logic                            o_dc_wr_en,
    output logic                            o_dc_dirty,
    output logic                            o_dc_fill,
    output logic [DC_LINE_WIDTH-1:0]        o_dc_fill_data,

    // Enqueue newly issued load/store ops in the load/store queues
    output logic [`PCYN_OP_WIDTH-1:0] o_alloc_op,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]   o_alloc_tag,
    output logic [OPTN_DATA_WIDTH-1:0]      o_alloc_data,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_alloc_addr,
    output logic                            o_alloc_sq_en,
    output logic                            o_alloc_lq_en
);

    logic lq_full;
    assign lq_full = i_lq_full & i_op_is[`PCYN_OP_IS_LD_IDX];

    logic sq_full;
    assign sq_full = i_sq_full & i_op_is[`PCYN_OP_IS_ST_IDX];

    // Stall the LSU RS if either of these conditions apply:
    // 1. There is a cache fill in progress
    // 2. Load queue is full and the incoming OP is a load
    // 3. Store queue is full and the incoming OP is a store
    // 4. A store needs to be retired
    // 5. A load needs to be replayed
    logic rs_stall;
    assign rs_stall = lq_full | sq_full | i_lq_replay_en | i_sq_retire_en | i_mhq_fill_en;
    assign o_stall = rs_stall;

    logic n_rs_stall;
    assign n_rs_stall = ~rs_stall;

    logic n_flush;
    assign n_flush = ~i_flush;

    // Allocate op in load queue or store queue
    logic alloc_sq_en;
    assign alloc_sq_en = n_flush & i_op_is[`PCYN_OP_IS_ST_IDX] & i_valid & n_rs_stall;
    procyon_srff #(1) o_alloc_sq_en_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(alloc_sq_en), .i_reset(1'b0), .o_q(o_alloc_sq_en));

    logic alloc_lq_en;
    assign alloc_lq_en = n_flush & i_op_is[`PCYN_OP_IS_LD_IDX] & i_valid & n_rs_stall;
    procyon_srff #(1) o_alloc_lq_en_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(alloc_lq_en), .i_reset(1'b0), .o_q(o_alloc_lq_en));

    procyon_ff #(`PCYN_OP_WIDTH) o_alloc_op_ff (.clk(clk), .i_en(1'b1), .i_d(i_op), .o_q(o_alloc_op));

    // Calculate address
    logic [OPTN_ADDR_WIDTH-1:0] addr;
    assign addr = i_src[0] + i_imm;
    procyon_ff #(OPTN_ADDR_WIDTH) o_alloc_addr_ff (.clk(clk), .i_en(1'b1), .i_d(addr), .o_q(o_alloc_addr));

    procyon_ff #(OPTN_ROB_IDX_WIDTH) o_alloc_tag_ff (.clk(clk), .i_en(1'b1), .i_d(i_tag), .o_q(o_alloc_tag));
    procyon_ff #(OPTN_DATA_WIDTH) o_alloc_data_ff (.clk(clk), .i_en(1'b1), .i_d(i_src[1]), .o_q(o_alloc_data));

    // Assign outputs to next stage in the pipeline
    // Fill requests get priority over pipeline flushes
    logic valid;
    assign valid = i_mhq_fill_en | (n_flush & ((i_valid & ~lq_full & ~sq_full) | i_lq_replay_en | i_sq_retire_en));
    procyon_srff #(1) o_valid_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(valid), .i_reset(1'b0), .o_q(o_valid));

    logic n_mhq_fill_en;
    assign n_mhq_fill_en = ~i_mhq_fill_en;

    logic retire;
    assign retire = n_mhq_fill_en & i_sq_retire_en;
    procyon_ff #(1) o_retire_ff (.clk(clk), .i_en(1'b1), .i_d(retire), .o_q(o_retire));

    logic replay;
    assign replay = n_mhq_fill_en & ~i_sq_retire_en & i_lq_replay_en;
    procyon_ff #(1) o_replay_ff (.clk(clk), .i_en(1'b1), .i_d(replay), .o_q(o_replay));

    procyon_ff #(OPTN_LQ_DEPTH) o_lq_select_ff (.clk(clk), .i_en(1'b1), .i_d(i_lq_replay_select), .o_q(o_lq_select));
    procyon_ff #(OPTN_SQ_DEPTH) o_sq_select_ff (.clk(clk), .i_en(1'b1), .i_d(i_sq_retire_select), .o_q(o_sq_select));
    procyon_ff #(OPTN_DATA_WIDTH) o_retire_data_ff (.clk(clk), .i_en(1'b1), .i_d(i_sq_retire_data), .o_q(o_retire_data));

    // Assign outputs to dcache interface
    logic dc_wr_en;
    assign dc_wr_en = n_flush & (i_sq_retire_en | i_mhq_fill_en);
    procyon_srff #(1) o_dc_wr_en_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(dc_wr_en), .i_reset(1'b0), .o_q(o_dc_wr_en));

    logic dc_dirty;
    assign dc_dirty = i_mhq_fill_en ? i_mhq_fill_dirty : i_sq_retire_en;
    procyon_ff #(1) o_dc_dirty_ff (.clk(clk), .i_en(1'b1), .i_d(dc_dirty), .o_q(o_dc_dirty));

    procyon_ff #(1) o_dc_fill_ff (.clk(clk), .i_en(1'b1), .i_d(i_mhq_fill_en), .o_q(o_dc_fill));
    procyon_ff #(DC_LINE_WIDTH) o_dc_fill_data_ff (.clk(clk), .i_en(1'b1), .i_d(i_mhq_fill_data), .o_q(o_dc_fill_data));

    // Mux AM outputs to next stage depending on replay_en/retire_en
    logic [1:0] lsu_am_mux_sel;
    assign lsu_am_mux_sel = {i_lq_replay_en, i_sq_retire_en};

    logic [OPTN_ADDR_WIDTH-1:0] lsu_am_addr_mux;

    always_comb begin
        case (lsu_am_mux_sel)
            2'b00: lsu_am_addr_mux = addr;
            2'b01: lsu_am_addr_mux = i_sq_retire_addr;
            2'b10: lsu_am_addr_mux = i_lq_replay_addr;
            2'b11: lsu_am_addr_mux = i_sq_retire_addr;
        endcase

        lsu_am_addr_mux = i_mhq_fill_en ? i_mhq_fill_addr : lsu_am_addr_mux;
    end

    procyon_ff #(OPTN_ADDR_WIDTH) o_addr_ff (.clk(clk), .i_en(1'b1), .i_d(lsu_am_addr_mux), .o_q(o_addr));

    logic [`PCYN_OP_WIDTH-1:0] lsu_am_op_mux;

    always_comb begin
        case (lsu_am_mux_sel)
            2'b00: lsu_am_op_mux = i_op;
            2'b01: lsu_am_op_mux = i_sq_retire_op;
            2'b10: lsu_am_op_mux = i_lq_replay_op;
            2'b11: lsu_am_op_mux = i_sq_retire_op;
        endcase

        lsu_am_op_mux = i_mhq_fill_en ? `PCYN_OP_FILL : lsu_am_op_mux;
    end

    procyon_ff #(`PCYN_OP_WIDTH) o_op_ff (.clk(clk), .i_en(1'b1), .i_d(lsu_am_op_mux), .o_q(o_op));

    logic [`PCYN_OP_IS_WIDTH-1:0] lsu_am_op_is_mux;

    always_comb begin
        case (lsu_am_mux_sel)
            2'b00: lsu_am_op_is_mux = i_op_is;
            2'b01: lsu_am_op_is_mux = `PCYN_OP_IS_ST;
            2'b10: lsu_am_op_is_mux = `PCYN_OP_IS_LD;
            2'b11: lsu_am_op_is_mux = `PCYN_OP_IS_ST;
        endcase

        lsu_am_op_is_mux = i_mhq_fill_en ? `PCYN_OP_IS_OP : lsu_am_op_is_mux;
    end

    procyon_ff #(`PCYN_OP_IS_WIDTH) o_op_is_ff (.clk(clk), .i_en(1'b1), .i_d(lsu_am_op_is_mux), .o_q(o_op_is));

    logic [OPTN_ROB_IDX_WIDTH-1:0] lsu_am_tag_mux;

    always_comb begin
        case (lsu_am_mux_sel)
            2'b00: lsu_am_tag_mux = i_tag;
            2'b01: lsu_am_tag_mux = i_sq_retire_tag;
            2'b10: lsu_am_tag_mux = i_lq_replay_tag;
            2'b11: lsu_am_tag_mux = i_sq_retire_tag;
        endcase

        lsu_am_tag_mux = i_mhq_fill_en ? '0 : lsu_am_tag_mux;
    end

    procyon_ff #(OPTN_ROB_IDX_WIDTH) o_tag_ff (.clk(clk), .i_en(1'b1), .i_d(lsu_am_tag_mux), .o_q(o_tag));

    assign o_sq_retire_stall = i_flush | i_mhq_fill_en;
    assign o_lq_replay_stall = i_sq_retire_en | i_mhq_fill_en;

endmodule
