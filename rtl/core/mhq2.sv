// Miss Handling Queue
// Queue for loads or stores that miss in the cache
// Merges missed loads if the load address already exists in the queue
// Stores will be merged with existing entries as well
// The data read from memory will be merged with updated bytes in the entry from stores
// The MHQ consists of a two stage pipeline
// Lookup stage:
// - CAM for valid matching addresses and output tag, full and address info to next stage
// as well as to LSU_EX
// Execute Stage:
// - Enqueue or merges if necessary and writes store retire data into the MHQ entry
// - Also handle merging write data with fill data from the CCU

`include "common.svh"
import procyon_types::*;

module mhq2 (
    input  logic                         clk,
    input  logic                         n_rst,

    // Interface to LSU to match lookup address to valid entries and return enqueue tag
    // FIXME What if there is a fill for the given lookup address on the same cycle?
    input  logic                         i_mhq_lookup_valid,
    input  logic                         i_mhq_lookup_dc_hit,
    input  procyon_addr_t                i_mhq_lookup_addr,
    input  procyon_lsu_func_t            i_mhq_lookup_lsu_func,
    input  procyon_data_t                i_mhq_lookup_data,
    input  logic                         i_mhq_lookup_we,
    output procyon_mhq_tag_t             o_mhq_lookup_tag,
    output logic                         o_mhq_lookup_full,

    // Fill cacheline interface
    output logic                         o_mhq_fill_en,
    output procyon_mhq_tag_t             o_mhq_fill_tag,
    output logic                         o_mhq_fill_dirty,
    output procyon_addr_t                o_mhq_fill_addr,
    output procyon_cacheline_t           o_mhq_fill_data,

    // CCU interface
    input  logic                         i_ccu_done,
    input  procyon_cacheline_t           i_ccu_data,
    output logic                         o_ccu_en,
    output procyon_addr_t                o_ccu_addr
);

    procyon_mhq_entry_t [`MHQ_DEPTH-1:0] mhq_entries;
    procyon_mhq_tag_t                    mhq_tail;
    logic                                mhq_full;
    logic                                mhq_lu_en;
    logic                                mhq_lu_we;
    procyon_dc_offset_t                  mhq_lu_offset;
    procyon_data_t                       mhq_lu_wr_data;
    procyon_byte_select_t                mhq_lu_byte_select;
    logic                                mhq_lu_match;
    procyon_mhq_tag_select_t             mhq_lu_tag_select;
    logic                                mhq_lu_valid;
    logic                                mhq_lu_dirty;
    procyon_mhq_addr_t                   mhq_lu_addr;
    procyon_cacheline_t                  mhq_lu_data;
    procyon_dc_byte_select_t             mhq_lu_byte_updated;

    assign o_mhq_lookup_full             = mhq_full;

    mhq_lu mhq_lu_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_mhq_entries(mhq_entries),
        .i_mhq_tail(mhq_tail),
        .i_mhq_full(mhq_full),
        .i_mhq_ex_bypass_en(mhq_lu_en),
        .i_mhq_ex_bypass_we(mhq_lu_we),
        .i_mhq_ex_bypass_match(mhq_lu_match),
        .i_mhq_ex_bypass_addr(mhq_lu_addr),
        .i_mhq_ex_bypass_tag_select(mhq_lu_tag_select),
        .i_mhq_lookup_valid(i_mhq_lookup_valid),
        .i_mhq_lookup_dc_hit(i_mhq_lookup_dc_hit),
        .i_mhq_lookup_addr(i_mhq_lookup_addr),
        .i_mhq_lookup_lsu_func(i_mhq_lookup_lsu_func),
        .i_mhq_lookup_data(i_mhq_lookup_data),
        .i_mhq_lookup_we(i_mhq_lookup_we),
        .o_mhq_lu_en(mhq_lu_en),
        .o_mhq_lu_we(mhq_lu_we),
        .o_mhq_lu_offset(mhq_lu_offset),
        .o_mhq_lu_wr_data(mhq_lu_wr_data),
        .o_mhq_lu_byte_select(mhq_lu_byte_select),
        .o_mhq_lu_match(mhq_lu_match),
        .o_mhq_lu_tag(o_mhq_lookup_tag),
        .o_mhq_lu_tag_select(mhq_lu_tag_select),
        .o_mhq_lu_valid(mhq_lu_valid),
        .o_mhq_lu_dirty(mhq_lu_dirty),
        .o_mhq_lu_addr(mhq_lu_addr),
        .o_mhq_lu_data(mhq_lu_data),
        .o_mhq_lu_byte_updated(mhq_lu_byte_updated)
    );

    mhq_ex mhq_ex_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_mhq_entries(mhq_entries),
        .o_mhq_entries(mhq_entries),
        .o_mhq_tail(mhq_tail),
        .o_mhq_full(mhq_full),
        .i_mhq_lu_en(mhq_lu_en),
        .i_mhq_lu_we(mhq_lu_we),
        .i_mhq_lu_offset(mhq_lu_offset),
        .i_mhq_lu_wr_data(mhq_lu_wr_data),
        .i_mhq_lu_byte_select(mhq_lu_byte_select),
        .i_mhq_lu_match(mhq_lu_match),
        .i_mhq_lu_tag_select(mhq_lu_tag_select),
        .i_mhq_lu_valid(mhq_lu_valid),
        .i_mhq_lu_dirty(mhq_lu_dirty),
        .i_mhq_lu_addr(mhq_lu_addr),
        .i_mhq_lu_data(mhq_lu_data),
        .i_mhq_lu_byte_updated(mhq_lu_byte_updated),
        .o_mhq_fill_en(o_mhq_fill_en),
        .o_mhq_fill_tag(o_mhq_fill_tag),
        .o_mhq_fill_dirty(o_mhq_fill_dirty),
        .o_mhq_fill_addr(o_mhq_fill_addr),
        .o_mhq_fill_data(o_mhq_fill_data),
        .i_ccu_done(i_ccu_done),
        .i_ccu_data(i_ccu_data),
        .o_ccu_en(o_ccu_en),
        .o_ccu_addr(o_ccu_addr)
    );

endmodule
