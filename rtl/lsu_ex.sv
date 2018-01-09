// LSU execute stage
// Grab data from D$ for loads and sign extend or zero extend if necessary

`include "common.svh"
import types::*;

module lsu_ex #(
    parameter DATA_WIDTH       = `DATA_WIDTH,
    parameter ADDR_WIDTH       = `ADDR_WIDTH,
    parameter TAG_WIDTH        = `TAG_WIDTH,
    parameter DC_LINE_WIDTH    = `DC_LINE_WIDTH,
    parameter DC_SET_WIDTH     = `DC_SET_WIDTH,
    parameter DC_WAY_WIDTH     = `DC_WAY_WIDTH,
    parameter DC_TAG_WIDTH     = `DC_TAG_WIDTH
) (
    input  logic                                                   clk,
    input  logic                                                   n_rst,

    // Inputs from last stage in the LSU pipeline
    input  lsu_func_t                                              i_lsu_func,
    input  logic [ADDR_WIDTH-1:0]                                  i_addr,
    input  logic [TAG_WIDTH-1:0]                                   i_tag,
    input  logic                                                   i_valid,

    // Output to writeback stage
    output logic [DATA_WIDTH-1:0]                                  o_data,
    output logic [ADDR_WIDTH-1:0]                                  o_addr,
    output logic [TAG_WIDTH-1:0]                                   o_tag,
    output logic                                                   o_valid,

    // Access D$ tag memory for address hit
    input  logic                                                   i_dc_hit,
    input  logic [DC_WAY_WIDTH-1:0]                                i_dc_way_addr,
    output logic [DC_SET_WIDTH-1:0]                                o_dc_index,
    output logic [DC_TAG_WIDTH-1:0]                                o_dc_tag,

    // Access D$ data memory for load data
    input  logic [DATA_WIDTH-1:0]                                  i_dc_data,
    output logic [DC_SET_WIDTH+DC_WAY_WIDTH+DC_LINE_WIDTH-1:0]     o_dc_addr,

    // On a D$ load miss, send load to MSHQ
    output lsu_func_t                                              o_mshq_lsu_func,
    output logic [ADDR_WIDTH-1:0]                                  o_mshq_addr,
    output logic [TAG_WIDTH-1:0]                                   o_mshq_tag,
    output logic                                                   o_mshq_en
);
    // Access D$ tag
    assign o_dc_index               = i_addr[DC_SET_WIDTH+DC_LINE_WIDTH-1:DC_LINE_WIDTH];
    assign o_dc_tag                 = i_addr[ADDR_WIDTH-1:ADDR_WIDTH-DC_TAG_WIDTH];

    // Access D$ data
    assign o_dc_addr                = {i_addr[DC_SET_WIDTH+DC_LINE_WIDTH-1:DC_LINE_WIDTH], i_dc_way_addr, i_addr[DC_LINE_WIDTH-1:0]};

    // Assign outputs to MSHQ
    assign o_mshq_lsu_func          = i_lsu_func;
    assign o_mshq_addr              = i_addr;
    assign o_mshq_tag               = i_tag;

    // Output to WB stage
    assign o_addr                   = i_addr;
    assign o_tag                    = i_tag;

    // LB and LH loads 8 bits or 16 bits respectively and sign extends to
    // 32-bits. LBU and LHU loads 8 bits or 16 bits respectively and zero
    // extends to 32 bits.
    always_comb begin
        case (i_lsu_func)
            LSU_FUNC_LB:  o_data = {{(DATA_WIDTH-8){i_dc_data[7]}, i_dc_data[7:0]};
            LSU_FUNC_LH:  o_data = {{(DATA_WIDTH-16){i_dc_data[15]}, i_dc_data[15:0]};
            LSU_FUNC_LW:  o_data = i_dc_data;
            LSU_FUNC_LBU: o_data = {{(DATA_WIDTH-8){1'b0}, i_dc_data[7:0]};
            LSU_FUNC_LHU: o_data = {{(DATA_WIDTH-16){1'b0}, i_dc_data[15:0]};
            default:      o_data = i_dc_data;
        endcase
    end

    // o_valid = i_valid if the op is a store since stores "complete" here
    // For load ops, o_valid is only true if it hits in the D$
    // Only send to MSHQ if op is a load that misses in the D$
    always_comb begin
        case (i_lsu_func)
            LSU_FUNC_SB: {o_valid, o_mshq_en} = {i_valid, 1'b0};
            LSU_FUNC_SH: {o_valid, o_mshq_en} = {i_valid, 1'b0};
            LSU_FUNC_SW: {o_valid, o_mshq_en} = {i_valid, 1'b0};
            default:     {o_valid, o_mshq_en} = {(i_valid && i_dc_hit), (i_valid && ~i_dc_hit)};
        endcase
    end

endmodule
