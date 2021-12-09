/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// `define NOOP 32'h00000013 // ADDI X0, X0, #0

/* verilator lint_off IMPORTSTAR */
import procyon_lib_pkg::*;
import procyon_core_pkg::*;
/* verilator lint_on  IMPORTSTAR */

module procyon #(
    parameter OPTN_DATA_WIDTH      = 32,
    parameter OPTN_INSN_WIDTH      = 32,
    parameter OPTN_ADDR_WIDTH      = 32,
    parameter OPTN_RAT_DEPTH       = 32,
    parameter OPTN_NUM_IEU         = 1,
    parameter OPTN_INSN_FIFO_DEPTH = 8,
    parameter OPTN_ROB_DEPTH       = 64,
    parameter OPTN_RS_IEU_DEPTH    = 16,
    parameter OPTN_RS_LSU_DEPTH    = 16,
    parameter OPTN_LQ_DEPTH        = 8,
    parameter OPTN_SQ_DEPTH        = 8,
    parameter OPTN_VQ_DEPTH        = 4,
    parameter OPTN_MHQ_DEPTH       = 4,
    parameter OPTN_IFQ_DEPTH       = 1,
    parameter OPTN_IC_CACHE_SIZE   = 1024,
    parameter OPTN_IC_LINE_SIZE    = 32,
    parameter OPTN_IC_WAY_COUNT    = 1,
    parameter OPTN_DC_CACHE_SIZE   = 1024,
    parameter OPTN_DC_LINE_SIZE    = 32,
    parameter OPTN_DC_WAY_COUNT    = 1,
    parameter OPTN_WB_DATA_WIDTH   = 16,
    parameter OPTN_WB_ADDR_WIDTH   = 32
)(
    input  logic                                     clk,
    input  logic                                     n_rst,

    // FIXME: To test if simulations pass/fail
    output logic [OPTN_DATA_WIDTH-1:0]               o_sim_tp,

    // FIXME: FPGA debugging output
    output logic                                     o_rob_redirect,
    output logic [OPTN_ADDR_WIDTH-1:0]               o_rob_redirect_addr,
    output logic                                     o_rat_retire_en,
    output logic [`PCYN_C2I(OPTN_RAT_DEPTH)-1:0]     o_rat_retire_rdst,
    output logic [OPTN_DATA_WIDTH-1:0]               o_rat_retire_data,

    // Wishbone bus interface
    input  logic                                     i_wb_clk,
    input  logic                                     i_wb_rst,
    input  logic                                     i_wb_ack,
    input  logic [OPTN_WB_DATA_WIDTH-1:0]            i_wb_data,
    output logic                                     o_wb_cyc,
    output logic                                     o_wb_stb,
    output logic                                     o_wb_we,
    output wb_cti_t                                  o_wb_cti,
    output wb_bte_t                                  o_wb_bte,
    output logic [`PCYN_W2S(OPTN_WB_DATA_WIDTH)-1:0] o_wb_sel,
    output logic [OPTN_WB_ADDR_WIDTH-1:0]            o_wb_addr,
    output logic [OPTN_WB_DATA_WIDTH-1:0]            o_wb_data
);
    localparam CDB_DEPTH = 1 + OPTN_NUM_IEU;
    localparam RAT_IDX_WIDTH = `PCYN_C2I(OPTN_RAT_DEPTH);
    localparam ROB_IDX_WIDTH = `PCYN_C2I(OPTN_ROB_DEPTH);
    localparam MHQ_IDX_WIDTH = `PCYN_C2I(OPTN_MHQ_DEPTH);
    localparam DC_LINE_WIDTH = `PCYN_S2W(OPTN_DC_LINE_SIZE);
    localparam IC_LINE_WIDTH = `PCYN_S2W(OPTN_IC_LINE_SIZE);
    localparam DATA_SIZE = `PCYN_W2S(OPTN_DATA_WIDTH);
    localparam WB_DATA_SIZE = `PCYN_W2S(OPTN_WB_DATA_WIDTH);

    // Module signals
    logic fetch_valid;
    logic [OPTN_ADDR_WIDTH-1:0] fetch_pc;
    logic [OPTN_INSN_WIDTH-1:0] fetch_insn;
    logic decode_stall;

    logic rob_reserve_en;
    logic [ROB_IDX_WIDTH-1:0] rob_reserve_tag;
    logic rob_stall;
    logic rob_lookup_rdy [0:1];
    logic [OPTN_DATA_WIDTH-1:0] rob_lookup_data [0:1];
    pcyn_op_is_t rob_dispatch_op_is;
    logic [OPTN_ADDR_WIDTH-1:0] rob_dispatch_pc;
    logic [RAT_IDX_WIDTH-1:0] rob_dispatch_rdst;
    logic [OPTN_DATA_WIDTH-1:0] rob_dispatch_rdst_data;

    logic [RAT_IDX_WIDTH-1:0] rat_lookup_rsrc [0:1];
    logic rat_lookup_rdy [0:1];
    logic [OPTN_DATA_WIDTH-1:0] rat_lookup_data [0:1];
    logic [ROB_IDX_WIDTH-1:0] rat_lookup_tag [0:1];

    logic [RAT_IDX_WIDTH-1:0] rat_rename_rdst;
    logic rat_retire_en;
    logic [RAT_IDX_WIDTH-1:0] rat_retire_rdst;
    logic [OPTN_DATA_WIDTH-1:0] rat_retire_data;
    logic [ROB_IDX_WIDTH-1:0] rat_retire_tag;

    logic rs_reserve_en;
    pcyn_op_is_t rs_reserve_op_is;
    logic rs_stall;
    pcyn_op_t rs_dispatch_op;
    logic [OPTN_DATA_WIDTH-1:0] rs_dispatch_imm;
    logic [ROB_IDX_WIDTH-1:0] rs_dispatch_dst_tag;
    logic rs_dispatch_src_rdy [0:1];
    logic [OPTN_DATA_WIDTH-1:0] rs_dispatch_src_data [0:1];
    logic [ROB_IDX_WIDTH-1:0] rs_dispatch_src_tag [0:1];

    pcyn_rs_fu_type_t rs_switch_fu_type [0:CDB_DEPTH-1];
    logic [CDB_DEPTH-1:0] rs_switch_reserve_en;
    logic [CDB_DEPTH-1:0] rs_switch_stall;
    logic rs_switch_src_rdy [0:1];
    logic [OPTN_DATA_WIDTH-1:0] rs_switch_src_data [0:1];
    logic [ROB_IDX_WIDTH-1:0] rs_switch_src_tag [0:1];

    logic fu_stall [0:CDB_DEPTH-1];
    logic fu_valid [0:CDB_DEPTH-1];
    pcyn_op_t fu_op [0:CDB_DEPTH-1];
    pcyn_op_is_t fu_op_is [0:CDB_DEPTH-1];
    logic [OPTN_DATA_WIDTH-1:0] fu_imm [0:CDB_DEPTH-1];
    logic [OPTN_DATA_WIDTH-1:0] fu_src [0:CDB_DEPTH-1] [0:1];
    logic [ROB_IDX_WIDTH-1:0] fu_tag [0:CDB_DEPTH-1];

    logic cdb_en [0:CDB_DEPTH-1];
    logic cdb_redirect [0:CDB_DEPTH-1];
    logic [OPTN_DATA_WIDTH-1:0] cdb_data [0:CDB_DEPTH-1];
    logic [ROB_IDX_WIDTH-1:0] cdb_tag [0:CDB_DEPTH-1];

    logic lsu_retire_lq_en;
    logic lsu_retire_sq_en;
    logic lsu_retire_lq_ack;
    logic lsu_retire_sq_ack;
    logic lsu_retire_misspeculated;
    logic [ROB_IDX_WIDTH-1:0] lsu_retire_tag;

    logic vq_lookup_valid;
    logic [OPTN_ADDR_WIDTH-1:0] vq_lookup_addr;
    logic [DATA_SIZE-1:0] vq_lookup_byte_sel;
    logic vq_lookup_hit;
    logic [OPTN_DATA_WIDTH-1:0] vq_lookup_data;
    logic victim_valid;
    logic [OPTN_ADDR_WIDTH-1:0] victim_addr;
    logic [DC_LINE_WIDTH-1:0] victim_data;

    logic mhq_lookup_valid;
    logic mhq_lookup_dc_hit;
    logic [OPTN_ADDR_WIDTH-1:0] mhq_lookup_addr;
    pcyn_op_t mhq_lookup_op;
    logic [OPTN_DATA_WIDTH-1:0] mhq_lookup_data;
    logic mhq_lookup_we;
    logic mhq_lookup_retry;
    logic mhq_lookup_replay;
    logic [MHQ_IDX_WIDTH-1:0] mhq_lookup_tag;
    logic mhq_fill_en;
    logic [MHQ_IDX_WIDTH-1:0] mhq_fill_tag;
    logic mhq_fill_dirty;
    logic [OPTN_ADDR_WIDTH-1:0] mhq_fill_addr;
    logic [DC_LINE_WIDTH-1:0] mhq_fill_data;

    logic ifq_full;
    logic ifq_alloc_en;
    logic [OPTN_ADDR_WIDTH-1:0] ifq_alloc_addr;
    logic ifq_fill_en;
    logic [OPTN_ADDR_WIDTH-1:0] ifq_fill_addr;
    logic [IC_LINE_WIDTH-1:0] ifq_fill_data;

    logic rob_redirect;
    logic [OPTN_ADDR_WIDTH-1:0] rob_redirect_addr;

    // FIXME: FPGA debugging output
    assign o_rob_redirect = rob_redirect;
    assign o_rob_redirect_addr = rob_redirect_addr;
    assign o_rat_retire_en = rat_retire_en;
    assign o_rat_retire_rdst = rat_retire_rdst;
    assign o_rat_retire_data = rat_retire_data;

    // Module Instances
    procyon_fetch #(
        .OPTN_INSN_WIDTH(OPTN_INSN_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_INSN_FIFO_DEPTH(OPTN_INSN_FIFO_DEPTH),
        .OPTN_IC_CACHE_SIZE(OPTN_IC_CACHE_SIZE),
        .OPTN_IC_LINE_SIZE(OPTN_IC_LINE_SIZE),
        .OPTN_IC_WAY_COUNT(OPTN_IC_WAY_COUNT)
    ) procyon_fetch_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_redirect(rob_redirect),
        .i_redirect_addr(rob_redirect_addr),
        .i_ifq_full(ifq_full),
        .o_ifq_alloc_en(ifq_alloc_en),
        .o_ifq_alloc_addr(ifq_alloc_addr),
        .i_ifq_fill_en(ifq_fill_en),
        .i_ifq_fill_addr(ifq_fill_addr),
        .i_ifq_fill_data(ifq_fill_data),
        .i_decode_stall(decode_stall),
        .o_fetch_pc(fetch_pc),
        .o_fetch_insn(fetch_insn),
        .o_fetch_valid(fetch_valid)
    );

    procyon_decode #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_RAT_IDX_WIDTH(RAT_IDX_WIDTH),
        .OPTN_ROB_IDX_WIDTH(ROB_IDX_WIDTH)
    ) procyon_decode_inst (
        .clk(clk),
        .i_flush(rob_redirect),
        .i_rob_stall(rob_stall),
        .i_rs_stall(rs_stall),
        .i_fetch_pc(fetch_pc),
        .i_fetch_insn(fetch_insn),
        .i_fetch_valid(fetch_valid),
        .o_decode_stall(decode_stall),
        .o_rat_lookup_rsrc(rat_lookup_rsrc),
        .i_rat_lookup_rdy(rat_lookup_rdy),
        .i_rat_lookup_data(rat_lookup_data),
        .i_rat_lookup_tag(rat_lookup_tag),
        .i_rob_lookup_rdy(rob_lookup_rdy),
        .i_rob_lookup_data(rob_lookup_data),
        .i_rob_dst_tag(rob_reserve_tag),
        .o_rat_rename_rdst(rat_rename_rdst),
        .o_rs_reserve_en(rs_reserve_en),
        .o_rs_reserve_op_is(rs_reserve_op_is),
        .o_rob_reserve_en(rob_reserve_en),
        .o_rob_dispatch_op_is(rob_dispatch_op_is),
        .o_rob_dispatch_pc(rob_dispatch_pc),
        .o_rob_dispatch_rdst(rob_dispatch_rdst),
        .o_rob_dispatch_rdst_data(rob_dispatch_rdst_data),
        .o_rs_dispatch_op(rs_dispatch_op),
        .o_rs_dispatch_imm(rs_dispatch_imm),
        .o_rs_dispatch_dst_tag(rs_dispatch_dst_tag),
        .o_rs_dispatch_src_rdy(rs_dispatch_src_rdy),
        .o_rs_dispatch_src_data(rs_dispatch_src_data),
        .o_rs_dispatch_src_tag(rs_dispatch_src_tag)
    );

    procyon_rat #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_RAT_DEPTH(OPTN_RAT_DEPTH),
        .OPTN_ROB_IDX_WIDTH(ROB_IDX_WIDTH)
    ) procyon_rat_inst (
        .clk(clk),
        .n_rst(n_rst),
        .o_sim_tp(o_sim_tp),
        .i_flush(rob_redirect),
        .i_rat_lookup_rsrc(rat_lookup_rsrc),
        .o_rat_lookup_rdy(rat_lookup_rdy),
        .o_rat_lookup_data(rat_lookup_data),
        .o_rat_lookup_tag(rat_lookup_tag),
        .i_rat_rename_en(rob_reserve_en),
        .i_rat_rename_rdst(rat_rename_rdst),
        .i_rat_rename_tag(rob_reserve_tag),
        .i_rat_retire_en(rat_retire_en),
        .i_rat_retire_rdst(rat_retire_rdst),
        .i_rat_retire_data(rat_retire_data),
        .i_rat_retire_tag(rat_retire_tag)
    );

    procyon_rob #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_CDB_DEPTH(CDB_DEPTH),
        .OPTN_ROB_DEPTH(OPTN_ROB_DEPTH),
        .OPTN_RAT_IDX_WIDTH(RAT_IDX_WIDTH)
    ) procyon_rob_inst (
        .clk(clk),
        .n_rst(n_rst),
        .o_redirect(rob_redirect),
        .o_redirect_addr(rob_redirect_addr),
        .o_rob_stall(rob_stall),
        .i_cdb_en(cdb_en),
        .i_cdb_redirect(cdb_redirect),
        .i_cdb_data(cdb_data),
        .i_cdb_tag(cdb_tag),
        .i_rob_reserve_en(rob_reserve_en),
        .o_rob_reserve_tag(rob_reserve_tag),
        .i_rob_lookup_tag(rat_lookup_tag),
        .o_rob_lookup_rdy(rob_lookup_rdy),
        .o_rob_lookup_data(rob_lookup_data),
        .i_rob_dispatch_op_is(rob_dispatch_op_is),
        .i_rob_dispatch_pc(rob_dispatch_pc),
        .i_rob_dispatch_rdst(rob_dispatch_rdst),
        .i_rob_dispatch_rdst_data(rob_dispatch_rdst_data),
        .o_rat_retire_data(rat_retire_data),
        .o_rat_retire_rdst(rat_retire_rdst),
        .o_rat_retire_tag(rat_retire_tag),
        .o_rat_retire_en(rat_retire_en),
        .i_lsu_retire_lq_ack(lsu_retire_lq_ack),
        .i_lsu_retire_sq_ack(lsu_retire_sq_ack),
        .i_lsu_retire_misspeculated(lsu_retire_misspeculated),
        .o_lsu_retire_lq_en(lsu_retire_lq_en),
        .o_lsu_retire_sq_en(lsu_retire_sq_en),
        .o_lsu_retire_tag(lsu_retire_tag)
    );

    procyon_rs_switch #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_ROB_IDX_WIDTH(ROB_IDX_WIDTH),
        .OPTN_CDB_DEPTH(CDB_DEPTH)
    ) procyon_rs_switch_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_cdb_en(cdb_en),
        .i_cdb_data(cdb_data),
        .i_cdb_tag(cdb_tag),
        .i_rs_reserve_en(rs_reserve_en),
        .i_rs_reserve_op_is(rs_reserve_op_is),
        .o_rs_reserve_en(rs_switch_reserve_en),
        .i_rs_fu_type(rs_switch_fu_type),
        .i_rs_src_rdy(rs_dispatch_src_rdy),
        .i_rs_src_data(rs_dispatch_src_data),
        .i_rs_src_tag(rs_dispatch_src_tag),
        .o_rs_src_rdy(rs_switch_src_rdy),
        .o_rs_src_data(rs_switch_src_data),
        .o_rs_src_tag(rs_switch_src_tag),
        .i_rs_stall(rs_switch_stall),
        .o_rs_stall(rs_stall)
    );

    procyon_rs #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_ROB_IDX_WIDTH(ROB_IDX_WIDTH),
        .OPTN_CDB_DEPTH(CDB_DEPTH),
        .OPTN_RS_DEPTH(OPTN_RS_LSU_DEPTH),
        .OPTN_RS_FU_TYPE(PCYN_RS_FU_TYPE_LSU)
    ) procyon_rs_lsu_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(rob_redirect),
        .o_rs_fu_type(rs_switch_fu_type[0]),
        .i_cdb_en(cdb_en),
        .i_cdb_data(cdb_data),
        .i_cdb_tag(cdb_tag),
        .i_rs_reserve_en(rs_switch_reserve_en[0]),
        .i_rs_dispatch_op(rs_dispatch_op),
        .i_rs_dispatch_op_is(rob_dispatch_op_is),
        .i_rs_dispatch_imm(rs_dispatch_imm),
        .i_rs_dispatch_dst_tag(rs_dispatch_dst_tag),
        .i_rs_dispatch_src_rdy(rs_switch_src_rdy),
        .i_rs_dispatch_src_data(rs_switch_src_data),
        .i_rs_dispatch_src_tag(rs_switch_src_tag),
        .o_rs_stall(rs_switch_stall[0]),
        .i_fu_stall(fu_stall[0]),
        .o_fu_valid(fu_valid[0]),
        .o_fu_op(fu_op[0]),
        .o_fu_op_is(fu_op_is[0]),
        .o_fu_imm(fu_imm[0]),
        .o_fu_src(fu_src[0]),
        .o_fu_tag(fu_tag[0])
    );

    procyon_lsu #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_LQ_DEPTH(OPTN_LQ_DEPTH),
        .OPTN_SQ_DEPTH(OPTN_SQ_DEPTH),
        .OPTN_DC_CACHE_SIZE(OPTN_DC_CACHE_SIZE),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE),
        .OPTN_DC_WAY_COUNT(OPTN_DC_WAY_COUNT),
        .OPTN_ROB_IDX_WIDTH(ROB_IDX_WIDTH),
        .OPTN_MHQ_IDX_WIDTH(MHQ_IDX_WIDTH)
    ) procyon_lsu_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(rob_redirect),
        .o_cdb_en(cdb_en[0]),
        .o_cdb_redirect(cdb_redirect[0]),
        .o_cdb_data(cdb_data[0]),
        .o_cdb_tag(cdb_tag[0]),
        .i_fu_valid(fu_valid[0]),
        .i_fu_op(fu_op[0]),
        .i_fu_op_is(fu_op_is[0]),
        .i_fu_imm(fu_imm[0]),
        .i_fu_src(fu_src[0]),
        .i_fu_tag(fu_tag[0]),
        .o_fu_stall(fu_stall[0]),
        .i_rob_retire_tag(lsu_retire_tag),
        .i_rob_retire_lq_en(lsu_retire_lq_en),
        .i_rob_retire_sq_en(lsu_retire_sq_en),
        .o_rob_retire_lq_ack(lsu_retire_lq_ack),
        .o_rob_retire_sq_ack(lsu_retire_sq_ack),
        .o_rob_retire_misspeculated(lsu_retire_misspeculated),
        .o_vq_lookup_valid(vq_lookup_valid),
        .o_vq_lookup_addr(vq_lookup_addr),
        .o_vq_lookup_byte_sel(vq_lookup_byte_sel),
        .i_vq_lookup_hit(vq_lookup_hit),
        .i_vq_lookup_data(vq_lookup_data),
        .o_victim_valid(victim_valid),
        .o_victim_addr(victim_addr),
        .o_victim_data(victim_data),
        .i_mhq_lookup_retry(mhq_lookup_retry),
        .i_mhq_lookup_replay(mhq_lookup_replay),
        .i_mhq_lookup_tag(mhq_lookup_tag),
        .o_mhq_lookup_valid(mhq_lookup_valid),
        .o_mhq_lookup_dc_hit(mhq_lookup_dc_hit),
        .o_mhq_lookup_addr(mhq_lookup_addr),
        .o_mhq_lookup_op(mhq_lookup_op),
        .o_mhq_lookup_data(mhq_lookup_data),
        .o_mhq_lookup_we(mhq_lookup_we),
        .i_mhq_fill_en(mhq_fill_en),
        .i_mhq_fill_tag(mhq_fill_tag),
        .i_mhq_fill_dirty(mhq_fill_dirty),
        .i_mhq_fill_addr(mhq_fill_addr),
        .i_mhq_fill_data(mhq_fill_data)
    );

    genvar inst;
    generate
    for (inst = 1; inst <= OPTN_NUM_IEU; inst++) begin : GEN_RS_IEU
        procyon_rs #(
            .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
            .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
            .OPTN_ROB_IDX_WIDTH(ROB_IDX_WIDTH),
            .OPTN_CDB_DEPTH(CDB_DEPTH),
            .OPTN_RS_DEPTH(OPTN_RS_IEU_DEPTH),
            .OPTN_RS_FU_TYPE(PCYN_RS_FU_TYPE_IEU)
        ) procyon_rs_ieu_inst (
            .clk(clk),
            .n_rst(n_rst),
            .i_flush(rob_redirect),
            .o_rs_fu_type(rs_switch_fu_type[inst]),
            .i_cdb_en(cdb_en),
            .i_cdb_data(cdb_data),
            .i_cdb_tag(cdb_tag),
            .i_rs_reserve_en(rs_switch_reserve_en[inst]),
            .i_rs_dispatch_op(rs_dispatch_op),
            .i_rs_dispatch_op_is(rob_dispatch_op_is),
            .i_rs_dispatch_imm(rs_dispatch_imm),
            .i_rs_dispatch_dst_tag(rs_dispatch_dst_tag),
            .i_rs_dispatch_src_rdy(rs_switch_src_rdy),
            .i_rs_dispatch_src_data(rs_switch_src_data),
            .i_rs_dispatch_src_tag(rs_switch_src_tag),
            .o_rs_stall(rs_switch_stall[inst]),
            .i_fu_stall(fu_stall[inst]),
            .o_fu_valid(fu_valid[inst]),
            .o_fu_op(fu_op[inst]),
            .o_fu_op_is(fu_op_is[inst]),
            .o_fu_imm(fu_imm[inst]),
            .o_fu_src(fu_src[inst]),
            .o_fu_tag(fu_tag[inst])
        );

        procyon_ieu #(
            .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
            .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
            .OPTN_ROB_IDX_WIDTH(ROB_IDX_WIDTH)
        ) procyon_ieu_inst (
            .clk(clk),
            .n_rst(n_rst),
            .i_flush(rob_redirect),
            .o_cdb_en(cdb_en[inst]),
            .o_cdb_redirect(cdb_redirect[inst]),
            .o_cdb_data(cdb_data[inst]),
            .o_cdb_tag(cdb_tag[inst]),
            .i_fu_valid(fu_valid[inst]),
            .i_fu_op(fu_op[inst]),
            .i_fu_op_is(fu_op_is[inst]),
            .i_fu_imm(fu_imm[inst]),
            .i_fu_src(fu_src[inst]),
            .i_fu_tag(fu_tag[inst]),
            .o_fu_stall(fu_stall[inst])
        );
    end
    endgenerate

    procyon_ccu #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_VQ_DEPTH(OPTN_VQ_DEPTH),
        .OPTN_MHQ_DEPTH(OPTN_MHQ_DEPTH),
        .OPTN_IFQ_DEPTH(OPTN_IFQ_DEPTH),
        .OPTN_IC_LINE_SIZE(OPTN_IC_LINE_SIZE),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE),
        .OPTN_WB_ADDR_WIDTH(OPTN_WB_ADDR_WIDTH),
        .OPTN_WB_DATA_WIDTH(OPTN_WB_DATA_WIDTH)
    ) procyon_ccu_inst (
        .clk(clk),
        .n_rst(n_rst),
        .o_ifq_full(ifq_full),
        .i_vq_lookup_valid(vq_lookup_valid),
        .i_vq_lookup_addr(vq_lookup_addr),
        .i_vq_lookup_byte_sel(vq_lookup_byte_sel),
        .o_vq_lookup_hit(vq_lookup_hit),
        .o_vq_lookup_data(vq_lookup_data),
        .i_victim_valid(victim_valid),
        .i_victim_addr(victim_addr),
        .i_victim_data(victim_data),
        .i_mhq_lookup_valid(mhq_lookup_valid),
        .i_mhq_lookup_dc_hit(mhq_lookup_dc_hit),
        .i_mhq_lookup_addr(mhq_lookup_addr),
        .i_mhq_lookup_op(mhq_lookup_op),
        .i_mhq_lookup_data(mhq_lookup_data),
        .i_mhq_lookup_we(mhq_lookup_we),
        .o_mhq_lookup_retry(mhq_lookup_retry),
        .o_mhq_lookup_replay(mhq_lookup_replay),
        .o_mhq_lookup_tag(mhq_lookup_tag),
        .o_mhq_fill_en(mhq_fill_en),
        .o_mhq_fill_tag(mhq_fill_tag),
        .o_mhq_fill_dirty(mhq_fill_dirty),
        .o_mhq_fill_addr(mhq_fill_addr),
        .o_mhq_fill_data(mhq_fill_data),
        .i_ifq_alloc_en(ifq_alloc_en),
        .i_ifq_alloc_addr(ifq_alloc_addr),
        .o_ifq_fill_en(ifq_fill_en),
        .o_ifq_fill_addr(ifq_fill_addr),
        .o_ifq_fill_data(ifq_fill_data),
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
