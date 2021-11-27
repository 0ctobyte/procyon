/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Basic direct-mapped cache

module procyon_cache #(
    parameter OPTN_DATA_WIDTH      = 32,
    parameter OPTN_ADDR_WIDTH      = 32,
    parameter OPTN_CACHE_SIZE      = 1024,
    parameter OPTN_CACHE_LINE_SIZE = 32,

    parameter CACHE_INDEX_COUNT    = OPTN_CACHE_SIZE / OPTN_CACHE_LINE_SIZE,
    parameter CACHE_INDEX_WIDTH    = CACHE_INDEX_COUNT == 1 ? 1 : $clog2(CACHE_INDEX_COUNT),
    parameter CACHE_TAG_WIDTH      = OPTN_ADDR_WIDTH - (CACHE_INDEX_WIDTH == 1 ? 0 : CACHE_INDEX_WIDTH) - $clog2(OPTN_CACHE_LINE_SIZE),
    parameter CACHE_LINE_WIDTH     = OPTN_CACHE_LINE_SIZE * 8
)(
    input  logic                                clk,
    input  logic                                n_rst,

    // Interface to read/write data to cache
    // i_cache_rd_en = read enable
    // i_cache_wr_en = write enable
    // i_cache_wr_valid and i_cache_wr_dirty are only written into the state when i_cache_wr_en
    // asserted. i_cache_wr_index chooses the index into the cache and i_cache_wr_tag is written
    // into the tag ram
    input  logic                         i_cache_wr_en,
    input  logic [CACHE_INDEX_WIDTH-1:0] i_cache_wr_index,
    input  logic                         i_cache_wr_valid,
    input  logic                         i_cache_wr_dirty,
    input  logic [CACHE_TAG_WIDTH-1:0]   i_cache_wr_tag,
    input  logic [CACHE_LINE_WIDTH-1:0]  i_cache_wr_data,

    // o_cache_rd_data is the data requested on a read access
    // o_cache_rd_dirty, o_cache_rd_valid, and o_cache_rd_tag are output on a read access
    // o_cache_rd_data is the whole cacheline (in case of victimizing cachelines)
    // and o_cache_rd_tag is output as well (for victimized cachelines)
    input  logic                         i_cache_rd_en,
    input  logic [CACHE_INDEX_WIDTH-1:0] i_cache_rd_index,
    output logic                         o_cache_rd_valid,
    output logic                         o_cache_rd_dirty,
    output logic [CACHE_TAG_WIDTH-1:0]   o_cache_rd_tag,
    output logic [CACHE_LINE_WIDTH-1:0]  o_cache_rd_data
);

    logic cache_state_valid_r [0:CACHE_INDEX_COUNT-1];
    logic cache_state_dirty_r [0:CACHE_INDEX_COUNT-1];

    // Bypass dirty and valid signals on same cycle writes to the same index
    logic cache_rd_valid;
    logic cache_rd_dirty;

    assign cache_rd_valid = ((i_cache_rd_index == i_cache_wr_index) & i_cache_wr_en) ? i_cache_wr_valid : cache_state_valid_r[i_cache_rd_index];
    procyon_srff #(1) o_cache_rd_valid_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(cache_rd_valid), .i_reset(1'b0), .o_q(o_cache_rd_valid));

    assign cache_rd_dirty = ((i_cache_rd_index == i_cache_wr_index) & i_cache_wr_en) ? i_cache_wr_dirty : cache_state_dirty_r[i_cache_rd_index];
    procyon_srff #(1) o_cache_rd_dirty_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(cache_rd_dirty), .i_reset(1'b0), .o_q(o_cache_rd_dirty));

    genvar cache_state_idx;
    generate
    for (cache_state_idx = 0; cache_state_idx < CACHE_INDEX_COUNT; cache_state_idx++) begin : GEN_DIRTY_VALID_CACHE_STATE_FF
        logic cache_state_wr_en;
        assign cache_state_wr_en = i_cache_wr_en && (i_cache_wr_index == cache_state_idx);

        // Update the valid bit on a fill
        procyon_srff #(1) cache_state_valid_r_srff (.clk(clk), .n_rst(n_rst), .i_en(cache_state_wr_en), .i_set(i_cache_wr_valid), .i_reset(1'b0), .o_q(cache_state_valid_r[cache_state_idx]));

        // Update the dirty bit on a write and on a fill
        procyon_srff #(1) cache_state_dirty_r_srff (.clk(clk), .n_rst(n_rst), .i_en(cache_state_wr_en), .i_set(i_cache_wr_dirty), .i_reset(1'b0), .o_q(cache_state_dirty_r[cache_state_idx]));
    end
    endgenerate

    // Instantiate the DATA and TAG RAMs
    procyon_ram_sdpb #(
        .OPTN_DATA_WIDTH(CACHE_LINE_WIDTH),
        .OPTN_RAM_DEPTH(CACHE_INDEX_COUNT)
    ) data_ram (
        .clk(clk),
        .i_ram_rd_en(i_cache_rd_en),
        .i_ram_rd_addr(i_cache_rd_index),
        .o_ram_rd_data(o_cache_rd_data),
        .i_ram_wr_en(i_cache_wr_en),
        .i_ram_wr_addr(i_cache_wr_index),
        .i_ram_wr_data(i_cache_wr_data)
    );

    procyon_ram_sdpb #(
        .OPTN_DATA_WIDTH(CACHE_TAG_WIDTH),
        .OPTN_RAM_DEPTH(CACHE_INDEX_COUNT)
    ) tag_ram (
        .clk(clk),
        .i_ram_rd_en(i_cache_rd_en),
        .i_ram_rd_addr(i_cache_rd_index),
        .o_ram_rd_data(o_cache_rd_tag),
        .i_ram_wr_en(i_cache_wr_en),
        .i_ram_wr_addr(i_cache_wr_index),
        .i_ram_wr_data(i_cache_wr_tag)
    );

endmodule
