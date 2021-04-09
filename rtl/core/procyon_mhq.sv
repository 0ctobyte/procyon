/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Miss Handling Queue
// Queue for loads or stores that miss in the cache
// Merges missed loads if the load address already exists in the queue
// Stores will be merged with existing entries as well
// The data read from memory will be merged with updated bytes in the entry from stores
// The MHQ consists of a two stage pipeline
// Lookup stage:
// - CAM for valid matching addresses and output tag, full and address info to next stage as well as to LSU_EX
// - The lsu_lq uses the MHQ tag information to wake up loads that missed in the cache and are waiting on fills from the MHQ
// Update Stage:
// - Enqueue or merges if necessary and writes store retire data into the MHQ entry

`include "procyon_constants.svh"

module procyon_mhq #(
    parameter OPTN_DATA_WIDTH   = 32,
    parameter OPTN_ADDR_WIDTH   = 32,
    parameter OPTN_MHQ_DEPTH    = 4,
    parameter OPTN_DC_LINE_SIZE = 1024,

    parameter MHQ_IDX_WIDTH     = $clog2(OPTN_MHQ_DEPTH),
    parameter DC_LINE_WIDTH     = OPTN_DC_LINE_SIZE * 8
)(
    input  logic                            clk,
    input  logic                            n_rst,

    // Interface to LSU to match lookup address to valid entries and return enqueue tag
    // FIXME What if there is a fill for the given lookup address on the same cycle?
    input  logic                            i_mhq_lookup_valid,
    input  logic                            i_mhq_lookup_dc_hit,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_mhq_lookup_addr,
    input  logic [`PCYN_LSU_FUNC_WIDTH-1:0] i_mhq_lookup_lsu_func,
    input  logic [OPTN_DATA_WIDTH-1:0]      i_mhq_lookup_data,
    input  logic                            i_mhq_lookup_we,
    output logic [MHQ_IDX_WIDTH-1:0]        o_mhq_lookup_tag,
    output logic                            o_mhq_lookup_retry,
    output logic                            o_mhq_lookup_replay,

    // Fill cacheline interface
    output logic                            o_mhq_fill_en,
    output logic [MHQ_IDX_WIDTH-1:0]        o_mhq_fill_tag,
    output logic                            o_mhq_fill_dirty,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_mhq_fill_addr,
    output logic [DC_LINE_WIDTH-1:0]        o_mhq_fill_data,

    // BIU interface
    input  logic                            i_biu_done,
    input  logic [DC_LINE_WIDTH-1:0]        i_biu_data,
    output logic                            o_biu_en,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_biu_addr
);

    localparam DC_OFFSET_WIDTH = $clog2(OPTN_DC_LINE_SIZE);

    logic [MHQ_IDX_WIDTH-1:0] mhq_queue_head;
    logic [MHQ_IDX_WIDTH-1:0] mhq_queue_tail;
    logic mhq_queue_full;
/* verilator lint_off UNUSED */
    logic mhq_queue_empty;
/* verilator lint_on  UNUSED */

    logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] mhq_lookup_addr;
    assign mhq_lookup_addr = i_mhq_lookup_addr[OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH];

    logic [OPTN_MHQ_DEPTH-1:0] mhq_entry_valid;
    logic [OPTN_MHQ_DEPTH-1:0] mhq_entry_complete;
    logic [OPTN_MHQ_DEPTH-1:0] mhq_entry_dirty;
    logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] mhq_entry_addr [0:OPTN_MHQ_DEPTH-1];
    logic [DC_LINE_WIDTH-1:0] mhq_entry_data [0:OPTN_MHQ_DEPTH-1];
    logic [OPTN_MHQ_DEPTH-1:0] mhq_lookup_entry_hit_select;
    logic [OPTN_MHQ_DEPTH-1:0] mhq_update_select;
    logic mhq_update_we;
    logic [DC_LINE_WIDTH-1:0] mhq_update_wr_data;
    logic [OPTN_DC_LINE_SIZE-1:0] mhq_update_byte_select;
    logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] mhq_update_addr;

    logic [OPTN_MHQ_DEPTH-1:0] biu_done;
    logic [OPTN_MHQ_DEPTH-1:0] mhq_fill_launched;

    always_comb begin
        biu_done = '0;
        biu_done[mhq_queue_head] = i_biu_done;

        mhq_fill_launched = '0;
        mhq_fill_launched[mhq_queue_head] = mhq_entry_complete[mhq_queue_head];
    end

    genvar inst;
    generate
    for (inst = 0; inst < OPTN_MHQ_DEPTH; inst++) begin : GEN_MHQ_ENTRY_INST
        procyon_mhq_entry #(
            .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
            .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE)
        ) procyon_mhq_entry_inst (
            .clk(clk),
            .n_rst(n_rst),
            .o_mhq_entry_valid(mhq_entry_valid[inst]),
            .o_mhq_entry_complete(mhq_entry_complete[inst]),
            .o_mhq_entry_dirty(mhq_entry_dirty[inst]),
            .o_mhq_entry_addr(mhq_entry_addr[inst]),
            .o_mhq_entry_data(mhq_entry_data[inst]),
            .i_lookup_addr(mhq_lookup_addr),
            .o_lookup_hit(mhq_lookup_entry_hit_select[inst]),
            .i_update_en(mhq_update_select[inst]),
            .i_update_we(mhq_update_we),
            .i_update_wr_data(mhq_update_wr_data),
            .i_update_byte_select(mhq_update_byte_select),
            .i_update_addr(mhq_update_addr),
            .i_biu_done(biu_done[inst]),
            .i_biu_data(i_biu_data),
            .i_fill_launched(mhq_fill_launched[inst])
        );
    end
    endgenerate

    logic [OPTN_MHQ_DEPTH-1:0] mhq_lookup_entry_alloc_select;
    logic mhq_lookup_allocating;
    logic mhq_fill_en;
    logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] mhq_lookup_fill_addr;

    // Convert tail pointer to one-hot allocation select vector
    procyon_binary2onehot #(OPTN_MHQ_DEPTH) mhq_lookup_entry_alloc_select_binary2onehot (.i_binary(mhq_queue_tail), .o_onehot(mhq_lookup_entry_alloc_select));

    // Send to the MHQ_LU stage to compare against current lookup address and signal immediate replay
    assign mhq_lookup_fill_addr = mhq_entry_addr[mhq_queue_head];
    assign mhq_fill_en = mhq_entry_complete[mhq_queue_head];

    procyon_mhq_lu #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_MHQ_DEPTH(OPTN_MHQ_DEPTH),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE)
    ) procyon_mhq_lu_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_mhq_full(mhq_queue_full),
        .i_mhq_update_bypass_select(mhq_update_select),
        .i_mhq_update_bypass_addr(mhq_update_addr),
        .i_mhq_lookup_valid(i_mhq_lookup_valid),
        .i_mhq_lookup_we(i_mhq_lookup_we),
        .i_mhq_lookup_dc_hit(i_mhq_lookup_dc_hit),
        .i_mhq_lookup_addr(i_mhq_lookup_addr),
        .i_mhq_lookup_lsu_func(i_mhq_lookup_lsu_func),
        .i_mhq_lookup_data(i_mhq_lookup_data),
        .i_mhq_lookup_entry_hit_select(mhq_lookup_entry_hit_select),
        .i_mhq_lookup_entry_alloc_select(mhq_lookup_entry_alloc_select),
        .o_mhq_lookup_tag(o_mhq_lookup_tag),
        .o_mhq_lookup_retry(o_mhq_lookup_retry),
        .o_mhq_lookup_replay(o_mhq_lookup_replay),
        .o_mhq_lookup_allocating(mhq_lookup_allocating),
        .o_mhq_update_select(mhq_update_select),
        .o_mhq_update_we(mhq_update_we),
        .o_mhq_update_wr_data(mhq_update_wr_data),
        .o_mhq_update_byte_select(mhq_update_byte_select),
        .o_mhq_update_addr(mhq_update_addr),
        .i_biu_done(i_biu_done),
        .i_mhq_fill_en(mhq_fill_en),
        .i_mhq_fill_addr(mhq_lookup_fill_addr)
    );

    // Increment tail pointer if an entry is going to be allocated (i.e. lookup is valid and missed in the cache but
    // did not hit any current mhq entries). Increment head pointer if a fill is going to be launched.
    procyon_queue_ctrl #(
        .OPTN_QUEUE_DEPTH(OPTN_MHQ_DEPTH)
    ) mhq_queue_ctrl (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(1'b0),
        .i_incr_head(mhq_fill_en),
        .i_incr_tail(mhq_lookup_allocating),
        .o_queue_head(mhq_queue_head),
        .o_queue_tail(mhq_queue_tail),
        .o_queue_full(mhq_queue_full),
        .o_queue_empty(mhq_queue_empty)
    );

    // Fill request signals sent to LSU
    procyon_ff #(1) o_mhq_fill_en_ff (.clk(clk), .i_en(1'b1), .i_d(mhq_fill_en), .o_q(o_mhq_fill_en));
    procyon_ff #(MHQ_IDX_WIDTH) o_mhq_fill_tag_ff (.clk(clk), .i_en(1'b1), .i_d(mhq_queue_head), .o_q(o_mhq_fill_tag));
    procyon_ff #(1) o_mhq_fill_dirty_ff (.clk(clk), .i_en(1'b1), .i_d(mhq_entry_dirty[mhq_queue_head]), .o_q(o_mhq_fill_dirty));

    logic [OPTN_ADDR_WIDTH-1:0] mhq_fill_addr;
    assign mhq_fill_addr = {mhq_entry_addr[mhq_queue_head], {(DC_OFFSET_WIDTH){1'b0}}};
    procyon_ff #(OPTN_ADDR_WIDTH) o_mhq_fill_addr_ff (.clk(clk), .i_en(1'b1), .i_d(mhq_fill_addr), .o_q(o_mhq_fill_addr));

    procyon_ff #(DC_LINE_WIDTH) o_mhq_fill_data_ff (.clk(clk), .i_en(1'b1), .i_d(mhq_entry_data[mhq_queue_head]), .o_q(o_mhq_fill_data));

    // Signal to BIU to fetch data from memory
    assign o_biu_addr = mhq_fill_addr;
    assign o_biu_en = mhq_entry_valid[mhq_queue_head] & ~mhq_entry_complete[mhq_queue_head];

endmodule
