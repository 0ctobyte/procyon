/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

`define SRAM_ADDR_WIDTH 20
`define SRAM_DATA_WIDTH 16

`define WB_CTI_WIDTH    3
`define WB_BTE_WIDTH    2

module dut #(
    parameter OPTN_DATA_WIDTH         = 32,
    parameter OPTN_INSN_WIDTH         = 32,
    parameter OPTN_ADDR_WIDTH         = 32,
    parameter OPTN_RAT_DEPTH          = 32,
    parameter OPTN_NUM_IEU            = 1,
    parameter OPTN_INSN_FIFO_DEPTH    = 32,
    parameter OPTN_ROB_DEPTH          = 128,
    parameter OPTN_RS_IEU_DEPTH       = 32,
    parameter OPTN_RS_LSU_DEPTH       = 32,
    parameter OPTN_LQ_DEPTH           = 16,
    parameter OPTN_SQ_DEPTH           = 16,
    parameter OPTN_VQ_DEPTH           = 16,
    parameter OPTN_MHQ_DEPTH          = 16,
    parameter OPTN_IFQ_DEPTH          = 8,
    parameter OPTN_IC_CACHE_SIZE      = 1024,
    parameter OPTN_IC_LINE_SIZE       = 32,
    parameter OPTN_IC_WAY_COUNT       = 1,
    parameter OPTN_DC_CACHE_SIZE      = 1024,
    parameter OPTN_DC_LINE_SIZE       = 32,
    parameter OPTN_DC_WAY_COUNT       = 1,
    parameter OPTN_WB_DATA_WIDTH      = 32,
    parameter OPTN_WB_ADDR_WIDTH      = 32,
    parameter OPTN_WB_SRAM_BASE_ADDR  = 0,
    parameter OPTN_HEX_FILE           = "",
    parameter OPTN_HEX_SIZE           = 0
)(
    input  logic                            clk,
    input  logic                            n_rst,

    // SRAM interface
    output logic [`SRAM_ADDR_WIDTH-1:0]     o_sram_addr,
    input  logic [`SRAM_DATA_WIDTH-1:0]     i_sram_dq,
    output logic [`SRAM_DATA_WIDTH-1:0]     o_sram_dq,
    output logic                            o_sram_ce_n,
    output logic                            o_sram_we_n,
    output logic                            o_sram_oe_n,
    output logic                            o_sram_ub_n,
    output logic                            o_sram_lb_n,

    // FIXME: To test if simulations pass/fail
    output logic [OPTN_DATA_WIDTH-1:0]      o_sim_tp,
    output logic                            o_sim_retire
);

    timeunit 1ns;
    timeprecision 1ns;

    logic [1:0] key;
/* verilator lint_off UNUSED */
    logic [6:0] hex [0:7];
    logic [17:0] ledr;
    logic [4:0] ledg;
/* verilator lint_on  UNUSED */

    always_ff @(posedge clk) begin
        key[0] <= 1'b0;
        key[1] <= ~key[1];
    end

    logic sram_we_n;
/* verilator lint_off UNOPTFLAT */
    logic [`SRAM_DATA_WIDTH-1:0] sram_dq;
/* verilator lint_on  UNOPTFLAT */

    assign sram_dq = sram_we_n ? i_sram_dq : 'z;
    assign o_sram_we_n = sram_we_n;
    assign o_sram_dq = sram_dq;

    procyon_sys_top #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_INSN_WIDTH(OPTN_INSN_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_RAT_DEPTH(OPTN_RAT_DEPTH),
        .OPTN_NUM_IEU(OPTN_NUM_IEU),
        .OPTN_INSN_FIFO_DEPTH(OPTN_INSN_FIFO_DEPTH),
        .OPTN_ROB_DEPTH(OPTN_ROB_DEPTH),
        .OPTN_RS_IEU_DEPTH(OPTN_RS_IEU_DEPTH),
        .OPTN_RS_LSU_DEPTH(OPTN_RS_LSU_DEPTH),
        .OPTN_LQ_DEPTH(OPTN_LQ_DEPTH),
        .OPTN_SQ_DEPTH(OPTN_SQ_DEPTH),
        .OPTN_VQ_DEPTH(OPTN_VQ_DEPTH),
        .OPTN_MHQ_DEPTH(OPTN_MHQ_DEPTH),
        .OPTN_IFQ_DEPTH(OPTN_IFQ_DEPTH),
        .OPTN_IC_CACHE_SIZE(OPTN_IC_CACHE_SIZE),
        .OPTN_IC_LINE_SIZE(OPTN_IC_LINE_SIZE),
        .OPTN_IC_WAY_COUNT(OPTN_IC_WAY_COUNT),
        .OPTN_DC_CACHE_SIZE(OPTN_DC_CACHE_SIZE),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE),
        .OPTN_DC_WAY_COUNT(OPTN_DC_WAY_COUNT),
        .OPTN_WB_DATA_WIDTH(OPTN_WB_DATA_WIDTH),
        .OPTN_WB_ADDR_WIDTH(OPTN_WB_ADDR_WIDTH),
        .OPTN_WB_SRAM_BASE_ADDR(OPTN_WB_SRAM_BASE_ADDR),
        .OPTN_HEX_FILE(OPTN_HEX_FILE),
        .OPTN_HEX_SIZE(OPTN_HEX_SIZE)
    ) procyon_sys_top_inst (
        .CLOCK_50(clk),
        .SW(n_rst),
        .KEY(key),
        .LEDR(ledr),
        .LEDG(ledg),
        .SRAM_DQ(sram_dq),
        .SRAM_ADDR(o_sram_addr),
        .SRAM_CE_N(o_sram_ce_n),
        .SRAM_OE_N(o_sram_oe_n),
        .SRAM_WE_N(sram_we_n),
        .SRAM_LB_N(o_sram_lb_n),
        .SRAM_UB_N(o_sram_ub_n),
        .HEX0(hex[0]),
        .HEX1(hex[1]),
        .HEX2(hex[2]),
        .HEX3(hex[3]),
        .HEX4(hex[4]),
        .HEX5(hex[5]),
        .HEX6(hex[6]),
        .HEX7(hex[7])
    );

    assign o_sim_retire = procyon_sys_top_inst.rat_retire_en;
    assign o_sim_tp = procyon_sys_top_inst.sim_tp;

endmodule
