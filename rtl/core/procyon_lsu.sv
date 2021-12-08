/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Load/Store Unit
// Encapsulates the AM, DT, DW, EX pipeline stages and the Load Queue and Store Queue and D$

/* verilator lint_off IMPORTSTAR */
import procyon_lib_pkg::*;
import procyon_core_pkg::*;
/* verilator lint_on  IMPORTSTAR */

module procyon_lsu #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_LQ_DEPTH      = 8,
    parameter OPTN_SQ_DEPTH      = 8,
    parameter OPTN_DC_CACHE_SIZE = 1024,
    parameter OPTN_DC_LINE_SIZE  = 32,
    parameter OPTN_DC_WAY_COUNT  = 1,
    parameter OPTN_ROB_IDX_WIDTH = 5,
    parameter OPTN_MHQ_IDX_WIDTH = 2
)(
    input  logic                                   clk,
    input  logic                                   n_rst,

    input  logic                                   i_flush,

    // Common Data Bus
    output logic                                    o_cdb_en,
    output logic                                    o_cdb_redirect,
    output logic [OPTN_DATA_WIDTH-1:0]              o_cdb_data,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]           o_cdb_tag,

    input  logic                                    i_fu_valid,
    input  pcyn_op_t                                i_fu_op,
    input  pcyn_op_is_t                             i_fu_op_is,
    input  logic [OPTN_DATA_WIDTH-1:0]              i_fu_imm,
    input  logic [OPTN_DATA_WIDTH-1:0]              i_fu_src [0:1],
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]           i_fu_tag,
    output logic                                    o_fu_stall,

    // ROB retirement interface
    input  logic                                    i_rob_retire_lq_en,
    input  logic                                    i_rob_retire_sq_en,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]           i_rob_retire_tag,
    output logic                                    o_rob_retire_lq_ack,
    output logic                                    o_rob_retire_sq_ack,
    output logic                                    o_rob_retire_misspeculated,

    // VQ lookup interface
    input  logic                                    i_vq_lookup_hit,
    input  logic [OPTN_DATA_WIDTH-1:0]              i_vq_lookup_data,
    output logic                                    o_vq_lookup_valid,
    output logic [OPTN_ADDR_WIDTH-1:0]              o_vq_lookup_addr,
    output logic [`PCYN_W2S(OPTN_DATA_WIDTH)-1:0]   o_vq_lookup_byte_sel,

    // Victim cacheline interface
    output logic                                    o_victim_valid,
    output logic [OPTN_ADDR_WIDTH-1:0]              o_victim_addr,
    output logic [`PCYN_S2W(OPTN_DC_LINE_SIZE)-1:0] o_victim_data,

    // MHQ address/tag lookup interface
    input  logic                                    i_mhq_lookup_retry,
    input  logic                                    i_mhq_lookup_replay,
    input  logic [OPTN_MHQ_IDX_WIDTH-1:0]           i_mhq_lookup_tag,
    output logic                                    o_mhq_lookup_valid,
    output logic                                    o_mhq_lookup_dc_hit,
    output logic [OPTN_ADDR_WIDTH-1:0]              o_mhq_lookup_addr,
    output pcyn_op_t                                o_mhq_lookup_op,
    output logic [OPTN_DATA_WIDTH-1:0]              o_mhq_lookup_data,
    output logic                                    o_mhq_lookup_we,

    // MHQ fill interface
    input  logic                                    i_mhq_fill_en,
    input  logic [OPTN_ADDR_WIDTH-1:0]              i_mhq_fill_addr,
    input  logic [OPTN_MHQ_IDX_WIDTH-1:0]           i_mhq_fill_tag,
    input  logic [`PCYN_S2W(OPTN_DC_LINE_SIZE)-1:0] i_mhq_fill_data,
    input  logic                                    i_mhq_fill_dirty
);

    localparam DC_LINE_WIDTH = `PCYN_S2W(OPTN_DC_LINE_SIZE);
    localparam DATA_SIZE = `PCYN_W2S(OPTN_DATA_WIDTH);

    logic sq_full;
    logic sq_nonspeculative_pending;
    logic sq_retire_en;
    logic [OPTN_ROB_IDX_WIDTH-1:0] sq_retire_tag;
    logic [OPTN_DATA_WIDTH-1:0] sq_retire_data;
    logic [OPTN_ADDR_WIDTH-1:0] sq_retire_addr;
    pcyn_op_t sq_retire_op;
    logic [OPTN_SQ_DEPTH-1:0] sq_retire_select;
    logic sq_retire_stall;
    logic lq_full;
    logic lq_replay_en;
    logic [OPTN_ROB_IDX_WIDTH-1:0] lq_replay_tag;
    logic [OPTN_ADDR_WIDTH-1:0] lq_replay_addr;
    pcyn_op_t lq_replay_op;
    logic [OPTN_LQ_DEPTH-1:0] lq_replay_select;
    logic lq_replay_stall;
    logic lsu_am_valid;
    pcyn_op_t lsu_am_op;
    pcyn_op_is_t lsu_am_op_is;
    logic [OPTN_LQ_DEPTH-1:0] lsu_am_lq_select;
    logic [OPTN_SQ_DEPTH-1:0] lsu_am_sq_select;
    logic [OPTN_ROB_IDX_WIDTH-1:0] lsu_am_tag;
    logic [OPTN_ADDR_WIDTH-1:0] lsu_am_addr;
    logic [OPTN_DATA_WIDTH-1:0] lsu_am_retire_data;
    logic lsu_am_retire;
    logic lsu_am_replay;
    logic lsu_dt_valid;
    logic lsu_dt_fill_replay;
    pcyn_op_t lsu_dt_op;
    pcyn_op_is_t lsu_dt_op_is;
    logic [OPTN_LQ_DEPTH-1:0] lsu_dt_lq_select;
    logic [OPTN_SQ_DEPTH-1:0] lsu_dt_sq_select;
    logic [OPTN_ROB_IDX_WIDTH-1:0] lsu_dt_tag;
    logic [OPTN_ADDR_WIDTH-1:0] lsu_dt_addr;
    logic [OPTN_DATA_WIDTH-1:0] lsu_dt_retire_data;
    logic lsu_dt_retire;
    logic lsu_dt_replay;
    logic lsu_dw_valid;
    logic lsu_dw_mhq_lookup_valid;
    logic lsu_dw_fill_replay;
    pcyn_op_t lsu_dw_op;
    pcyn_op_is_t lsu_dw_op_is;
    logic [OPTN_LQ_DEPTH-1:0] lsu_dw_lq_select;
    logic [OPTN_SQ_DEPTH-1:0] lsu_dw_sq_select;
    logic [OPTN_ROB_IDX_WIDTH-1:0] lsu_dw_tag;
    logic [OPTN_ADDR_WIDTH-1:0] lsu_dw_addr;
    logic [OPTN_DATA_WIDTH-1:0] lsu_dw_retire_data;
    logic lsu_dw_retire;
    logic [OPTN_ADDR_WIDTH-1:`PCYN_DC_OFFSET_WIDTH] lsu_mhq_fill_addr;
    logic dc_wr_en;
    logic [DATA_SIZE-1:0] dc_dt_byte_sel;
    logic dc_dirty;
    logic dc_fill;
    logic [DC_LINE_WIDTH-1:0] dc_fill_data;
    logic dc_hit;
    logic [OPTN_DATA_WIDTH-1:0] dc_rd_data;
    logic alloc_sq_en;
    logic alloc_lq_en;
    pcyn_op_t alloc_op;
    logic [OPTN_ROB_IDX_WIDTH-1:0] alloc_tag;
    logic [OPTN_ADDR_WIDTH-1:0] alloc_addr;
    logic [OPTN_DATA_WIDTH-1:0] alloc_data;
    logic [OPTN_LQ_DEPTH-1:0] alloc_lq_select;
    logic update_lq_en;
    logic [OPTN_LQ_DEPTH-1:0] update_lq_select;
    logic update_sq_en;
    logic [OPTN_SQ_DEPTH-1:0] update_sq_select;
    logic update_retry;
    logic update_replay;
/* verilator lint_off UNUSED */
    logic victim_en;
    logic [OPTN_ADDR_WIDTH-1:0] victim_addr;
    logic [DC_LINE_WIDTH-1:0] victim_data;
/* verilator lint_on  UNUSED */

    assign o_cdb_redirect = 1'b0;

    assign lsu_mhq_fill_addr = i_mhq_fill_addr[OPTN_ADDR_WIDTH-1:`PCYN_DC_OFFSET_WIDTH];

    // Output to the VQ lookup interface
    assign o_vq_lookup_valid = lsu_dt_valid & lsu_dt_op_is[PCYN_OP_IS_LD_IDX];
    assign o_vq_lookup_addr = lsu_dt_addr;
    assign o_vq_lookup_byte_sel = dc_dt_byte_sel;

    // Outputs to the MHQ lookup interface
    assign o_mhq_lookup_valid = lsu_dw_mhq_lookup_valid;
    assign o_mhq_lookup_dc_hit = dc_hit;
    assign o_mhq_lookup_addr = lsu_dw_addr;
    assign o_mhq_lookup_op = lsu_dw_op;
    assign o_mhq_lookup_data = lsu_dw_retire_data;
    assign o_mhq_lookup_we = lsu_dw_retire;

    procyon_lsu_am #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_LQ_DEPTH(OPTN_LQ_DEPTH),
        .OPTN_SQ_DEPTH(OPTN_SQ_DEPTH),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE),
        .OPTN_ROB_IDX_WIDTH(OPTN_ROB_IDX_WIDTH)
    ) procyon_lsu_am_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .i_lq_full(lq_full),
        .i_sq_full(sq_full),
        .i_valid(i_fu_valid),
        .i_op(i_fu_op),
        .i_op_is(i_fu_op_is),
        .i_imm(i_fu_imm),
        .i_src(i_fu_src),
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
        .i_sq_retire_op(sq_retire_op),
        .i_sq_retire_select(sq_retire_select),
        .o_sq_retire_stall(sq_retire_stall),
        .i_lq_replay_en(lq_replay_en),
        .i_lq_replay_tag(lq_replay_tag),
        .i_lq_replay_addr(lq_replay_addr),
        .i_lq_replay_op(lq_replay_op),
        .i_lq_replay_select(lq_replay_select),
        .o_lq_replay_stall(lq_replay_stall),
        .o_valid(lsu_am_valid),
        .o_op(lsu_am_op),
        .o_op_is(lsu_am_op_is),
        .o_lq_select(lsu_am_lq_select),
        .o_sq_select(lsu_am_sq_select),
        .o_tag(lsu_am_tag),
        .o_addr(lsu_am_addr),
        .o_retire_data(lsu_am_retire_data),
        .o_retire(lsu_am_retire),
        .o_replay(lsu_am_replay),
        .o_dc_wr_en(dc_wr_en),
        .o_dc_dirty(dc_dirty),
        .o_dc_fill(dc_fill),
        .o_dc_fill_data(dc_fill_data),
        .o_alloc_sq_en(alloc_sq_en),
        .o_alloc_lq_en(alloc_lq_en),
        .o_alloc_op(alloc_op),
        .o_alloc_tag(alloc_tag),
        .o_alloc_data(alloc_data),
        .o_alloc_addr(alloc_addr)
    );

    procyon_lsu_dt #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_LQ_DEPTH(OPTN_LQ_DEPTH),
        .OPTN_SQ_DEPTH(OPTN_SQ_DEPTH),
        .OPTN_ROB_IDX_WIDTH(OPTN_ROB_IDX_WIDTH),
        .OPTN_DC_OFFSET_WIDTH(`PCYN_DC_OFFSET_WIDTH)
    ) procyon_lsu_dt_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .i_mhq_fill_en(i_mhq_fill_en),
        .i_mhq_fill_addr(lsu_mhq_fill_addr),
        .i_valid(lsu_am_valid),
        .i_op(lsu_am_op),
        .i_op_is(lsu_am_op_is),
        .i_lq_select(lsu_am_lq_select),
        .i_sq_select(lsu_am_sq_select),
        .i_tag(lsu_am_tag),
        .i_addr(lsu_am_addr),
        .i_retire_data(lsu_am_retire_data),
        .i_retire(lsu_am_retire),
        .i_replay(lsu_am_replay),
        .o_valid(lsu_dt_valid),
        .o_fill_replay(lsu_dt_fill_replay),
        .o_op(lsu_dt_op),
        .o_op_is(lsu_dt_op_is),
        .o_lq_select(lsu_dt_lq_select),
        .o_sq_select(lsu_dt_sq_select),
        .o_tag(lsu_dt_tag),
        .o_addr(lsu_dt_addr),
        .o_retire_data(lsu_dt_retire_data),
        .o_retire(lsu_dt_retire),
        .o_replay(lsu_dt_replay)
    );

    procyon_lsu_dw #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_LQ_DEPTH(OPTN_LQ_DEPTH),
        .OPTN_SQ_DEPTH(OPTN_SQ_DEPTH),
        .OPTN_ROB_IDX_WIDTH(OPTN_ROB_IDX_WIDTH),
        .OPTN_DC_OFFSET_WIDTH(`PCYN_DC_OFFSET_WIDTH)
    ) procyon_lsu_dw_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .i_mhq_fill_en(i_mhq_fill_en),
        .i_mhq_fill_addr(lsu_mhq_fill_addr),
        .i_valid(lsu_dt_valid),
        .i_fill_replay(lsu_dt_fill_replay),
        .i_op(lsu_dt_op),
        .i_op_is(lsu_dt_op_is),
        .i_lq_select(lsu_dt_lq_select),
        .i_sq_select(lsu_dt_sq_select),
        .i_tag(lsu_dt_tag),
        .i_addr(lsu_dt_addr),
        .i_retire_data(lsu_dt_retire_data),
        .i_retire(lsu_dt_retire),
        .i_replay(lsu_dt_replay),
        .i_alloc_lq_select(alloc_lq_select),
        .o_valid(lsu_dw_valid),
        .o_mhq_lookup_valid(lsu_dw_mhq_lookup_valid),
        .o_fill_replay(lsu_dw_fill_replay),
        .o_op(lsu_dw_op),
        .o_op_is(lsu_dw_op_is),
        .o_lq_select(lsu_dw_lq_select),
        .o_sq_select(lsu_dw_sq_select),
        .o_tag(lsu_dw_tag),
        .o_addr(lsu_dw_addr),
        .o_retire_data(lsu_dw_retire_data),
        .o_retire(lsu_dw_retire)
    );

    procyon_lsu_ex #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_LQ_DEPTH(OPTN_LQ_DEPTH),
        .OPTN_SQ_DEPTH(OPTN_SQ_DEPTH),
        .OPTN_ROB_IDX_WIDTH(OPTN_ROB_IDX_WIDTH)
    ) procyon_lsu_ex_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .i_valid(lsu_dw_valid),
        .i_fill_replay(lsu_dw_fill_replay),
        .i_op(lsu_dw_op),
        .i_op_is(lsu_dw_op_is),
        .i_lq_select(lsu_dw_lq_select),
        .i_sq_select(lsu_dw_sq_select),
        .i_tag(lsu_dw_tag),
        .i_retire(lsu_dw_retire),
        .i_dc_hit(dc_hit),
        .i_dc_data(dc_rd_data),
        .i_vq_hit(i_vq_lookup_hit),
        .i_vq_data(i_vq_lookup_data),
        .o_valid(o_cdb_en),
        .o_data(o_cdb_data),
        .o_tag(o_cdb_tag),
        .o_update_lq_en(update_lq_en),
        .o_update_lq_select(update_lq_select),
        .o_update_sq_en(update_sq_en),
        .o_update_sq_select(update_sq_select),
        .o_update_retry(update_retry),
        .o_update_replay(update_replay)
    );

    procyon_lsu_lq #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_LQ_DEPTH(OPTN_LQ_DEPTH),
        .OPTN_ROB_IDX_WIDTH(OPTN_ROB_IDX_WIDTH),
        .OPTN_MHQ_IDX_WIDTH(OPTN_MHQ_IDX_WIDTH)
    ) procyon_lsu_lq_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .i_sq_nonspeculative_pending(sq_nonspeculative_pending),
        .o_full(lq_full),
        .i_alloc_en(alloc_lq_en),
        .i_alloc_op(alloc_op),
        .i_alloc_tag(alloc_tag),
        .i_alloc_addr(alloc_addr),
        .o_alloc_lq_select(alloc_lq_select),
        .i_replay_stall(lq_replay_stall),
        .o_replay_en(lq_replay_en),
        .o_replay_select(lq_replay_select),
        .o_replay_op(lq_replay_op),
        .o_replay_addr(lq_replay_addr),
        .o_replay_tag(lq_replay_tag),
        .i_update_en(update_lq_en),
        .i_update_select(update_lq_select),
        .i_update_retry(update_retry),
        .i_update_replay(update_replay),
        .i_update_mhq_tag(i_mhq_lookup_tag),
        .i_update_mhq_retry(i_mhq_lookup_retry),
        .i_update_mhq_replay(i_mhq_lookup_replay),
        .i_mhq_fill_en(i_mhq_fill_en),
        .i_mhq_fill_tag(i_mhq_fill_tag),
        .i_sq_retire_en(sq_retire_en),
        .i_sq_retire_addr(sq_retire_addr),
        .i_sq_retire_op(sq_retire_op),
        .i_rob_retire_en(i_rob_retire_lq_en),
        .i_rob_retire_tag(i_rob_retire_tag),
        .o_rob_retire_ack(o_rob_retire_lq_ack),
        .o_rob_retire_misspeculated(o_rob_retire_misspeculated)
    );

    procyon_lsu_sq #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_SQ_DEPTH(OPTN_SQ_DEPTH),
        .OPTN_ROB_IDX_WIDTH(OPTN_ROB_IDX_WIDTH)
    ) procyon_lsu_sq_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .o_full(sq_full),
        .o_nonspeculative_pending(sq_nonspeculative_pending),
        .i_alloc_en(alloc_sq_en),
        .i_alloc_op(alloc_op),
        .i_alloc_tag(alloc_tag),
        .i_alloc_addr(alloc_addr),
        .i_alloc_data(alloc_data),
        .i_sq_retire_stall(sq_retire_stall),
        .o_sq_retire_en(sq_retire_en),
        .o_sq_retire_select(sq_retire_select),
        .o_sq_retire_op(sq_retire_op),
        .o_sq_retire_addr(sq_retire_addr),
        .o_sq_retire_tag(sq_retire_tag),
        .o_sq_retire_data(sq_retire_data),
        .i_update_en(update_sq_en),
        .i_update_select(update_sq_select),
        .i_update_retry(update_retry),
        .i_update_replay(update_replay),
        .i_update_mhq_retry(i_mhq_lookup_retry),
        .i_update_mhq_replay(i_mhq_lookup_replay),
        .i_mhq_fill_en(i_mhq_fill_en),
        .i_rob_retire_en(i_rob_retire_sq_en),
        .i_rob_retire_tag(i_rob_retire_tag),
        .o_rob_retire_ack(o_rob_retire_sq_ack)
    );

    procyon_dcache #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_DC_CACHE_SIZE(OPTN_DC_CACHE_SIZE),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE),
        .OPTN_DC_WAY_COUNT(OPTN_DC_WAY_COUNT)
    ) procyon_dcache_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_dc_wr_en(dc_wr_en),
        .i_dc_addr(lsu_am_addr),
        .i_dc_op(lsu_am_op),
        .i_dc_data(lsu_am_retire_data),
        .i_dc_valid(1'b1),
        .i_dc_dirty(dc_dirty),
        .i_dc_fill(dc_fill),
        .i_dc_fill_data(dc_fill_data),
        .o_dc_dt_byte_sel(dc_dt_byte_sel),
        .o_dc_hit(dc_hit),
        .o_dc_data(dc_rd_data),
        .o_dc_victim_valid(o_victim_valid),
        .o_dc_victim_addr(o_victim_addr),
        .o_dc_victim_data(o_victim_data)
    );

endmodule
