`define SRAM_ADDR_WIDTH 20
`define SRAM_DATA_WIDTH 16

module dut #(
    parameter OPTN_DATA_WIDTH         = 32,
    parameter OPTN_WB_DATA_WIDTH      = 16,
    parameter OPTN_WB_ADDR_WIDTH      = 32,
    parameter OPTN_CACHE_SIZE         = 1024,
    parameter OPTN_CACHE_LINE_SIZE    = 32,
    parameter OPTN_WB_SRAM_BASE_ADDR  = 0,
    parameter OPTN_WB_SRAM_FIFO_DEPTH = 8,

    localparam CACHE_INDEX_WIDTH      = $clog2(OPTN_CACHE_SIZE / OPTN_CACHE_LINE_SIZE),
    localparam CACHE_TAG_WIDTH        = OPTN_WB_ADDR_WIDTH - CACHE_INDEX_WIDTH - $clog2(OPTN_CACHE_LINE_SIZE),
    localparam CACHE_LINE_WIDTH       = OPTN_CACHE_LINE_SIZE * 8
)(
    input  logic                            clk,
    input  logic                            n_rst,

    input  logic                            i_cache_wr_en,
    input  logic [CACHE_INDEX_WIDTH-1:0]    i_cache_wr_index,
    input  logic                            i_cache_wr_valid,
    input  logic                            i_cache_wr_dirty,
    input  logic [CACHE_TAG_WIDTH-1:0]      i_cache_wr_tag,
    input  logic [CACHE_LINE_WIDTH-1:0]     i_cache_wr_data,
    input  logic                            i_cache_rd_en,
    input  logic [CACHE_INDEX_WIDTH-1:0]    i_cache_rd_index,
    output logic                            o_cache_rd_valid,
    output logic                            o_cache_rd_dirty,
    output logic [CACHE_TAG_WIDTH-1:0]      o_cache_rd_tag,
    output logic [CACHE_LINE_WIDTH-1:0]     o_cache_rd_data,

    output logic                            o_wb_rst,
    input  logic                            i_wb_cyc,
    input  logic                            i_wb_stb,
    input  logic                            i_wb_we,
    input  logic [OPTN_WB_DATA_WIDTH/8-1:0] i_wb_sel,
    input  logic [OPTN_WB_ADDR_WIDTH-1:0]   i_wb_addr,
    input  logic [OPTN_WB_DATA_WIDTH-1:0]   i_wb_data,
    output logic [OPTN_WB_DATA_WIDTH-1:0]   o_wb_data,
    output logic                            o_wb_ack,
    output logic                            o_wb_stall,

    output logic [`SRAM_ADDR_WIDTH-1:0]     o_sram_addr,
    input  logic [`SRAM_DATA_WIDTH-1:0]     i_sram_dq,
    output logic [`SRAM_DATA_WIDTH-1:0]     o_sram_dq,
    output logic                            o_sram_ce_n,
    output logic                            o_sram_we_n,
    output logic                            o_sram_oe_n,
    output logic                            o_sram_ub_n,
    output logic                            o_sram_lb_n
);

    timeunit 1ns;
    timeprecision 1ns;

    logic                            wb_rst;
    logic [OPTN_WB_DATA_WIDTH-1:0]   wb_data;
    logic                            wb_ack;
    logic                            wb_stall;
    logic                            sram_we_n;
/* verilator lint_off UNOPTFLAT */
    logic [`SRAM_DATA_WIDTH-1:0]     sram_dq;
/* verilator lint_on  UNOPTFLAT */

    assign wb_rst      = ~n_rst;
    assign o_wb_rst    = wb_rst;
    assign o_wb_data   = wb_data;
    assign o_wb_ack    = wb_ack;
    assign o_wb_stall  = wb_stall;

    assign sram_dq     = sram_we_n ? i_sram_dq : {(`SRAM_DATA_WIDTH){1'bz}};
    assign o_sram_we_n = sram_we_n;
    assign o_sram_dq   = sram_dq;

    cache #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_WB_ADDR_WIDTH),
        .OPTN_CACHE_SIZE(OPTN_CACHE_SIZE),
        .OPTN_CACHE_LINE_SIZE(OPTN_CACHE_LINE_SIZE)
    ) cache_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_cache_wr_en(i_cache_wr_en),
        .i_cache_wr_index(i_cache_wr_index),
        .i_cache_wr_valid(i_cache_wr_valid),
        .i_cache_wr_dirty(i_cache_wr_dirty),
        .i_cache_wr_tag(i_cache_wr_tag),
        .i_cache_wr_data(i_cache_wr_data),
        .i_cache_rd_en(i_cache_rd_en),
        .i_cache_rd_index(i_cache_rd_index),
        .o_cache_rd_valid(o_cache_rd_valid),
        .o_cache_rd_dirty(o_cache_rd_dirty),
        .o_cache_rd_tag(o_cache_rd_tag),
        .o_cache_rd_data(o_cache_rd_data)
    );

    wb_sram #(
        .DATA_WIDTH(OPTN_WB_DATA_WIDTH),
        .ADDR_WIDTH(OPTN_WB_ADDR_WIDTH),
        .BASE_ADDR(OPTN_WB_SRAM_BASE_ADDR),
        .FIFO_DEPTH(OPTN_WB_SRAM_FIFO_DEPTH)
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
