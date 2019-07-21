// Data Cache - Dcache hit check and generate dcache write signals stage

`include "common.svh"
import procyon_types::*;

module dcache_d1 (
    input  logic                   clk,
    input  logic                   n_rst,

    input  logic                   i_wr_en,
    input  procyon_dc_tag_t        i_tag,
    input  procyon_dc_index_t      i_index,
    input  procyon_dc_offset_t     i_offset,
    input  procyon_byte_select_t   i_byte_sel,
    input  procyon_data_t          i_data,
    input  logic                   i_valid,
    input  logic                   i_dirty,
    input  logic                   i_fill,
    input  procyon_cacheline_t     i_fill_data,

    input  logic                   i_cache_rd_valid,
    input  logic                   i_cache_rd_dirty,
    input  procyon_dc_tag_t        i_cache_rd_tag,
    input  procyon_cacheline_t     i_cache_rd_data,

    input  logic                   i_bypass_cache_wr_en,
    input  procyon_dc_index_t      i_bypass_cache_wr_index,
    input  procyon_dc_tag_t        i_bypass_cache_wr_tag,
    input  procyon_cacheline_t     i_bypass_cache_wr_data,
    input  logic                   i_bypass_cache_wr_valid,
    input  logic                   i_bypass_cache_wr_dirty,

    output logic                   o_cache_wr_en,
    output procyon_dc_index_t      o_cache_wr_index,
    output procyon_dc_tag_t        o_cache_wr_tag,
    output procyon_cacheline_t     o_cache_wr_data,
    output logic                   o_cache_wr_valid,
    output logic                   o_cache_wr_dirty,

    output logic                   o_hit,
    output procyon_data_t          o_data,
    output logic                   o_victim_valid,
    output logic                   o_victim_dirty,
    output procyon_addr_t          o_victim_addr,
    output procyon_cacheline_t     o_victim_data
);

    logic                          bypass;
    logic                          bypass_hit;
    procyon_cacheline_t            bypass_cache_wr_data;
    procyon_dc_tag_t               bypass_cache_wr_tag;
    logic                          bypass_cache_wr_valid;
    logic                          bypass_cache_wr_dirty;
    logic                          cache_hit;
    procyon_addr_t                 victim_addr;
    procyon_data_t                 rd_data;
    procyon_cacheline_t            wr_data;

    // Determine if a cache write needs to be bypassed
    assign bypass                  = i_bypass_cache_wr_en & (i_bypass_cache_wr_index == i_index);
    assign bypass_hit              = bypass & (i_bypass_cache_wr_tag == i_tag);
    assign bypass_cache_wr_data    = bypass_hit ? i_bypass_cache_wr_data : i_cache_rd_data;
    assign bypass_cache_wr_tag     = bypass ? i_bypass_cache_wr_tag : i_cache_rd_tag;
    assign bypass_cache_wr_valid   = bypass ? i_bypass_cache_wr_valid : i_cache_rd_valid;
    assign bypass_cache_wr_dirty   = bypass ? i_bypass_cache_wr_dirty : i_cache_rd_dirty;

    // Generate cache hit signal when cacheline is valid and the tags match
    // Bypass signals from next stage if bypass_index matches
    assign cache_hit               = (bypass_cache_wr_tag == i_tag) & bypass_cache_wr_valid;

    // Generate victim address from tag & index
    assign victim_addr             = {bypass_cache_wr_tag, i_index, {(`DC_OFFSET_WIDTH){1'b0}}};

    // Extract read data word from cacheline masking off bytes according to the byte select
    always_comb begin
        rd_data = {(`DATA_WIDTH){1'b0}};
        for (int i = 0; i < (`DC_LINE_SIZE-`WORD_SIZE); i++) begin
            if (procyon_dc_offset_t'(i) == i_offset) begin
                for (int j = 0; j < `WORD_SIZE; j++) begin
                    if (i_byte_sel[j]) begin
                        rd_data[j*8 +: 8] = bypass_cache_wr_data[(i+j)*8 +: 8];
                    end
                end
            end
        end

        // Accessing bytes at the end of the line is tricky. We can't read or write past the end of the data line
        // So special case the accesses to the last WORD_SIZE portion of the line by only reading the bytes we can access
        for (int i = (`DC_LINE_SIZE-`WORD_SIZE); i < `DC_LINE_SIZE; i++) begin
            if (procyon_dc_offset_t'(i) == i_offset) begin
                for (int j = 0; j < (`DC_LINE_SIZE-i); j++) begin
                    if (i_byte_sel[j]) begin
                        rd_data[j*8 +: 8] = bypass_cache_wr_data[(i+j)*8 +: 8];
                    end
                end
            end
        end
    end

    // Shift write data to correct offset in cacheline masking off writes to certain bytes according to the byte select
    always_comb begin
        wr_data = bypass_cache_wr_data;
        for (int i = 0; i < (`DC_LINE_SIZE-`WORD_SIZE); i++) begin
            if (procyon_dc_offset_t'(i) == i_offset) begin
                for (int j = 0; j < `WORD_SIZE; j++) begin
                    if (i_byte_sel[j]) begin
                        wr_data[(i+j)*8 +: 8] = i_data[j*8 +: 8];
                    end
                end
            end
        end

        // Accessing bytes at the end of the line is tricky. We can't read or write past the end of the data line
        // So special case the writes to the last WORD_SIZE portion of the line by only writing to the number of bytes
        // remaining in the line rather than the whole WORD_SIZE data
        for (int i = (`DC_LINE_SIZE-`WORD_SIZE); i < `DC_LINE_SIZE; i++) begin
            if (procyon_dc_offset_t'(i) == i_offset) begin
                for (int j = 0; j < (`DC_LINE_SIZE-i); j++) begin
                    if (i_byte_sel[j]) begin
                        wr_data[(i+j)*8 +: 8] = i_data[j*8 +: 8];
                    end
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        o_cache_wr_index <= i_index;
        o_cache_wr_tag   <= i_tag;
        o_cache_wr_data  <= i_fill ? i_fill_data : wr_data;
        o_cache_wr_valid <= i_valid;
        o_cache_wr_dirty <= i_dirty;
    end

    // o_cache_wr_en must be asserted if i_fill is asserted
    always_ff @(posedge clk) begin
        if (~n_rst) o_cache_wr_en <= 1'b0;
        else        o_cache_wr_en <= i_fill | (cache_hit & i_wr_en);
    end

    always_ff @(posedge clk) begin
        o_hit          <= cache_hit;
        o_data         <= rd_data;
        o_victim_valid <= bypass_cache_wr_valid;
        o_victim_dirty <= bypass_cache_wr_dirty;
        o_victim_addr  <= victim_addr;
        o_victim_data  <= bypass ? i_bypass_cache_wr_data : i_cache_rd_data;
    end

endmodule
