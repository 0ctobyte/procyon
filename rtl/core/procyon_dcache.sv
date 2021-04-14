/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Data Cache
// Requests are split into two stages
// For read requests:
// DT stage - Read out data/tag RAM and cache state
// DW stage - Generate hit signal and read data word
// For write requests:
// DT stage - Read out data/tag RAM and cache state
// and shift write data into correct offset into cacheline
// also for fills, mux out the fill data instead of the write data
// DW stage - Generate hit signal and cache write signals
// also output victim data, address and cache state

`include "procyon_constants.svh"

module procyon_dcache #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_DC_CACHE_SIZE = 1024,
    parameter OPTN_DC_LINE_SIZE  = 32,
    parameter OPTN_DC_WAY_COUNT  = 1,

    parameter DC_LINE_WIDTH      = OPTN_DC_LINE_SIZE * 8
)(
    input  logic                            clk,
    input  logic                            n_rst,

    input  logic                            i_dc_wr_en,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_dc_addr,
    input  logic [OPTN_DATA_WIDTH-1:0]      i_dc_data,
    input  logic [`PCYN_OP_WIDTH-1:0]       i_dc_op,
    input  logic                            i_dc_valid,
    input  logic                            i_dc_dirty,
    input  logic                            i_dc_fill,
    input  logic [DC_LINE_WIDTH-1:0]        i_dc_fill_data,

    output logic                            o_dc_hit,
    output logic [OPTN_DATA_WIDTH-1:0]      o_dc_data,
    output logic                            o_dc_victim_valid,
    output logic                            o_dc_victim_dirty,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_dc_victim_addr,
    output logic [DC_LINE_WIDTH-1:0]        o_dc_victim_data
);

    localparam DC_OFFSET_WIDTH = $clog2(OPTN_DC_LINE_SIZE);
    localparam DC_INDEX_WIDTH  = $clog2(OPTN_DC_CACHE_SIZE / OPTN_DC_LINE_SIZE / OPTN_DC_WAY_COUNT);
    localparam DC_TAG_WIDTH    = OPTN_ADDR_WIDTH - DC_INDEX_WIDTH - DC_OFFSET_WIDTH;
    localparam DATA_SIZE       = OPTN_DATA_WIDTH / 8;

    // Crack open address into tag, index & offset
    logic [DC_TAG_WIDTH-1:0] dc_tag;
    logic [DC_INDEX_WIDTH-1:0] dc_index;
    logic [DC_OFFSET_WIDTH-1:0] dc_offset;

    assign dc_tag = i_dc_addr[OPTN_ADDR_WIDTH-1:OPTN_ADDR_WIDTH-DC_TAG_WIDTH];
    assign dc_index = i_dc_addr[DC_INDEX_WIDTH+DC_OFFSET_WIDTH-1:DC_OFFSET_WIDTH];
    assign dc_offset = i_dc_addr[DC_OFFSET_WIDTH-1:0];

    logic dcache_dt_wr_en;
    logic [DC_TAG_WIDTH-1:0] dcache_dt_tag;
    logic [DC_INDEX_WIDTH-1:0] dcache_dt_index;
    logic [DC_OFFSET_WIDTH-1:0] dcache_dt_offset;
    logic [DATA_SIZE-1:0] dcache_dt_byte_sel;
    logic [OPTN_DATA_WIDTH-1:0] dcache_dt_data;
    logic dcache_dt_valid;
    logic dcache_dt_dirty;
    logic dcache_dt_fill;
    logic [DC_LINE_WIDTH-1:0] dcache_dt_fill_data;
    logic cache_rd_valid;
    logic cache_rd_dirty;
    logic [DC_TAG_WIDTH-1:0] cache_rd_tag;
    logic [DC_LINE_WIDTH-1:0] cache_rd_data;
    logic cache_wr_en;
    logic [DC_INDEX_WIDTH-1:0] cache_wr_index;
    logic cache_wr_valid;
    logic cache_wr_dirty;
    logic [DC_TAG_WIDTH-1:0] cache_wr_tag;
    logic [DC_LINE_WIDTH-1:0] cache_wr_data;

    procyon_dcache_dt #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_DC_CACHE_SIZE(OPTN_DC_CACHE_SIZE),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE),
        .OPTN_DC_WAY_COUNT(OPTN_DC_WAY_COUNT)
    ) procyon_dcache_dt_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_wr_en(i_dc_wr_en),
        .i_tag(dc_tag),
        .i_index(dc_index),
        .i_offset(dc_offset),
        .i_op(i_dc_op),
        .i_data(i_dc_data),
        .i_valid(i_dc_valid),
        .i_dirty(i_dc_dirty),
        .i_fill(i_dc_fill),
        .i_fill_data(i_dc_fill_data),
        .o_wr_en(dcache_dt_wr_en),
        .o_tag(dcache_dt_tag),
        .o_index(dcache_dt_index),
        .o_offset(dcache_dt_offset),
        .o_byte_sel(dcache_dt_byte_sel),
        .o_data(dcache_dt_data),
        .o_valid(dcache_dt_valid),
        .o_dirty(dcache_dt_dirty),
        .o_fill(dcache_dt_fill),
        .o_fill_data(dcache_dt_fill_data)
    );

    procyon_dcache_dw #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_DC_CACHE_SIZE(OPTN_DC_CACHE_SIZE),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE),
        .OPTN_DC_WAY_COUNT(OPTN_DC_WAY_COUNT)
    ) procyon_dcache_dw_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_wr_en(dcache_dt_wr_en),
        .i_tag(dcache_dt_tag),
        .i_index(dcache_dt_index),
        .i_offset(dcache_dt_offset),
        .i_byte_sel(dcache_dt_byte_sel),
        .i_data(dcache_dt_data),
        .i_valid(dcache_dt_valid),
        .i_dirty(dcache_dt_dirty),
        .i_fill(dcache_dt_fill),
        .i_fill_data(dcache_dt_fill_data),
        .i_cache_rd_valid(cache_rd_valid),
        .i_cache_rd_dirty(cache_rd_dirty),
        .i_cache_rd_tag(cache_rd_tag),
        .i_cache_rd_data(cache_rd_data),
        .i_bypass_cache_wr_en(cache_wr_en),
        .i_bypass_cache_wr_index(cache_wr_index),
        .i_bypass_cache_wr_tag(cache_wr_tag),
        .i_bypass_cache_wr_data(cache_wr_data),
        .i_bypass_cache_wr_valid(cache_wr_valid),
        .i_bypass_cache_wr_dirty(cache_wr_dirty),
        .o_cache_wr_en(cache_wr_en),
        .o_cache_wr_index(cache_wr_index),
        .o_cache_wr_tag(cache_wr_tag),
        .o_cache_wr_data(cache_wr_data),
        .o_cache_wr_valid(cache_wr_valid),
        .o_cache_wr_dirty(cache_wr_dirty),
        .o_hit(o_dc_hit),
        .o_data(o_dc_data),
        .o_victim_valid(o_dc_victim_valid),
        .o_victim_dirty(o_dc_victim_dirty),
        .o_victim_addr(o_dc_victim_addr),
        .o_victim_data(o_dc_victim_data)
    );

    procyon_cache #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_CACHE_SIZE(OPTN_DC_CACHE_SIZE),
        .OPTN_CACHE_LINE_SIZE(OPTN_DC_LINE_SIZE)
    ) procyon_data_cache_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_cache_wr_en(cache_wr_en),
        .i_cache_wr_index(cache_wr_index),
        .i_cache_wr_valid(cache_wr_valid),
        .i_cache_wr_dirty(cache_wr_dirty),
        .i_cache_wr_tag(cache_wr_tag),
        .i_cache_wr_data(cache_wr_data),
        .i_cache_rd_en(1'b1),
        .i_cache_rd_index(dc_index),
        .o_cache_rd_valid(cache_rd_valid),
        .o_cache_rd_dirty(cache_rd_dirty),
        .o_cache_rd_tag(cache_rd_tag),
        .o_cache_rd_data(cache_rd_data)
    );

endmodule
