`timescale 1ns/1ns

import procyon_types::*;

module dut (
    input  logic                  clk,
    input  logic                  n_rst,

    // FIXME: To test if simulations pass/fail
    output procyon_data_t         o_sim_tp,

    // FIXME: Temporary instruction cache interface
    input  procyon_data_t         i_ic_insn,
    input  logic                  i_ic_valid,
    output procyon_addr_t         o_ic_pc,
    output logic                  o_ic_en,

    // FIXME: Temporary data cache interface
    input  logic                  i_dc_hit,
    input  procyon_data_t         i_dc_rdata,
    output logic                  o_dc_re,
    output procyon_addr_t         o_dc_addr,

    // FIXME: Temporary store retire to cache interface
    input  logic                  i_sq_retire_dc_hit,
    input  logic                  i_sq_retire_msq_full,
    output logic                  o_sq_retire_en,
    output procyon_byte_select_t  o_sq_retire_byte_en,
    output procyon_addr_t         o_sq_retire_addr,
    output procyon_data_t         o_sq_retire_data
);

/* verilator lint_off UNUSED */
    // FIXME: FPGA debugging output
    logic           rob_redirect;
    procyon_addr_t  rob_redirect_addr;
    logic           regmap_retire_wr_en;
    procyon_reg_t   regmap_retire_rdest;
    procyon_data_t  regmap_retire_data;
/* verilator lint_on  UNUSED */

    procyon procyon (
        .clk(clk),
        .n_rst(n_rst),
        .o_sim_tp(o_sim_tp),
        .o_rob_redirect(rob_redirect),
        .o_rob_redirect_addr(rob_redirect_addr),
        .o_regmap_retire_wr_en(regmap_retire_wr_en),
        .o_regmap_retire_rdest(regmap_retire_rdest),
        .o_regmap_retire_data(regmap_retire_data),
        .i_ic_insn(i_ic_insn),
        .i_ic_valid(i_ic_valid),
        .o_ic_pc(o_ic_pc),
        .o_ic_en(o_ic_en),
        .i_dc_hit(i_dc_hit),
        .i_dc_rdata(i_dc_rdata),
        .o_dc_re(o_dc_re),
        .o_dc_addr(o_dc_addr),
        .i_sq_retire_dc_hit(i_sq_retire_dc_hit),
        .i_sq_retire_msq_full(i_sq_retire_msq_full),
        .o_sq_retire_en(o_sq_retire_en),
        .o_sq_retire_byte_en(o_sq_retire_byte_en),
        .o_sq_retire_addr(o_sq_retire_addr),
        .o_sq_retire_data(o_sq_retire_data)
    );

endmodule
