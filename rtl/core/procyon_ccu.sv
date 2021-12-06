/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Core Communications Unit
// This module is responsible for arbitrating between the MHQ, fetch and victim requests within the CPU and controlling the BIU

`include "procyon_constants.svh"

module procyon_ccu #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_VQ_DEPTH      = 4,
    parameter OPTN_MHQ_DEPTH     = 4,
    parameter OPTN_IFQ_DEPTH     = 1,
    parameter OPTN_IC_LINE_SIZE  = 32,
    parameter OPTN_DC_LINE_SIZE  = 32,
    parameter OPTN_WB_ADDR_WIDTH = 32,
    parameter OPTN_WB_DATA_WIDTH = 16,

    parameter MHQ_IDX_WIDTH      = OPTN_MHQ_DEPTH == 1 ? 1 : $clog2(OPTN_MHQ_DEPTH),
    parameter DC_LINE_WIDTH      = OPTN_DC_LINE_SIZE * 8,
    parameter IC_LINE_WIDTH      = OPTN_IC_LINE_SIZE * 8,
    parameter DATA_SIZE          = OPTN_DATA_WIDTH / 8,
    parameter WB_DATA_SIZE       = OPTN_WB_DATA_WIDTH / 8
)(
    input  logic                            clk,
    input  logic                            n_rst,

    output logic                            o_ifq_full,

    // VQ lookup interface
    input  logic                            i_vq_lookup_valid,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_vq_lookup_addr,
    input  logic [DATA_SIZE-1:0]            i_vq_lookup_byte_sel,
    output logic                            o_vq_lookup_hit,
    output logic [OPTN_DATA_WIDTH-1:0]      o_vq_lookup_data,

    // Victim cacheline
    input  logic                            i_victim_valid,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_victim_addr,
    input  logic [DC_LINE_WIDTH-1:0]        i_victim_data,

    // MHQ address/tag lookup interface
    input  logic                            i_mhq_lookup_valid,
    input  logic                            i_mhq_lookup_dc_hit,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_mhq_lookup_addr,
    input  logic [`PCYN_OP_WIDTH-1:0]       i_mhq_lookup_op,
    input  logic [OPTN_DATA_WIDTH-1:0]      i_mhq_lookup_data,
    input  logic                            i_mhq_lookup_we,
    output logic                            o_mhq_lookup_retry,
    output logic                            o_mhq_lookup_replay,
    output logic [MHQ_IDX_WIDTH-1:0]        o_mhq_lookup_tag,

    // DCache fill interface
    output logic                            o_mhq_fill_en,
    output logic [MHQ_IDX_WIDTH-1:0]        o_mhq_fill_tag,
    output logic                            o_mhq_fill_dirty,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_mhq_fill_addr,
    output logic [DC_LINE_WIDTH-1:0]        o_mhq_fill_data,

    // IFQ enqueue interface
    input  logic                            i_ifq_alloc_en,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_ifq_alloc_addr,

    // ICache fill interface
    output logic                            o_ifq_fill_en,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_ifq_fill_addr,
    output logic [IC_LINE_WIDTH-1:0]        o_ifq_fill_data,

    // Wishbone bus interface
    input  logic                            i_wb_clk,
    input  logic                            i_wb_rst,
    input  logic                            i_wb_ack,
    input  logic [OPTN_WB_DATA_WIDTH-1:0]   i_wb_data,
    output logic                            o_wb_cyc,
    output logic                            o_wb_stb,
    output logic                            o_wb_we,
    output logic [`WB_CTI_WIDTH-1:0]        o_wb_cti,
    output logic [`WB_BTE_WIDTH-1:0]        o_wb_bte,
    output logic [WB_DATA_SIZE-1:0]         o_wb_sel,
    output logic [OPTN_WB_ADDR_WIDTH-1:0]   o_wb_addr,
    output logic [OPTN_WB_DATA_WIDTH-1:0]   o_wb_data
);

    localparam CCU_LINE_SIZE    = (OPTN_DC_LINE_SIZE > OPTN_IC_LINE_SIZE) ? OPTN_DC_LINE_SIZE : OPTN_IC_LINE_SIZE;
    localparam CCU_LINE_WIDTH   = CCU_LINE_SIZE * 8;
    localparam CCU_ARB_DEPTH    = 3;
    localparam CCU_VQ_PRIORITY  = 0;
    localparam CCU_MHQ_PRIORITY = 1;
    localparam CCU_IFQ_PRIORITY = 2;

    logic vq_full;
    logic [CCU_ARB_DEPTH-1:0] ccu_arb_valid;
    logic [OPTN_ADDR_WIDTH-1:0] ccu_arb_addr [0:CCU_ARB_DEPTH-1];
    logic [CCU_LINE_WIDTH-1:0] ccu_arb_data_w [0:CCU_ARB_DEPTH-1];
    logic [CCU_ARB_DEPTH-1:0] ccu_arb_we;
    logic [`PCYN_CCU_LEN_WIDTH-1:0] ccu_arb_len [0:CCU_ARB_DEPTH-1];
    logic [CCU_ARB_DEPTH-1:0] ccu_arb_done;
    logic [CCU_LINE_WIDTH-1:0] ccu_arb_data_r;
/* verilator lint_off UNUSED */
    logic [CCU_ARB_DEPTH-1:0] ccu_arb_grant;
/* verilator lint_on  UNUSED */
    logic biu_en;
    logic [`PCYN_BIU_FUNC_WIDTH-1:0] biu_func;
    logic [`PCYN_BIU_LEN_WIDTH-1:0] biu_len;
    logic [CCU_LINE_SIZE-1:0] biu_sel;
    logic [OPTN_ADDR_WIDTH-1:0] biu_addr;
    logic [CCU_LINE_WIDTH-1:0] biu_data_w;
    logic biu_done;
    logic [CCU_LINE_WIDTH-1:0] biu_data_r;
    logic [DC_LINE_WIDTH-1:0] ccu_arb_data_vq;
    logic [DC_LINE_WIDTH-1:0] ccu_arb_data_mhq;
    logic [IC_LINE_WIDTH-1:0] ccu_arb_data_ifq;

    assign ccu_arb_data_w[CCU_VQ_PRIORITY] = {{(CCU_LINE_WIDTH-DC_LINE_WIDTH){1'b0}}, ccu_arb_data_vq};
    assign ccu_arb_data_w[CCU_MHQ_PRIORITY] = '0;
    assign ccu_arb_data_w[CCU_IFQ_PRIORITY] = '0;
    assign ccu_arb_data_mhq = ccu_arb_data_r[DC_LINE_WIDTH-1:0];
    assign ccu_arb_data_ifq = ccu_arb_data_r[IC_LINE_WIDTH-1:0];
    assign biu_sel = '1;

    procyon_ccu_vq #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_VQ_DEPTH(OPTN_VQ_DEPTH),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE)
    ) procyon_ccu_vq_inst (
        .clk(clk),
        .n_rst(n_rst),
        .o_vq_full(vq_full),
        .i_vq_lookup_valid(i_vq_lookup_valid),
        .i_vq_lookup_addr(i_vq_lookup_addr),
        .i_vq_lookup_byte_sel(i_vq_lookup_byte_sel),
        .o_vq_lookup_hit(o_vq_lookup_hit),
        .o_vq_lookup_data(o_vq_lookup_data),
        .i_vq_victim_valid(i_victim_valid),
        .i_vq_victim_addr(i_victim_addr),
        .i_vq_victim_data(i_victim_data),
        .i_ccu_done(ccu_arb_done[CCU_VQ_PRIORITY]),
        .o_ccu_en(ccu_arb_valid[CCU_VQ_PRIORITY]),
        .o_ccu_we(ccu_arb_we[CCU_VQ_PRIORITY]),
        .o_ccu_len(ccu_arb_len[CCU_VQ_PRIORITY]),
        .o_ccu_addr(ccu_arb_addr[CCU_VQ_PRIORITY]),
        .o_ccu_data(ccu_arb_data_vq)
    );

    procyon_ccu_mhq #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_MHQ_DEPTH(OPTN_MHQ_DEPTH),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE)
    ) procyon_ccu_mhq_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_vq_full(vq_full),
        .i_mhq_lookup_valid(i_mhq_lookup_valid),
        .i_mhq_lookup_dc_hit(i_mhq_lookup_dc_hit),
        .i_mhq_lookup_addr(i_mhq_lookup_addr),
        .i_mhq_lookup_op(i_mhq_lookup_op),
        .i_mhq_lookup_data(i_mhq_lookup_data),
        .i_mhq_lookup_we(i_mhq_lookup_we),
        .o_mhq_lookup_retry(o_mhq_lookup_retry),
        .o_mhq_lookup_replay(o_mhq_lookup_replay),
        .o_mhq_lookup_tag(o_mhq_lookup_tag),
        .o_mhq_fill_en(o_mhq_fill_en),
        .o_mhq_fill_tag(o_mhq_fill_tag),
        .o_mhq_fill_dirty(o_mhq_fill_dirty),
        .o_mhq_fill_addr(o_mhq_fill_addr),
        .o_mhq_fill_data(o_mhq_fill_data),
        .i_ccu_done(ccu_arb_done[CCU_MHQ_PRIORITY]),
        .i_ccu_data(ccu_arb_data_mhq),
        .o_ccu_en(ccu_arb_valid[CCU_MHQ_PRIORITY]),
        .o_ccu_we(ccu_arb_we[CCU_MHQ_PRIORITY]),
        .o_ccu_len(ccu_arb_len[CCU_MHQ_PRIORITY]),
        .o_ccu_addr(ccu_arb_addr[CCU_MHQ_PRIORITY])
    );

    procyon_ccu_ifq #(
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_IFQ_DEPTH(OPTN_IFQ_DEPTH),
        .OPTN_IC_LINE_SIZE(OPTN_IC_LINE_SIZE)
    ) procyon_ccu_ifq_inst (
        .clk(clk),
        .n_rst(n_rst),
        .o_ifq_full(o_ifq_full),
        .i_ifq_alloc_en(i_ifq_alloc_en),
        .i_ifq_alloc_addr(i_ifq_alloc_addr),
        .o_ifq_fill_en(o_ifq_fill_en),
        .o_ifq_fill_addr(o_ifq_fill_addr),
        .o_ifq_fill_data(o_ifq_fill_data),
        .i_ccu_done(ccu_arb_done[CCU_IFQ_PRIORITY]),
        .i_ccu_data(ccu_arb_data_ifq),
        .o_ccu_en(ccu_arb_valid[CCU_IFQ_PRIORITY]),
        .o_ccu_we(ccu_arb_we[CCU_IFQ_PRIORITY]),
        .o_ccu_len(ccu_arb_len[CCU_IFQ_PRIORITY]),
        .o_ccu_addr(ccu_arb_addr[CCU_IFQ_PRIORITY])
    );

    procyon_ccu_arb #(
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_CCU_ARB_DEPTH(CCU_ARB_DEPTH),
        .OPTN_CCU_LINE_SIZE(CCU_LINE_SIZE)
    ) procyon_ccu_arb_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_ccu_arb_valid(ccu_arb_valid),
        .i_ccu_arb_we(ccu_arb_we),
        .i_ccu_arb_len(ccu_arb_len),
        .i_ccu_arb_addr(ccu_arb_addr),
        .i_ccu_arb_data(ccu_arb_data_w),
        .o_ccu_arb_done(ccu_arb_done),
        .o_ccu_arb_grant(ccu_arb_grant),
        .o_ccu_arb_data(ccu_arb_data_r),
        .i_biu_done(biu_done),
        .i_biu_data(biu_data_r),
        .o_biu_en(biu_en),
        .o_biu_func(biu_func),
        .o_biu_len(biu_len),
        .o_biu_addr(biu_addr),
        .o_biu_data(biu_data_w)
    );

    procyon_biu_controller_wb #(
        .OPTN_BIU_DATA_SIZE(CCU_LINE_SIZE),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_WB_DATA_WIDTH(OPTN_WB_DATA_WIDTH),
        .OPTN_WB_ADDR_WIDTH(OPTN_WB_ADDR_WIDTH)
    ) procyon_biu_controller_wb_inst (
        .i_biu_en(biu_en),
        .i_biu_func(biu_func),
        .i_biu_len(biu_len),
        .i_biu_sel(biu_sel),
        .i_biu_addr(biu_addr),
        .i_biu_data(biu_data_w),
        .o_biu_done(biu_done),
        .o_biu_data(biu_data_r),
        .i_wb_clk(i_wb_clk),
        .i_wb_rst(i_wb_rst),
        .i_wb_ack(i_wb_ack),
        .i_wb_data(i_wb_data),
        .o_wb_cyc(o_wb_cyc),
        .o_wb_stb(o_wb_stb),
        .o_wb_we(o_wb_we),
        .o_wb_cti(o_wb_cti),
        .o_wb_bte(o_wb_bte),
        .o_wb_sel(o_wb_sel),
        .o_wb_addr(o_wb_addr),
        .o_wb_data(o_wb_data)
    );

endmodule
