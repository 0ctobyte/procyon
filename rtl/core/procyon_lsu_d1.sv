// LSU dcache stage 1

`include "procyon_constants.svh"

module procyon_lsu_d1 #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_LQ_DEPTH      = 8,
    parameter OPTN_SQ_DEPTH      = 8,
    parameter OPTN_ROB_IDX_WIDTH = 5
)(
    input  logic                            clk,
    input  logic                            n_rst,

    input  logic                            i_flush,

    // Inputs from previous pipeline stage
    input  logic                            i_valid,
    input  logic [`PCYN_LSU_FUNC_WIDTH-1:0] i_lsu_func,
    input  logic [OPTN_LQ_DEPTH-1:0]        i_lq_select,
    input  logic [OPTN_SQ_DEPTH-1:0]        i_sq_select,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]   i_tag,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_addr,
    input  logic [OPTN_DATA_WIDTH-1:0]      i_retire_data,
    input  logic                            i_retire,
    input  logic                            i_replay,

    // Input from LQ for allocated entry select
    input  logic [OPTN_LQ_DEPTH-1:0]        i_alloc_lq_select,

    // Outputs to next pipeline stage
    output logic                            o_valid,
    output logic [`PCYN_LSU_FUNC_WIDTH-1:0] o_lsu_func,
    output logic [OPTN_LQ_DEPTH-1:0]        o_lq_select,
    output logic [OPTN_SQ_DEPTH-1:0]        o_sq_select,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]   o_tag,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_addr,
    output logic [OPTN_DATA_WIDTH-1:0]      o_retire_data,
    output logic                            o_retire
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
