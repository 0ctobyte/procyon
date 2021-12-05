/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// SRAM controller with a wishbone interface
// Controls the IS61WV102416BLL SRAM chip

// Constants
`define SRAM_DATA_WIDTH 16
`define SRAM_ADDR_WIDTH 20
`define SRAM_DATA_SIZE  `SRAM_DATA_WIDTH / 8
`define SRAM_ADDR_SPAN  2097152 // 2M bytes, or 1M 2-byte words

`include "../lib/procyon_biu_wb_constants.svh"

module sram_top #(
    parameter OPTN_WB_DATA_WIDTH = 16,
    parameter OPTN_WB_ADDR_WIDTH = 32,
    parameter OPTN_BASE_ADDR     = 0,

    parameter WB_DATA_SIZE       = OPTN_WB_DATA_WIDTH / 8
)(
    // Wishbone Interface
    input       logic                            i_wb_clk,
    input       logic                            i_wb_rst,
    input       logic                            i_wb_cyc,
    input       logic                            i_wb_stb,
    input       logic                            i_wb_we,
    input       logic [`WB_CTI_WIDTH-1:0]        i_wb_cti,
    input       logic [`WB_BTE_WIDTH-1:0]        i_wb_bte,
    input       logic [WB_DATA_SIZE-1:0]         i_wb_sel,
    input       logic [OPTN_WB_ADDR_WIDTH-1:0]   i_wb_addr,
    input       logic [OPTN_WB_DATA_WIDTH-1:0]   i_wb_data,
    output      logic [OPTN_WB_DATA_WIDTH-1:0]   o_wb_data,
    output      logic                            o_wb_ack,

    // SRAM interface
    output      logic                            o_sram_ce_n,
    output      logic                            o_sram_oe_n,
    output      logic                            o_sram_we_n,
    output      logic                            o_sram_lb_n,
    output      logic                            o_sram_ub_n,
    output      logic [`SRAM_ADDR_WIDTH-1:0]     o_sram_addr,
    inout  wire logic [`SRAM_DATA_WIDTH-1:0]     io_sram_dq
);

    logic n_rst;
    assign n_rst = ~i_wb_rst;

    logic biu_done;
    logic [OPTN_WB_DATA_WIDTH-1:0] biu_data_o;
    logic biu_en;
    logic biu_we;
    logic biu_eob;
    logic [WB_DATA_SIZE-1:0] biu_sel;
    logic [OPTN_WB_ADDR_WIDTH-1:0] biu_addr;
    logic [OPTN_WB_DATA_WIDTH-1:0] biu_data_i;

    procyon_biu_responder_wb #(
        .OPTN_ADDR_WIDTH(OPTN_WB_ADDR_WIDTH),
        .OPTN_WB_DATA_WIDTH(OPTN_WB_DATA_WIDTH),
        .OPTN_WB_ADDR_WIDTH(OPTN_WB_ADDR_WIDTH),
        .OPTN_BASE_ADDR(OPTN_BASE_ADDR)
    ) procyon_biu_responder_wb_inst (
        .i_wb_clk(i_wb_clk),
        .i_wb_rst(i_wb_rst),
        .i_wb_cyc(i_wb_cyc),
        .i_wb_stb(i_wb_stb),
        .i_wb_we(i_wb_we),
        .i_wb_cti(i_wb_cti),
        .i_wb_bte(i_wb_bte),
        .i_wb_sel(i_wb_sel),
        .i_wb_addr(i_wb_addr),
        .i_wb_data(i_wb_data),
        .o_wb_data(o_wb_data),
        .o_wb_ack(o_wb_ack),
        .i_biu_done(biu_done),
        .i_biu_data(biu_data_o),
        .o_biu_en(biu_en),
        .o_biu_we(biu_we),
        .o_biu_eob(biu_eob),
        .o_biu_sel(biu_sel),
        .o_biu_addr(biu_addr),
        .o_biu_data(biu_data_i)
    );

    sram_ctrl #(
        .OPTN_DATA_WIDTH(OPTN_WB_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_WB_ADDR_WIDTH)
    ) sram_ctrl_inst (
        .clk(i_wb_clk),
        .n_rst(n_rst),
        .i_biu_en(biu_en),
        .i_biu_we(biu_we),
        .i_biu_eob(biu_eob),
        .i_biu_sel(biu_sel),
        .i_biu_addr(biu_addr),
        .i_biu_data(biu_data_i),
        .o_biu_done(biu_done),
        .o_biu_data(biu_data_o),
        .o_sram_ce_n(o_sram_ce_n),
        .o_sram_oe_n(o_sram_oe_n),
        .o_sram_we_n(o_sram_we_n),
        .o_sram_lb_n(o_sram_lb_n),
        .o_sram_ub_n(o_sram_ub_n),
        .o_sram_addr(o_sram_addr),
        .io_sram_dq(io_sram_dq)
    );

endmodule
