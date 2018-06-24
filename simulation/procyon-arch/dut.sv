`timescale 1ns/1ns

`include "../common/test_common.svh"

import procyon_types::*;

module dut (
    input  logic                              clk,
    input  logic                              n_rst,

    // SRAM interface
    output logic [`SRAM_ADDR_WIDTH-1:0]       o_sram_addr,
    input  logic [`SRAM_DATA_WIDTH-1:0]       i_sram_dq,
    output logic [`SRAM_DATA_WIDTH-1:0]       o_sram_dq,
    output logic                              o_sram_ce_n,
    output logic                              o_sram_we_n,
    output logic                              o_sram_oe_n,
    output logic                              o_sram_ub_n,
    output logic                              o_sram_lb_n,

    // FIXME: To test if simulations pass/fail
    output procyon_data_t                     o_sim_tp,
    output logic                              o_sim_retire,

    // FIXME: Temporary instruction cache interface
    input  procyon_data_t                     i_ic_insn,
    input  logic                              i_ic_valid,
    output procyon_addr_t                     o_ic_pc,
    output logic                              o_ic_en
);

    logic                              wb_clk;
    logic                              wb_rst;
    logic                              wb_ack;
    logic                              wb_stall;
    wb_data_t                          wb_data_i;
    logic                              wb_cyc;
    logic                              wb_stb;
    logic                              wb_we;
    wb_byte_select_t                   wb_sel;
    wb_addr_t                          wb_addr;
    wb_data_t                          wb_data_o;

    logic                              sram_we_n;
/* verilator lint_off UNOPTFLAT */
    logic [`SRAM_DATA_WIDTH-1:0]       sram_dq;
/* verilator lint_on  UNOPTFLAT */

/* verilator lint_off UNUSED */
    // FIXME: FPGA debugging output
    logic                              rob_redirect;
    procyon_addr_t                     rob_redirect_addr;
    logic                              regmap_retire_en;
    procyon_reg_t                      regmap_retire_rdest;
    procyon_data_t                     regmap_retire_data;
/* verilator lint_on  UNUSED */

    assign o_sim_retire        = regmap_retire_en;

    assign wb_clk              = clk;
    assign wb_rst              = ~n_rst;

    assign sram_dq             = sram_we_n ? i_sram_dq : {(`SRAM_DATA_WIDTH){1'bz}};
    assign o_sram_we_n         = sram_we_n;
    assign o_sram_dq           = sram_dq;

    procyon procyon (
        .clk(clk),
        .n_rst(n_rst),
        .o_sim_tp(o_sim_tp),
        .o_rob_redirect(rob_redirect),
        .o_rob_redirect_addr(rob_redirect_addr),
        .o_regmap_retire_en(regmap_retire_en),
        .o_regmap_retire_rdest(regmap_retire_rdest),
        .o_regmap_retire_data(regmap_retire_data),
        .i_ic_insn(i_ic_insn),
        .i_ic_valid(i_ic_valid),
        .o_ic_pc(o_ic_pc),
        .o_ic_en(o_ic_en),
        .i_wb_clk(wb_clk),
        .i_wb_rst(wb_rst),
        .i_wb_ack(wb_ack),
        .i_wb_stall(wb_stall),
        .i_wb_data(wb_data_i),
        .o_wb_cyc(wb_cyc),
        .o_wb_stb(wb_stb),
        .o_wb_we(wb_we),
        .o_wb_sel(wb_sel),
        .o_wb_addr(wb_addr),
        .o_wb_data(wb_data_o)
    );

    wb_sram #(
        .DATA_WIDTH(`WB_DATA_WIDTH),
        .ADDR_WIDTH(`WB_ADDR_WIDTH),
        .BASE_ADDR(`WB_SRAM_BASE_ADDR),
        .FIFO_DEPTH(`WB_SRAM_FIFO_DEPTH)
    ) wb_sram_inst (
        .i_wb_clk(wb_clk),
        .i_wb_rst(wb_rst),
        .i_wb_cyc(wb_cyc),
        .i_wb_stb(wb_stb),
        .i_wb_we(wb_we),
        .i_wb_sel(wb_sel),
        .i_wb_addr(wb_addr),
        .i_wb_data(wb_data_o),
        .o_wb_data(wb_data_i),
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
