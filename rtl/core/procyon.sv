/* 
 * Copyright (c) 2019 Sekhar Bhattacharya
 *
 * SPDS-License-Identifier: MIT
 */

// `define NOOP 32'h00000013 // ADDI X0, X0, #0

`include "procyon_constants.svh"

module procyon #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_REGMAP_DEPTH  = 32,
    parameter OPTN_ROB_DEPTH     = 64,
    parameter OPTN_RS_IEU_DEPTH  = 16,
    parameter OPTN_RS_LSU_DEPTH  = 16,
    parameter OPTN_LQ_DEPTH      = 8,
    parameter OPTN_SQ_DEPTH      = 8,
    parameter OPTN_MHQ_DEPTH     = 4,
    parameter OPTN_DC_CACHE_SIZE = 1024,
    parameter OPTN_DC_LINE_SIZE  = 32,
    parameter OPTN_DC_WAY_COUNT  = 1,
    parameter OPTN_WB_DATA_WIDTH = 16,
    parameter OPTN_WB_ADDR_WIDTH = 32,

    parameter REGMAP_IDX_WIDTH   = $clog2(OPTN_REGMAP_DEPTH),
    parameter WB_DATA_SIZE       = OPTN_WB_DATA_WIDTH / 8
)(
    input  logic                          clk,
    input  logic                          n_rst,

    // FIXME: To test if simulations pass/fail
    output logic [OPTN_DATA_WIDTH-1:0]    o_sim_tp,

    // FIXME: FPGA debugging output
    output logic                          o_rob_redirect,
    output logic [OPTN_ADDR_WIDTH-1:0]    o_rob_redirect_addr,
    output logic                          o_regmap_retire_en,
    output logic [REGMAP_IDX_WIDTH-1:0]   o_regmap_retire_rdest,
    output logic [OPTN_DATA_WIDTH-1:0]    o_regmap_retire_data,

    // FIXME: Temporary instruction cache interface
    input  logic [OPTN_DATA_WIDTH-1:0]    i_ic_insn,
    input  logic                          i_ic_valid,
    output logic [OPTN_ADDR_WIDTH-1:0]    o_ic_pc,
    output logic                          o_ic_en,

    // Wishbone bus interface
    input  logic                          i_wb_clk,
    input  logic                          i_wb_rst,
    input  logic                          i_wb_ack,
    input  logic [OPTN_WB_DATA_WIDTH-1:0] i_wb_data,
    output logic                          o_wb_cyc,
    output logic                          o_wb_stb,
    output logic                          o_wb_we,
    output logic [`WB_CTI_WIDTH-1:0]      o_wb_cti,
    output logic [`WB_BTE_WIDTH-1:0]      o_wb_bte,
    output logic [WB_DATA_SIZE-1:0]       o_wb_sel,
    output logic [OPTN_WB_ADDR_WIDTH-1:0] o_wb_addr,
    output logic [OPTN_WB_DATA_WIDTH-1:0] o_wb_data
);

    localparam CDB_DEPTH     = 2;
    localparam ROB_IDX_WIDTH = $clog2(OPTN_ROB_DEPTH);
    localparam MHQ_IDX_WIDTH = $clog2(OPTN_MHQ_DEPTH);
    localparam DC_LINE_WIDTH = OPTN_DC_LINE_SIZE * 8;

    // Module signals
    logic                            dispatch_stall;
    logic [OPTN_ADDR_WIDTH-1:0]      dispatch_pc;
    logic [OPTN_DATA_WIDTH-1:0]      dispatch_insn;
    logic                            dispatch_valid;

    logic                            rob_stall;
    logic                            rob_lookup_rdy_ovrd [0:1];
    logic                            rob_enq_en;
    logic [`PCYN_ROB_OP_WIDTH-1:0]   rob_enq_op;
    logic [OPTN_ADDR_WIDTH-1:0]      rob_enq_pc;
    logic [REGMAP_IDX_WIDTH-1:0]     rob_enq_rdest;

    logic [OPTN_DATA_WIDTH-1:0]      regmap_retire_data;
    logic [REGMAP_IDX_WIDTH-1:0]     regmap_retire_rdest;
    logic [ROB_IDX_WIDTH-1:0]        regmap_retire_tag;
    logic                            regmap_retire_en;

    logic [ROB_IDX_WIDTH-1:0]        regmap_rename_tag;
    logic [REGMAP_IDX_WIDTH-1:0]     regmap_rename_rdest;
    logic                            regmap_rename_en;

    logic                            regmap_lookup_valid;
    logic [REGMAP_IDX_WIDTH-1:0]     regmap_lookup_rsrc  [0:1];
    logic                            regmap_lookup_rdy   [0:1];
    logic [ROB_IDX_WIDTH-1:0]        regmap_lookup_tag   [0:1];
    logic [OPTN_DATA_WIDTH-1:0]      regmap_lookup_data  [0:1];

    logic                            rs_stall;
    logic                            rs_en;
    logic [`PCYN_OPCODE_WIDTH-1:0]   rs_opcode;
    logic [OPTN_ADDR_WIDTH-1:0]      rs_pc;
    logic [OPTN_DATA_WIDTH-1:0]      rs_insn;
    logic [ROB_IDX_WIDTH-1:0]        rs_src_tag          [0:1];
    logic [OPTN_DATA_WIDTH-1:0]      rs_src_data         [0:1];
    logic                            rs_src_rdy          [0:1];
    logic [ROB_IDX_WIDTH-1:0]        rs_dst_tag;

    logic                            rs_switch_en        [0:CDB_DEPTH-1];
    logic                            rs_switch_stall     [0:CDB_DEPTH-1];
    logic [OPTN_DATA_WIDTH-1:0]      rs_switch_src_data  [0:1];
    logic [ROB_IDX_WIDTH-1:0]        rs_switch_src_tag   [0:1];
    logic                            rs_switch_src_rdy   [0:1];

    logic                            fu_stall            [0:CDB_DEPTH-1];
    logic                            fu_valid            [0:CDB_DEPTH-1];
    logic [`PCYN_OPCODE_WIDTH-1:0]   fu_opcode           [0:CDB_DEPTH-1];
    logic [OPTN_ADDR_WIDTH-1:0]      fu_iaddr            [0:CDB_DEPTH-1];
    logic [OPTN_DATA_WIDTH-1:0]      fu_insn             [0:CDB_DEPTH-1];
    logic [OPTN_DATA_WIDTH-1:0]      fu_src_a            [0:CDB_DEPTH-1];
    logic [OPTN_DATA_WIDTH-1:0]      fu_src_b            [0:CDB_DEPTH-1];
    logic [ROB_IDX_WIDTH-1:0]        fu_tag              [0:CDB_DEPTH-1];

    logic                            cdb_en              [0:CDB_DEPTH-1];
    logic                            cdb_redirect        [0:CDB_DEPTH-1];
    logic [OPTN_DATA_WIDTH-1:0]      cdb_data            [0:CDB_DEPTH-1];
    logic [OPTN_ADDR_WIDTH-1:0]      cdb_addr            [0:CDB_DEPTH-1];
    logic [ROB_IDX_WIDTH-1:0]        cdb_tag             [0:CDB_DEPTH-1];

    logic                            lsu_retire_lq_en;
    logic                            lsu_retire_sq_en;
    logic                            lsu_retire_lq_ack;
    logic                            lsu_retire_sq_ack;
    logic                            lsu_retire_misspeculated;
    logic [ROB_IDX_WIDTH-1:0]        lsu_retire_tag;

    logic                            mhq_lookup_valid;
    logic                            mhq_lookup_dc_hit;
    logic [OPTN_ADDR_WIDTH-1:0]      mhq_lookup_addr;
    logic [`PCYN_LSU_FUNC_WIDTH-1:0] mhq_lookup_lsu_func;
    logic [OPTN_DATA_WIDTH-1:0]      mhq_lookup_data;
    logic                            mhq_lookup_we;
    logic                            mhq_lookup_retry;
    logic                            mhq_lookup_replay;
    logic [MHQ_IDX_WIDTH-1:0]        mhq_lookup_tag;
    logic                            mhq_fill_en;
    logic [MHQ_IDX_WIDTH-1:0]        mhq_fill_tag;
    logic                            mhq_fill_dirty;
    logic [OPTN_ADDR_WIDTH-1:0]      mhq_fill_addr;
    logic [DC_LINE_WIDTH-1:0]        mhq_fill_data;

    logic                            rob_redirect;
    logic [OPTN_ADDR_WIDTH-1:0]      rob_redirect_addr;

    // FIXME: FPGA debugging output
    assign o_rob_redirect        = rob_redirect;
    assign o_rob_redirect_addr   = rob_redirect_addr;
    assign o_regmap_retire_en    = regmap_retire_en;
    assign o_regmap_retire_rdest = regmap_retire_rdest;
    assign o_regmap_retire_data  = regmap_retire_data;

    // Module Instances
    procyon_fetch #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH)
    ) procyon_fetch_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_redirect(rob_redirect),
        .i_redirect_addr(rob_redirect_addr),
        .i_insn(i_ic_insn),
        .i_data_valid(i_ic_valid),
        .o_pc(o_ic_pc),
        .o_en(o_ic_en),
        .i_dispatch_stall(dispatch_stall),
        .o_dispatch_pc(dispatch_pc),
        .o_dispatch_insn(dispatch_insn),
        .o_dispatch_valid(dispatch_valid)
    );

    procyon_dispatch #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_REGMAP_IDX_WIDTH(REGMAP_IDX_WIDTH),
        .OPTN_ROB_IDX_WIDTH(ROB_IDX_WIDTH)
    ) procyon_dispatch_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(rob_redirect),
        .i_rob_stall(rob_stall),
        .i_rs_stall(rs_stall),
        .i_dispatch_pc(dispatch_pc),
        .i_dispatch_insn(dispatch_insn),
        .i_dispatch_valid(dispatch_valid),
        .o_dispatch_stall(dispatch_stall),
        .o_regmap_lookup_valid(regmap_lookup_valid),
        .o_regmap_lookup_rsrc(regmap_lookup_rsrc),
        .o_regmap_rename_rdest(regmap_rename_rdest),
        .o_regmap_rename_en(regmap_rename_en),
        .i_rob_dst_tag(regmap_rename_tag),
        .o_rob_lookup_rdy_ovrd(rob_lookup_rdy_ovrd),
        .o_rob_enq_en(rob_enq_en),
        .o_rob_enq_op(rob_enq_op),
        .o_rob_enq_pc(rob_enq_pc),
        .o_rob_enq_rdest(rob_enq_rdest),
        .o_rs_en(rs_en),
        .o_rs_opcode(rs_opcode),
        .o_rs_pc(rs_pc),
        .o_rs_insn(rs_insn),
        .o_rs_dst_tag(rs_dst_tag)
    );

    procyon_regmap #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_REGMAP_DEPTH(OPTN_REGMAP_DEPTH),
        .OPTN_ROB_IDX_WIDTH(ROB_IDX_WIDTH)
    ) procyon_regmap_inst (
        .clk(clk),
        .n_rst(n_rst),
        .o_sim_tp(o_sim_tp),
        .i_flush(rob_redirect),
        .i_regmap_retire_data(regmap_retire_data),
        .i_regmap_retire_rdest(regmap_retire_rdest),
        .i_regmap_retire_tag(regmap_retire_tag),
        .i_regmap_retire_en(regmap_retire_en),
        .i_regmap_rename_tag(regmap_rename_tag),
        .i_regmap_rename_rdest(regmap_rename_rdest),
        .i_regmap_rename_en(regmap_rename_en),
        .i_regmap_lookup_valid(regmap_lookup_valid),
        .i_regmap_lookup_rsrc(regmap_lookup_rsrc),
        .o_regmap_lookup_rdy(regmap_lookup_rdy),
        .o_regmap_lookup_tag(regmap_lookup_tag),
        .o_regmap_lookup_data(regmap_lookup_data)
    );

    procyon_rob #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_CDB_DEPTH(CDB_DEPTH),
        .OPTN_ROB_DEPTH(OPTN_ROB_DEPTH),
        .OPTN_REGMAP_IDX_WIDTH(REGMAP_IDX_WIDTH)
    ) procyon_rob_inst (
        .clk(clk),
        .n_rst(n_rst),
        .o_redirect(rob_redirect),
        .o_redirect_addr(rob_redirect_addr),
        .i_rs_stall(rs_stall),
        .o_rob_stall(rob_stall),
        .i_cdb_en(cdb_en),
        .i_cdb_redirect(cdb_redirect),
        .i_cdb_data(cdb_data),
        .i_cdb_addr(cdb_addr),
        .i_cdb_tag(cdb_tag),
        .i_rob_enq_en(rob_enq_en),
        .i_rob_enq_op(rob_enq_op),
        .i_rob_enq_pc(rob_enq_pc),
        .i_rob_enq_rdest(rob_enq_rdest),
        .i_rob_lookup_rdy_ovrd(rob_lookup_rdy_ovrd),
        .i_rob_lookup_rdy(regmap_lookup_rdy),
        .i_rob_lookup_tag(regmap_lookup_tag),
        .i_rob_lookup_data(regmap_lookup_data),
        .o_rs_src_data(rs_src_data),
        .o_rs_src_tag(rs_src_tag),
        .o_rs_src_rdy(rs_src_rdy),
        .i_regmap_rename_en(regmap_rename_en),
        .o_regmap_rename_tag(regmap_rename_tag),
        .o_regmap_retire_data(regmap_retire_data),
        .o_regmap_retire_rdest(regmap_retire_rdest),
        .o_regmap_retire_tag(regmap_retire_tag),
        .o_regmap_retire_en(regmap_retire_en),
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
        .i_cdb_en(cdb_en),
        .i_cdb_data(cdb_data),
        .i_cdb_tag(cdb_tag),
        .i_rs_en(rs_en),
        .i_rs_opcode(rs_opcode),
        .i_rs_src_tag(rs_src_tag),
        .i_rs_src_data(rs_src_data),
        .i_rs_src_rdy(rs_src_rdy),
        .o_rs_en(rs_switch_en),
        .o_rs_src_tag(rs_switch_src_tag),
        .o_rs_src_data(rs_switch_src_data),
        .o_rs_src_rdy(rs_switch_src_rdy),
        .i_rs_stall(rs_switch_stall),
        .o_rs_stall(rs_stall)
    );

    procyon_rs #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_ROB_IDX_WIDTH(ROB_IDX_WIDTH),
        .OPTN_CDB_DEPTH(CDB_DEPTH),
        .OPTN_RS_DEPTH(OPTN_RS_IEU_DEPTH)
    ) procyon_rs_ieu_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(rob_redirect),
        .i_cdb_en(cdb_en),
        .i_cdb_data(cdb_data),
        .i_cdb_tag(cdb_tag),
        .i_rs_en(rs_switch_en[0]),
        .i_rs_opcode(rs_opcode),
        .i_rs_iaddr(rs_pc),
        .i_rs_insn(rs_insn),
        .i_rs_src_tag(rs_switch_src_tag),
        .i_rs_src_data(rs_switch_src_data),
        .i_rs_src_rdy(rs_switch_src_rdy),
        .i_rs_dst_tag(rs_dst_tag),
        .o_rs_stall(rs_switch_stall[0]),
        .i_fu_stall(fu_stall[0]),
        .o_fu_valid(fu_valid[0]),
        .o_fu_opcode(fu_opcode[0]),
        .o_fu_iaddr(fu_iaddr[0]),
        .o_fu_insn(fu_insn[0]),
        .o_fu_src_a(fu_src_a[0]),
        .o_fu_src_b(fu_src_b[0]),
        .o_fu_tag(fu_tag[0])
    );

    procyon_ieu #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_ROB_IDX_WIDTH(ROB_IDX_WIDTH)
    ) procyon_ieu_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(rob_redirect),
        .o_cdb_en(cdb_en[0]),
        .o_cdb_redirect(cdb_redirect[0]),
        .o_cdb_data(cdb_data[0]),
        .o_cdb_addr(cdb_addr[0]),
        .o_cdb_tag(cdb_tag[0]),
        .i_fu_valid(fu_valid[0]),
        .i_fu_opcode(fu_opcode[0]),
        .i_fu_iaddr(fu_iaddr[0]),
        .i_fu_insn(fu_insn[0]),
        .i_fu_src_a(fu_src_a[0]),
        .i_fu_src_b(fu_src_b[0]),
        .i_fu_tag(fu_tag[0]),
        .o_fu_stall(fu_stall[0])
    );

    procyon_rs #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_ROB_IDX_WIDTH(ROB_IDX_WIDTH),
        .OPTN_CDB_DEPTH(CDB_DEPTH),
        .OPTN_RS_DEPTH(OPTN_RS_IEU_DEPTH)
    ) procyon_rs_lsu_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(rob_redirect),
        .i_cdb_en(cdb_en),
        .i_cdb_data(cdb_data),
        .i_cdb_tag(cdb_tag),
        .i_rs_en(rs_switch_en[1]),
        .i_rs_opcode(rs_opcode),
        .i_rs_iaddr(rs_pc),
        .i_rs_insn(rs_insn),
        .i_rs_src_tag(rs_switch_src_tag),
        .i_rs_src_data(rs_switch_src_data),
        .i_rs_src_rdy(rs_switch_src_rdy),
        .i_rs_dst_tag(rs_dst_tag),
        .o_rs_stall(rs_switch_stall[1]),
        .i_fu_stall(fu_stall[1]),
        .o_fu_valid(fu_valid[1]),
        .o_fu_opcode(fu_opcode[1]),
        .o_fu_iaddr(fu_iaddr[1]),
        .o_fu_insn(fu_insn[1]),
        .o_fu_src_a(fu_src_a[1]),
        .o_fu_src_b(fu_src_b[1]),
        .o_fu_tag(fu_tag[1])
    );

    procyon_lsu #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_LQ_DEPTH(OPTN_LQ_DEPTH),
        .OPTN_SQ_DEPTH(OPTN_SQ_DEPTH),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE),
        .OPTN_ROB_IDX_WIDTH(ROB_IDX_WIDTH),
        .OPTN_MHQ_IDX_WIDTH(MHQ_IDX_WIDTH)
    ) procyon_lsu_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(rob_redirect),
        .o_cdb_en(cdb_en[1]),
        .o_cdb_redirect(cdb_redirect[1]),
        .o_cdb_data(cdb_data[1]),
        .o_cdb_addr(cdb_addr[1]),
        .o_cdb_tag(cdb_tag[1]),
        .i_fu_valid(fu_valid[1]),
        .i_fu_opcode(fu_opcode[1]),
        .i_fu_iaddr(fu_iaddr[1]),
        .i_fu_insn(fu_insn[1]),
        .i_fu_src_a(fu_src_a[1]),
        .i_fu_src_b(fu_src_b[1]),
        .i_fu_tag(fu_tag[1]),
        .o_fu_stall(fu_stall[1]),
        .i_rob_retire_tag(lsu_retire_tag),
        .i_rob_retire_lq_en(lsu_retire_lq_en),
        .i_rob_retire_sq_en(lsu_retire_sq_en),
        .o_rob_retire_lq_ack(lsu_retire_lq_ack),
        .o_rob_retire_sq_ack(lsu_retire_sq_ack),
        .o_rob_retire_misspeculated(lsu_retire_misspeculated),
        .i_mhq_lookup_retry(mhq_lookup_retry),
        .i_mhq_lookup_replay(mhq_lookup_replay),
        .i_mhq_lookup_tag(mhq_lookup_tag),
        .o_mhq_lookup_valid(mhq_lookup_valid),
        .o_mhq_lookup_dc_hit(mhq_lookup_dc_hit),
        .o_mhq_lookup_addr(mhq_lookup_addr),
        .o_mhq_lookup_lsu_func(mhq_lookup_lsu_func),
        .o_mhq_lookup_data(mhq_lookup_data),
        .o_mhq_lookup_we(mhq_lookup_we),
        .i_mhq_fill_en(mhq_fill_en),
        .i_mhq_fill_tag(mhq_fill_tag),
        .i_mhq_fill_dirty(mhq_fill_dirty),
        .i_mhq_fill_addr(mhq_fill_addr),
        .i_mhq_fill_data(mhq_fill_data)
    );

    procyon_ccu #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_MHQ_DEPTH(OPTN_MHQ_DEPTH),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE),
        .OPTN_WB_ADDR_WIDTH(OPTN_WB_ADDR_WIDTH),
        .OPTN_WB_DATA_WIDTH(OPTN_WB_DATA_WIDTH)
    ) procyon_ccu_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_mhq_lookup_valid(mhq_lookup_valid),
        .i_mhq_lookup_dc_hit(mhq_lookup_dc_hit),
        .i_mhq_lookup_addr(mhq_lookup_addr),
        .i_mhq_lookup_lsu_func(mhq_lookup_lsu_func),
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
