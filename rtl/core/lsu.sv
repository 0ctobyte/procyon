// Load/Store Unit
// Encapsulates the ID, D0, D1, EX pipeline stages and the Load Queue and Store Queue and D$

`include "procyon_constants.svh"

module lsu #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_LQ_DEPTH      = 8,
    parameter OPTN_SQ_DEPTH      = 8,
    parameter OPTN_DC_CACHE_SIZE = 1024,
    parameter OPTN_DC_LINE_SIZE  = 32,
    parameter OPTN_DC_WAY_COUNT  = 1,
    parameter OPTN_ROB_IDX_WIDTH = 5,
    parameter OPTN_MHQ_IDX_WIDTH = 2,

    localparam DC_LINE_WIDTH     = OPTN_DC_LINE_SIZE * 8
)(
    input  logic                            clk,
    input  logic                            n_rst,

    input  logic                            i_flush,

    // Common Data Bus
    output logic                            o_cdb_en,
    output logic                            o_cdb_redirect,
    output logic [OPTN_DATA_WIDTH-1:0]      o_cdb_data,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_cdb_addr,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]   o_cdb_tag,

    input  logic                            i_fu_valid,
    input  logic [`PCYN_OPCODE_WIDTH-1:0]   i_fu_opcode,
/* verilator lint_off UNUSED */
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_fu_iaddr,
/* verilator lint_on  UNUSED */
    input  logic [OPTN_DATA_WIDTH-1:0]      i_fu_insn,
    input  logic [OPTN_DATA_WIDTH-1:0]      i_fu_src_a,
    input  logic [OPTN_DATA_WIDTH-1:0]      i_fu_src_b,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]   i_fu_tag,
    output logic                            o_fu_stall,

    // ROB retirement interface
    input  logic                            i_rob_retire_lq_en,
    input  logic                            i_rob_retire_sq_en,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]   i_rob_retire_tag,
    output logic                            o_rob_retire_lq_ack,
    output logic                            o_rob_retire_sq_ack,
    output logic                            o_rob_retire_misspeculated,

    // MHQ address/tag lookup interface
    input  logic                            i_mhq_lookup_retry,
    input  logic [OPTN_MHQ_IDX_WIDTH-1:0]   i_mhq_lookup_tag,
    output logic                            o_mhq_lookup_valid,
    output logic                            o_mhq_lookup_dc_hit,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_mhq_lookup_addr,
    output logic [`PCYN_LSU_FUNC_WIDTH-1:0] o_mhq_lookup_lsu_func,
    output logic [OPTN_DATA_WIDTH-1:0]      o_mhq_lookup_data,
    output logic                            o_mhq_lookup_we,

    // MHQ fill interface
    input  logic                            i_mhq_fill_en,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_mhq_fill_addr,
    input  logic [OPTN_MHQ_IDX_WIDTH-1:0]   i_mhq_fill_tag,
    input  logic [DC_LINE_WIDTH-1:0]        i_mhq_fill_data,
    input  logic                            i_mhq_fill_dirty
);

    logic                            sq_full;
    logic                            sq_retire_en;
    logic [OPTN_ROB_IDX_WIDTH-1:0]   sq_retire_tag;
    logic [OPTN_DATA_WIDTH-1:0]      sq_retire_data;
    logic [OPTN_ADDR_WIDTH-1:0]      sq_retire_addr;
    logic [`PCYN_LSU_FUNC_WIDTH-1:0] sq_retire_lsu_func;
    logic [OPTN_SQ_DEPTH-1:0]        sq_retire_select;
    logic                            sq_retire_stall;
    logic                            lq_full;
    logic                            lq_replay_en;
    logic [OPTN_ROB_IDX_WIDTH-1:0]   lq_replay_tag;
    logic [OPTN_ADDR_WIDTH-1:0]      lq_replay_addr;
    logic [`PCYN_LSU_FUNC_WIDTH-1:0] lq_replay_lsu_func;
    logic [OPTN_LQ_DEPTH-1:0]        lq_replay_select;
    logic                            lq_replay_stall;
    logic                            lsu_ad_valid;
    logic [`PCYN_LSU_FUNC_WIDTH-1:0] lsu_ad_lsu_func;
    logic [OPTN_LQ_DEPTH-1:0]        lsu_ad_lq_select;
    logic [OPTN_SQ_DEPTH-1:0]        lsu_ad_sq_select;
    logic [OPTN_ROB_IDX_WIDTH-1:0]   lsu_ad_tag;
    logic [OPTN_ADDR_WIDTH-1:0]      lsu_ad_addr;
    logic [OPTN_DATA_WIDTH-1:0]      lsu_ad_retire_data;
    logic                            lsu_ad_retire;
    logic                            lsu_ad_replay;
    logic                            lsu_d0_valid;
    logic [`PCYN_LSU_FUNC_WIDTH-1:0] lsu_d0_lsu_func;
    logic [OPTN_LQ_DEPTH-1:0]        lsu_d0_lq_select;
    logic [OPTN_SQ_DEPTH-1:0]        lsu_d0_sq_select;
    logic [OPTN_ROB_IDX_WIDTH-1:0]   lsu_d0_tag;
    logic [OPTN_ADDR_WIDTH-1:0]      lsu_d0_addr;
    logic [OPTN_DATA_WIDTH-1:0]      lsu_d0_retire_data;
    logic                            lsu_d0_retire;
    logic                            lsu_d0_replay;
    logic                            lsu_d1_valid;
    logic [`PCYN_LSU_FUNC_WIDTH-1:0] lsu_d1_lsu_func;
    logic [OPTN_LQ_DEPTH-1:0]        lsu_d1_lq_select;
    logic [OPTN_SQ_DEPTH-1:0]        lsu_d1_sq_select;
    logic [OPTN_ROB_IDX_WIDTH-1:0]   lsu_d1_tag;
    logic [OPTN_ADDR_WIDTH-1:0]      lsu_d1_addr;
    logic [OPTN_DATA_WIDTH-1:0]      lsu_d1_retire_data;
    logic                            lsu_d1_retire;
    logic                            dc_wr_en;
    logic [OPTN_ADDR_WIDTH-1:0]      dc_addr;
    logic [`PCYN_LSU_FUNC_WIDTH-1:0] dc_lsu_func;
    logic [OPTN_DATA_WIDTH-1:0]      dc_wr_data;
    logic                            dc_valid;
    logic                            dc_dirty;
    logic                            dc_fill;
    logic [DC_LINE_WIDTH-1:0]        dc_fill_data;
    logic                            dc_hit;
    logic [OPTN_DATA_WIDTH-1:0]      dc_rd_data;
    logic                            dc_victim_valid;
    logic                            dc_victim_dirty;
    logic [OPTN_ADDR_WIDTH-1:0]      dc_victim_addr;
    logic [DC_LINE_WIDTH-1:0]        dc_victim_data;
    logic                            alloc_sq_en;
    logic                            alloc_lq_en;
    logic [`PCYN_LSU_FUNC_WIDTH-1:0] alloc_lsu_func;
    logic [OPTN_ROB_IDX_WIDTH-1:0]   alloc_tag;
    logic [OPTN_ADDR_WIDTH-1:0]      alloc_addr;
    logic [OPTN_DATA_WIDTH-1:0]      alloc_data;
    logic [OPTN_LQ_DEPTH-1:0]        alloc_lq_select;
    logic                            update_lq_en;
    logic [OPTN_LQ_DEPTH-1:0]        update_lq_select;
    logic                            update_lq_retry;
    logic                            update_sq_en;
    logic [OPTN_SQ_DEPTH-1:0]        update_sq_select;
    logic                            update_sq_retry;
/* verilator lint_off UNUSED */
    logic                            victim_en;
    logic [OPTN_ADDR_WIDTH-1:0]      victim_addr;
    logic [DC_LINE_WIDTH-1:0]        victim_data;
/* verilator lint_on  UNUSED */

    assign o_cdb_redirect        = 1'b0;

    // Outputs to the MHQ lookup interface
    assign o_mhq_lookup_valid    = lsu_d1_valid;
    assign o_mhq_lookup_dc_hit   = dc_hit;
    assign o_mhq_lookup_addr     = lsu_d1_addr;
    assign o_mhq_lookup_lsu_func = lsu_d1_lsu_func;
    assign o_mhq_lookup_data     = lsu_d1_retire_data;
    assign o_mhq_lookup_we       = lsu_d1_retire;

    lsu_ad #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_LQ_DEPTH(OPTN_LQ_DEPTH),
        .OPTN_SQ_DEPTH(OPTN_SQ_DEPTH),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE),
        .OPTN_ROB_IDX_WIDTH(OPTN_ROB_IDX_WIDTH)
    ) lsu_ad_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .i_valid(i_fu_valid),
        .i_lq_full(lq_full),
        .i_sq_full(sq_full),
        .i_insn(i_fu_insn),
        .i_opcode(i_fu_opcode),
        .i_src_a(i_fu_src_a),
        .i_src_b(i_fu_src_b),
        .i_tag(i_fu_tag),
        .o_stall(o_fu_stall),
        .i_mhq_fill_en(i_mhq_fill_en),
        .i_mhq_fill_addr(i_mhq_fill_addr),
        .i_mhq_fill_data(i_mhq_fill_data),
        .i_mhq_fill_dirty(i_mhq_fill_dirty),
        .i_sq_retire_en(sq_retire_en),
        .i_sq_retire_tag(sq_retire_tag),
        .i_sq_retire_data(sq_retire_data),
        .i_sq_retire_addr(sq_retire_addr),
        .i_sq_retire_lsu_func(sq_retire_lsu_func),
        .i_sq_retire_select(sq_retire_select),
        .o_sq_retire_stall(sq_retire_stall),
        .i_lq_replay_en(lq_replay_en),
        .i_lq_replay_tag(lq_replay_tag),
        .i_lq_replay_addr(lq_replay_addr),
        .i_lq_replay_lsu_func(lq_replay_lsu_func),
        .i_lq_replay_select(lq_replay_select),
        .o_lq_replay_stall(lq_replay_stall),
        .o_valid(lsu_ad_valid),
        .o_lsu_func(lsu_ad_lsu_func),
        .o_lq_select(lsu_ad_lq_select),
        .o_sq_select(lsu_ad_sq_select),
        .o_tag(lsu_ad_tag),
        .o_addr(lsu_ad_addr),
        .o_retire_data(lsu_ad_retire_data),
        .o_retire(lsu_ad_retire),
        .o_replay(lsu_ad_replay),
        .o_dc_wr_en(dc_wr_en),
        .o_dc_addr(dc_addr),
        .o_dc_lsu_func(dc_lsu_func),
        .o_dc_data(dc_wr_data),
        .o_dc_valid(dc_valid),
        .o_dc_dirty(dc_dirty),
        .o_dc_fill(dc_fill),
        .o_dc_fill_data(dc_fill_data),
        .o_alloc_sq_en(alloc_sq_en),
        .o_alloc_lq_en(alloc_lq_en),
        .o_alloc_lsu_func(alloc_lsu_func),
        .o_alloc_tag(alloc_tag),
        .o_alloc_data(alloc_data),
        .o_alloc_addr(alloc_addr)
    );

    lsu_d0 #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_LQ_DEPTH(OPTN_LQ_DEPTH),
        .OPTN_SQ_DEPTH(OPTN_SQ_DEPTH),
        .OPTN_ROB_IDX_WIDTH(OPTN_ROB_IDX_WIDTH)
    ) lsu_d0_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .i_valid(lsu_ad_valid),
        .i_lsu_func(lsu_ad_lsu_func),
        .i_lq_select(lsu_ad_lq_select),
        .i_sq_select(lsu_ad_sq_select),
        .i_tag(lsu_ad_tag),
        .i_addr(lsu_ad_addr),
        .i_retire_data(lsu_ad_retire_data),
        .i_retire(lsu_ad_retire),
        .i_replay(lsu_ad_replay),
        .o_valid(lsu_d0_valid),
        .o_lsu_func(lsu_d0_lsu_func),
        .o_lq_select(lsu_d0_lq_select),
        .o_sq_select(lsu_d0_sq_select),
        .o_tag(lsu_d0_tag),
        .o_addr(lsu_d0_addr),
        .o_retire_data(lsu_d0_retire_data),
        .o_retire(lsu_d0_retire),
        .o_replay(lsu_d0_replay)
    );

    lsu_d1 #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_LQ_DEPTH(OPTN_LQ_DEPTH),
        .OPTN_SQ_DEPTH(OPTN_SQ_DEPTH),
        .OPTN_ROB_IDX_WIDTH(OPTN_ROB_IDX_WIDTH)
    ) lsu_d1_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .i_valid(lsu_d0_valid),
        .i_lsu_func(lsu_d0_lsu_func),
        .i_lq_select(lsu_d0_lq_select),
        .i_sq_select(lsu_d0_sq_select),
        .i_tag(lsu_d0_tag),
        .i_addr(lsu_d0_addr),
        .i_retire_data(lsu_d0_retire_data),
        .i_retire(lsu_d0_retire),
        .i_replay(lsu_d0_replay),
        .i_alloc_lq_select(alloc_lq_select),
        .o_valid(lsu_d1_valid),
        .o_lsu_func(lsu_d1_lsu_func),
        .o_lq_select(lsu_d1_lq_select),
        .o_sq_select(lsu_d1_sq_select),
        .o_tag(lsu_d1_tag),
        .o_addr(lsu_d1_addr),
        .o_retire_data(lsu_d1_retire_data),
        .o_retire(lsu_d1_retire)
    );

    lsu_ex #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_LQ_DEPTH(OPTN_LQ_DEPTH),
        .OPTN_SQ_DEPTH(OPTN_SQ_DEPTH),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE),
        .OPTN_ROB_IDX_WIDTH(OPTN_ROB_IDX_WIDTH)
    ) lsu_ex_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .i_valid(lsu_d1_valid),
        .i_lsu_func(lsu_d1_lsu_func),
        .i_lq_select(lsu_d1_lq_select),
        .i_sq_select(lsu_d1_sq_select),
        .i_tag(lsu_d1_tag),
        .i_addr(lsu_d1_addr),
        .i_retire(lsu_d1_retire),
        .i_dc_hit(dc_hit),
        .i_dc_data(dc_rd_data),
        .i_dc_victim_valid(dc_victim_valid),
        .i_dc_victim_dirty(dc_victim_dirty),
        .i_dc_victim_addr(dc_victim_addr),
        .i_dc_victim_data(dc_victim_data),
        .o_valid(o_cdb_en),
        .o_data(o_cdb_data),
        .o_addr(o_cdb_addr),
        .o_tag(o_cdb_tag),
        .o_update_lq_en(update_lq_en),
        .o_update_lq_select(update_lq_select),
        .o_update_lq_retry(update_lq_retry),
        .o_update_sq_en(update_sq_en),
        .o_update_sq_select(update_sq_select),
        .o_update_sq_retry(update_sq_retry),
        .o_victim_en(victim_en),
        .o_victim_addr(victim_addr),
        .o_victim_data(victim_data)
    );

    lsu_lq #(
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_LQ_DEPTH(OPTN_LQ_DEPTH),
        .OPTN_SQ_DEPTH(OPTN_SQ_DEPTH),
        .OPTN_ROB_IDX_WIDTH(OPTN_ROB_IDX_WIDTH),
        .OPTN_MHQ_IDX_WIDTH(OPTN_MHQ_IDX_WIDTH)
    ) lsu_lq_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .o_full(lq_full),
        .i_alloc_en(alloc_lq_en),
        .i_alloc_lsu_func(alloc_lsu_func),
        .i_alloc_tag(alloc_tag),
        .i_alloc_addr(alloc_addr),
        .o_alloc_lq_select(alloc_lq_select),
        .i_replay_stall(lq_replay_stall),
        .o_replay_en(lq_replay_en),
        .o_replay_select(lq_replay_select),
        .o_replay_lsu_func(lq_replay_lsu_func),
        .o_replay_addr(lq_replay_addr),
        .o_replay_tag(lq_replay_tag),
        .i_update_en(update_lq_en),
        .i_update_select(update_lq_select),
        .i_update_retry(update_lq_retry),
        .i_update_mhq_tag(i_mhq_lookup_tag),
        .i_update_mhq_retry(i_mhq_lookup_retry),
        .i_mhq_fill_en(i_mhq_fill_en),
        .i_mhq_fill_tag(i_mhq_fill_tag),
        .i_sq_retire_en(sq_retire_en),
        .i_sq_retire_addr(sq_retire_addr),
        .i_sq_retire_lsu_func(sq_retire_lsu_func),
        .i_rob_retire_en(i_rob_retire_lq_en),
        .i_rob_retire_tag(i_rob_retire_tag),
        .o_rob_retire_ack(o_rob_retire_lq_ack),
        .o_rob_retire_misspeculated(o_rob_retire_misspeculated)
    );

    lsu_sq #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_SQ_DEPTH(OPTN_SQ_DEPTH),
        .OPTN_ROB_IDX_WIDTH(OPTN_ROB_IDX_WIDTH)
    ) lsu_sq_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .o_full(sq_full),
        .i_alloc_en(alloc_sq_en),
        .i_alloc_lsu_func(alloc_lsu_func),
        .i_alloc_tag(alloc_tag),
        .i_alloc_addr(alloc_addr),
        .i_alloc_data(alloc_data),
        .i_sq_retire_stall(sq_retire_stall),
        .o_sq_retire_en(sq_retire_en),
        .o_sq_retire_select(sq_retire_select),
        .o_sq_retire_lsu_func(sq_retire_lsu_func),
        .o_sq_retire_addr(sq_retire_addr),
        .o_sq_retire_tag(sq_retire_tag),
        .o_sq_retire_data(sq_retire_data),
        .i_update_en(update_sq_en),
        .i_update_select(update_sq_select),
        .i_update_retry(update_sq_retry),
        .i_update_mhq_retry(i_mhq_lookup_retry),
        .i_mhq_fill_en(i_mhq_fill_en),
        .i_rob_retire_en(i_rob_retire_sq_en),
        .i_rob_retire_tag(i_rob_retire_tag),
        .o_rob_retire_ack(o_rob_retire_sq_ack)
    );

    dcache #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_DC_CACHE_SIZE(OPTN_DC_CACHE_SIZE),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE),
        .OPTN_DC_WAY_COUNT(OPTN_DC_WAY_COUNT)
    ) dcache_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_dc_wr_en(dc_wr_en),
        .i_dc_addr(dc_addr),
        .i_dc_lsu_func(dc_lsu_func),
        .i_dc_data(dc_wr_data),
        .i_dc_valid(dc_valid),
        .i_dc_dirty(dc_dirty),
        .i_dc_fill(dc_fill),
        .i_dc_fill_data(dc_fill_data),
        .o_dc_hit(dc_hit),
        .o_dc_data(dc_rd_data),
        .o_dc_victim_valid(dc_victim_valid),
        .o_dc_victim_dirty(dc_victim_dirty),
        .o_dc_victim_addr(dc_victim_addr),
        .o_dc_victim_data(dc_victim_data)
    );

endmodule
