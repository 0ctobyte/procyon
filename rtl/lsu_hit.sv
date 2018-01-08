// D$ tag lookup unit
// Lookup address in tag memory to determine hit status and way address
// If address misses in the D$ tag memory then send request to MSHQ

import types::*;

module lsu_hit #(
    parameter ADDR_WIDTH      = 32,
    parameter TAG_WIDTH       = 6,
    parameter DC_BLOCK_WIDTH  = 5,
    parameter DC_INDEX_WIDTH  = 4,
    parameter DC_WAY_WIDTH    = 1,
    parameter DC_TAG_WIDTH    = 23
) (
    input  logic                        clk,
    input  logic                        n_rst,

    // Inputs from last stage in the LSU pipeline
    input  lsu_func_t                   i_lsu_func,
    input  logic [ADDR_WIDTH-1:0]       i_addr,
    input  logic [TAG_WIDTH-1:0]        i_tag,
    input  logic                        i_valid,

    // Outputs to next stage in the LSU pipeline
    output lsu_func_t                   o_lsu_func,
    output logic [ADDR_WIDTH-1:0]       o_addr,
    output logic [TAG_WIDTH-1:0]        o_tag,
    output logic [DC_WAY_WIDTH-1:0]     o_way_addr, 
    output logic                        o_hit,
    output logic                        o_valid,

    // Access D$ tag memory for address hit
    input  logic                        i_dc_hit,
    input  logic [DC_WAY_WIDTH-1:0]     i_dc_way_addr,
    output logic [DC_INDEX_WIDTH-1:0]   o_dc_index,
    output logic [DC_TAG_WIDTH-1:0]     o_dc_tag,

    // On a D$ load miss, send load to MSHQ
    output lsu_func_t                   o_mshq_lsu_func,
    output logic [ADDR_WIDTH-1:0]       o_mshq_addr,
    output logic [TAG_WIDTH-1:0]        o_mshq_tag,
    output logic                        o_mshq_en
);

    // Assign outputs to D$ for tag lookup
    assign o_dc_index               = i_addr[DC_INDEX_WIDTH+DC_BLOCK_WIDTH-1:DC_BLOCK_WIDTH];
    assign o_dc_tag                 = i_addr[ADDR_WIDTH-1:ADDR_WIDTH-DC_TAG_WIDTH];

    // Assign outputs to MSHQ
    assign o_mshq_lsu_func          = i_lsu_func;
    assign o_mshq_addr              = i_addr;
    assign o_mshq_tag               = i_tag;
    assign o_mshq_en                = i_valid && ~i_dc_hit;

    // Assign outputs to next stage in the LSU pipeline
    assign o_lsu_func               = i_lsu_func;
    assign o_addr                   = i_addr;
    assign o_tag                    = i_tag;
    assign o_way_addr               = i_dc_way_addr;
    assign o_hit                    = i_dc_hit;
    assign o_valid                  = i_valid;

endmodule
