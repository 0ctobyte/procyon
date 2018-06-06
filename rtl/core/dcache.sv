// Data Cache

`include "common.svh"
import procyon_types::*;

module dcache (
    input  logic                   clk,
    input  logic                   n_rst,

    input  logic                   i_dc_we,
    input  procyon_addr_t          i_dc_addr,
    input  procyon_data_t          i_dc_data,
    input  procyon_byte_select_t   i_dc_byte_select,
    output logic                   o_dc_busy,
    output logic                   o_dc_hit,
    output procyon_data_t          o_dc_data,

    input  logic                   i_dc_fill,
    input  logic                   i_dc_fill_dirty,
    input  procyon_addr_t          i_dc_fill_addr,
    input  procyon_cacheline_t     i_dc_fill_data
);

    logic [`DC_OFFSET_WIDTH-1:0] cache_offset;
    logic [`DC_INDEX_WIDTH-1:0]  cache_index;
    logic [`DC_TAG_WIDTH-1:0]    cache_tag;
    logic                        cache_re;
    procyon_data_t               cache_wdata;
    procyon_data_t               cache_rdata;

    /* verilator lint_off UNUSED */
    logic                        cache_victim_dirty;
    logic [`DC_TAG_WIDTH-1:0]    cache_victim_tag;
    procyon_cacheline_t          cache_victim_data;
    /* verilator lint_on  UNUSED */

    logic [`DC_OFFSET_WIDTH-1:0] dc_offset;
    logic [`DC_INDEX_WIDTH-1:0]  dc_index;
    logic [`DC_TAG_WIDTH-1:0]    dc_tag;
    logic [`DC_OFFSET_WIDTH-1:0] fill_offset;
    logic [`DC_INDEX_WIDTH-1:0]  fill_index;
    logic [`DC_TAG_WIDTH-1:0]    fill_tag;

    // Splice the input read/write address into tag, index, offset
    assign dc_offset    = i_dc_addr[`DC_OFFSET_WIDTH-1:0];
    assign dc_index     = i_dc_addr[`DC_INDEX_WIDTH+`DC_OFFSET_WIDTH-1:`DC_OFFSET_WIDTH];
    assign dc_tag       = i_dc_addr[`ADDR_WIDTH-1:`ADDR_WIDTH-`DC_TAG_WIDTH];

    // Splice the input fill address into tag, index, offset
    assign fill_offset  = i_dc_fill_addr[`DC_OFFSET_WIDTH-1:0];
    assign fill_index   = i_dc_fill_addr[`DC_INDEX_WIDTH+`DC_OFFSET_WIDTH-1:`DC_OFFSET_WIDTH];
    assign fill_tag     = i_dc_fill_addr[`ADDR_WIDTH-1:`ADDR_WIDTH-`DC_TAG_WIDTH];

    // If a cache fill is in progress then signal that the cache is busy
    // Output cache read data
    assign o_dc_busy    = i_dc_fill;
    assign o_dc_data    = cache_rdata;

    // Select between read/write address bits or fill address bits depending
    // on i_dc_fill
    assign cache_re     = ~i_dc_we;
    assign cache_offset = i_dc_fill ? fill_offset : dc_offset;
    assign cache_index  = i_dc_fill ? fill_index : dc_index;
    assign cache_tag    = i_dc_fill ? fill_tag : dc_tag;

    always_comb begin
        for (int i = 0; i < `WORD_SIZE; i++) begin
            cache_wdata[i*8 +: 8] = i_dc_byte_select[i] ? i_dc_data[i*8 +: 8] : cache_rdata[i*8 +: 8];
        end
    end

    cache #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ADDR_WIDTH(`ADDR_WIDTH),
        .CACHE_SIZE(`DC_CACHE_SIZE),
        .CACHE_LINE_SIZE(`DC_LINE_SIZE)
    ) data_cache_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_cache_re(cache_re),
        .i_cache_we(i_dc_we),
        .i_cache_fe(i_dc_fill),
        .i_cache_valid(i_dc_fill),
        .i_cache_dirty(i_dc_fill_dirty),
        .i_cache_offset(cache_offset),
        .i_cache_index(cache_index),
        .i_cache_tag(cache_tag),
        .i_cache_fdata(i_dc_fill_data),
        .i_cache_wdata(cache_wdata),
        .o_cache_hit(o_dc_hit),
        .o_cache_dirty(cache_victim_dirty),
        .o_cache_tag(cache_victim_tag),
        .o_cache_vdata(cache_victim_data),
        .o_cache_rdata(cache_rdata)
    );

endmodule
