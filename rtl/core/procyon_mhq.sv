// Miss Handling Queue
// Queue for loads or stores that miss in the cache
// Merges missed loads if the load address already exists in the queue
// Stores will be merged with existing entries as well
// The data read from memory will be merged with updated bytes in the entry from stores
// The MHQ consists of a two stage pipeline
// Lookup stage:
// - CAM for valid matching addresses and output tag, full and address info to next stage as well as to LSU_EX
// - The lsu_lq uses the MHQ tag information to wake up loads that missed in the cache and are waiting on fills from the MHQ
// Execute Stage:
// - Enqueue or merges if necessary and writes store retire data into the MHQ entry
// - Also handle merging write data with fill data from the BIU

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
    localparam DATA_SIZE       = OPTN_DATA_WIDTH / 8;

    logic [MHQ_IDX_WIDTH:0]                   mhq_head_next;
    logic [MHQ_IDX_WIDTH:0]                   mhq_tail_next;
    logic                                     mhq_entry_valid [0:OPTN_MHQ_DEPTH-1];
    logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] mhq_entry_addr  [0:OPTN_MHQ_DEPTH-1];
    logic                                     mhq_lu_en;
    logic                                     mhq_lu_we;
    logic [DC_OFFSET_WIDTH-1:0]               mhq_lu_offset;
    logic [OPTN_DATA_WIDTH-1:0]               mhq_lu_wr_data;
    logic [DATA_SIZE-1:0]                     mhq_lu_byte_select;
    logic                                     mhq_lu_match;
    logic [MHQ_IDX_WIDTH-1:0]                 mhq_lu_tag;
    logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] mhq_lu_addr;
    logic                                     mhq_lu_retry;
    logic [OPTN_ADDR_WIDTH-1:0]               biu_addr;

    // Output to BIU but also used by MHQ_LU
    assign o_biu_addr         = biu_addr;

    // Output to LSU
    assign o_mhq_lookup_retry = mhq_lu_retry;
    assign o_mhq_lookup_tag   = mhq_lu_tag;

    procyon_mhq_lu #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_MHQ_DEPTH(OPTN_MHQ_DEPTH),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE)
    ) procyon_mhq_lu_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_mhq_head_next(mhq_head_next),
        .i_mhq_tail_next(mhq_tail_next),
        .i_mhq_entry_valid(mhq_entry_valid),
        .i_mhq_entry_addr(mhq_entry_addr),
        .i_mhq_ex_bypass_en(mhq_lu_en),
        .i_mhq_ex_bypass_we(mhq_lu_we),
        .i_mhq_ex_bypass_match(mhq_lu_match),
        .i_mhq_ex_bypass_addr(mhq_lu_addr),
        .i_mhq_ex_bypass_tag(mhq_lu_tag),
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
        .o_mhq_lu_tag(mhq_lu_tag),
        .o_mhq_lu_addr(mhq_lu_addr),
        .o_mhq_lu_retry(mhq_lu_retry),
        .i_biu_done(i_biu_done),
        .i_biu_addr(biu_addr)
    );

    procyon_mhq_ex #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_MHQ_DEPTH(OPTN_MHQ_DEPTH),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE)
    ) procyon_mhq_ex_inst (
        .clk(clk),
        .n_rst(n_rst),
        .o_mhq_head_next(mhq_head_next),
        .o_mhq_tail_next(mhq_tail_next),
        .o_mhq_entry_valid(mhq_entry_valid),
        .o_mhq_entry_addr(mhq_entry_addr),
        .i_mhq_lu_en(mhq_lu_en),
        .i_mhq_lu_we(mhq_lu_we),
        .i_mhq_lu_offset(mhq_lu_offset),
        .i_mhq_lu_wr_data(mhq_lu_wr_data),
        .i_mhq_lu_byte_select(mhq_lu_byte_select),
        .i_mhq_lu_match(mhq_lu_match),
        .i_mhq_lu_tag(mhq_lu_tag),
        .i_mhq_lu_addr(mhq_lu_addr),
        .o_mhq_fill_en(o_mhq_fill_en),
        .o_mhq_fill_tag(o_mhq_fill_tag),
        .o_mhq_fill_dirty(o_mhq_fill_dirty),
        .o_mhq_fill_addr(o_mhq_fill_addr),
        .o_mhq_fill_data(o_mhq_fill_data),
        .i_biu_done(i_biu_done),
        .i_biu_data(i_biu_data),
        .o_biu_en(o_biu_en),
        .o_biu_addr(biu_addr)
    );

endmodule
