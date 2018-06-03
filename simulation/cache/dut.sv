`timescale 1ns/1ns

`include "test_common.svh"

module dut (
    input  logic                              clk,
    input  logic                              n_rst,

    input  logic                              i_cache_re,
    input  logic                              i_cache_we,
    input  logic                              i_cache_fe,
    input  logic                              i_cache_valid,
    input  logic [`CACHE_TAG_WIDTH-1:0]       i_cache_tag,
    input  logic [`CACHE_INDEX_WIDTH-1:0]     i_cache_index,
    input  logic [`CACHE_OFFSET_WIDTH-1:0]    i_cache_offset,
    input  logic [`DATA_WIDTH-1:0]            i_cache_wdata,
    input  logic [`CACHE_LINE_WIDTH-1:0]      i_cache_fdata,
    output logic                              o_cache_dirty,
    output logic                              o_cache_hit,
    output logic [`CACHE_TAG_WIDTH-1:0]       o_cache_tag,
    output logic [`DATA_WIDTH-1:0]            o_cache_rdata,
    output logic [`CACHE_LINE_WIDTH-1:0]      o_cache_vdata,

    output logic                              o_wb_rst,
    input  logic                              i_wb_cyc,
    input  logic                              i_wb_stb,
    input  logic                              i_wb_we,
    input  logic [`WB_DATA_WIDTH/8-1:0]       i_wb_sel,
    input  logic [`WB_ADDR_WIDTH-1:0]         i_wb_addr,
    input  logic [`WB_DATA_WIDTH-1:0]         i_wb_data,
    output logic [`WB_DATA_WIDTH-1:0]         o_wb_data,
    output logic                              o_wb_ack,
    output logic                              o_wb_stall,

    output logic [`SRAM_ADDR_WIDTH-1:0]       o_sram_addr,
    input  logic [`SRAM_DATA_WIDTH-1:0]       i_sram_dq,
    output logic [`SRAM_DATA_WIDTH-1:0]       o_sram_dq,
    output logic                              o_sram_ce_n,
    output logic                              o_sram_we_n,
    output logic                              o_sram_oe_n,
    output logic                              o_sram_ub_n,
    output logic                              o_sram_lb_n
);

    logic                              wb_rst;

    logic [`WB_DATA_WIDTH-1:0]         wb_data;
    logic                              wb_ack;
    logic                              wb_stall;

    logic                              sram_we_n;
/* verilator lint_off UNOPTFLAT */
    logic [`SRAM_DATA_WIDTH-1:0]       sram_dq;
/* verilator lint_on  UNOPTFLAT */

    assign wb_rst              = ~n_rst;
    assign o_wb_rst            = wb_rst;
    assign o_wb_data           = wb_data;
    assign o_wb_ack            = wb_ack;
    assign o_wb_stall          = wb_stall;

    assign sram_dq             = sram_we_n ? i_sram_dq : {(`SRAM_DATA_WIDTH){1'bz}};
    assign o_sram_we_n         = sram_we_n;
    assign o_sram_dq           = sram_dq;

    cache #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ADDR_WIDTH(`WB_ADDR_WIDTH),
        .CACHE_SIZE(`CACHE_SIZE),
        .CACHE_LINE_SIZE(`CACHE_LINE_SIZE)
    ) cache_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_cache_re(i_cache_re),
        .i_cache_we(i_cache_we),
        .i_cache_fe(i_cache_fe),
        .i_cache_valid(i_cache_valid),
        .i_cache_offset(i_cache_offset),
        .i_cache_index(i_cache_index),
        .i_cache_tag(i_cache_tag),
        .i_cache_fdata(i_cache_fdata),
        .i_cache_wdata(i_cache_wdata),
        .o_cache_dirty(o_cache_dirty),
        .o_cache_hit(o_cache_hit),
        .o_cache_tag(o_cache_tag),
        .o_cache_vdata(o_cache_vdata),
        .o_cache_rdata(o_cache_rdata)
    );

    wb_sram #(
        .DATA_WIDTH(`WB_DATA_WIDTH),
        .ADDR_WIDTH(`WB_ADDR_WIDTH),
        .BASE_ADDR(`WB_SRAM_BASE_ADDR),
        .FIFO_DEPTH(`WB_SRAM_FIFO_DEPTH)
    ) wb_sram_inst (
        .i_wb_clk(clk),
        .i_wb_rst(wb_rst),
        .i_wb_cyc(i_wb_cyc),
        .i_wb_stb(i_wb_stb),
        .i_wb_we(i_wb_we),
        .i_wb_sel(i_wb_sel),
        .i_wb_addr(i_wb_addr),
        .i_wb_data(i_wb_data),
        .o_wb_data(wb_data),
        .o_wb_ack(wb_ack),
        .o_wb_stall(wb_stall),
        .io_sram_dq(sram_dq),
        .o_sram_addr(o_sram_addr),
        .o_sram_ce_n(o_sram_ce_n),
        .o_sram_oe_n(o_sram_oe_n),
        .o_sram_we_n(sram_we_n),
        .o_sram_ub_n(o_sram_ub_n),
        .o_sram_lb_n(o_sram_lb_n)
    );

endmodule
