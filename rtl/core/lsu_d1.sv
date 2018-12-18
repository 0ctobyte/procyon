// LSU dcache stage 1

`include "common.svh"
import procyon_types::*;

module lsu_d1 (
    input  logic                clk,
    input  logic                n_rst,

    input  logic                i_flush,

    // Inputs from previous pipeline stage
    input  logic                i_valid,
    input  procyon_lsu_func_t   i_lsu_func,
    input  procyon_lq_select_t  i_lq_select,
    input  procyon_sq_select_t  i_sq_select,
    input  procyon_tag_t        i_tag,
    input  procyon_addr_t       i_addr,
    input  procyon_data_t       i_retire_data,
    input  logic                i_retire,
    input  logic                i_replay,

    // Input from LQ for allocated entry select
    input  procyon_lq_select_t  i_alloc_lq_select,

    // Outputs to next pipeline stage
    output logic                o_valid,
    output procyon_lsu_func_t   o_lsu_func,
    output procyon_lq_select_t  o_lq_select,
    output procyon_sq_select_t  o_sq_select,
    output procyon_tag_t        o_tag,
    output procyon_addr_t       o_addr,
    output procyon_data_t       o_retire_data,
    output logic                o_retire
);

    always_ff @(posedge clk) begin
        o_lsu_func    <= i_lsu_func;
        o_lq_select   <= i_replay ? i_lq_select : i_alloc_lq_select;
        o_sq_select   <= i_sq_select;
        o_tag         <= i_tag;
        o_addr        <= i_addr;
        o_retire_data <= i_retire_data;
        o_retire      <= i_retire;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_valid <= 1'b0;
        else        o_valid <= ~i_flush & i_valid;
    end

endmodule
