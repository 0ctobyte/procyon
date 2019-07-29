// Data Cache
// Requests are split into two stages
// For read requests:
// Stage 0 - Read out data/tag RAM and cache state
// Stage 1 - Generate hit signal and read data word
// For write requests:
// Stage 0 - Read out data/tag RAM and cache state
// and shift write data into correct offset into cacheline
// also for fills, mux out the fill data instead of the write data
// Stage 1 - Generate hit signal and cache write signals
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
    input  logic [`PCYN_LSU_FUNC_WIDTH-1:0] i_dc_lsu_func,
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

    logic [DC_TAG_WIDTH-1:0]        dc_tag;
    logic [DC_INDEX_WIDTH-1:0]      dc_index;
    logic [DC_OFFSET_WIDTH-1:0]     dc_offset;
    logic                           dcache_dr_wr_en;
    logic [DC_TAG_WIDTH-1:0]        dcache_dr_tag;
    logic [DC_INDEX_WIDTH-1:0]      dcache_dr_index;
    logic [DC_OFFSET_WIDTH-1:0]     dcache_dr_offset;
    logic [DATA_SIZE-1:0]           dcache_dr_byte_sel;
    logic [OPTN_DATA_WIDTH-1:0]     dcache_dr_data;
    logic                           dcache_dr_valid;
    logic                           dcache_dr_dirty;
    logic                           dcache_dr_fill;
    logic [DC_LINE_WIDTH-1:0]       dcache_dr_fill_data;
    logic                           cache_rd_valid;
    logic                           cache_rd_dirty;
    logic [DC_TAG_WIDTH-1:0]        cache_rd_tag;
    logic [DC_LINE_WIDTH-1:0]       cache_rd_data;
    logic                           cache_wr_en;
    logic [DC_INDEX_WIDTH-1:0]      cache_wr_index;
    logic                           cache_wr_valid;
    logic                           cache_wr_dirty;
    logic [DC_TAG_WIDTH-1:0]        cache_wr_tag;
    logic [DC_LINE_WIDTH-1:0]       cache_wr_data;

    // Crack open address into tag, index & offset
    assign dc_tag    = i_dc_addr[OPTN_ADDR_WIDTH-1:OPTN_ADDR_WIDTH-DC_TAG_WIDTH];
    assign dc_index  = i_dc_addr[DC_INDEX_WIDTH+DC_OFFSET_WIDTH-1:DC_OFFSET_WIDTH];
    assign dc_offset = i_dc_addr[DC_OFFSET_WIDTH-1:0];

    procyon_dcache_d0 #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_DC_CACHE_SIZE(OPTN_DC_CACHE_SIZE),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE),
        .OPTN_DC_WAY_COUNT(OPTN_DC_WAY_COUNT)
    ) procyon_dcache_d0_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_wr_en(i_dc_wr_en),
        .i_tag(dc_tag),
        .i_index(dc_index),
        .i_offset(dc_offset),
        .i_lsu_func(i_dc_lsu_func),
        .i_data(i_dc_data),
        .i_valid(i_dc_valid),
        .i_dirty(i_dc_dirty),
        .i_fill(i_dc_fill),
        .i_fill_data(i_dc_fill_data),
        .o_wr_en(dcache_dr_wr_en),
        .o_tag(dcache_dr_tag),
        .o_index(dcache_dr_index),
        .o_offset(dcache_dr_offset),
        .o_byte_sel(dcache_dr_byte_sel),
        .o_data(dcache_dr_data),
        .o_valid(dcache_dr_valid),
        .o_dirty(dcache_dr_dirty),
        .o_fill(dcache_dr_fill),
        .o_fill_data(dcache_dr_fill_data)
    );

    procyon_dcache_d1 #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_DC_CACHE_SIZE(OPTN_DC_CACHE_SIZE),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE),
        .OPTN_DC_WAY_COUNT(OPTN_DC_WAY_COUNT)
    ) procyon_dcache_d1_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_wr_en(dcache_dr_wr_en),
        .i_tag(dcache_dr_tag),
        .i_index(dcache_dr_index),
        .i_offset(dcache_dr_offset),
        .i_byte_sel(dcache_dr_byte_sel),
        .i_data(dcache_dr_data),
        .i_valid(dcache_dr_valid),
        .i_dirty(dcache_dr_dirty),
        .i_fill(dcache_dr_fill),
        .i_fill_data(dcache_dr_fill_data),
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
