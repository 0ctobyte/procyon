// Grab data from data cache and update store queue if necessary

import types::*;

module lsu_mem #(
    parameter DATA_WIDTH       = 32,
    parameter ADDR_WIDTH       = 32,
    parameter TAG_WIDTH        = 6,
    parameter DC_LINE_WIDTH    = 5,
    parameter DC_INDEX_WIDTH   = 4,
    parameter DC_WAY_WIDTH     = 1
) (
    input  logic                                                   clk,
    input  logic                                                   n_rst,

    // Inputs from last stage in the LSU pipeline
    input  lsu_func_t                                              i_lsu_func,
    input  logic [ADDR_WIDTH-1:0]                                  i_addr,
    input  logic [TAG_WIDTH-1:0]                                   i_tag,
    input  logic [DC_WAY_WIDTH-1:0]                                i_way_addr,
    input  logic                                                   i_hit,
    input  logic                                                   i_valid,

    // Output to writeback FIFO
    output logic [DATA_WIDTH-1:0]                                  o_data,
    output logic [ADDR_WIDTH-1:0]                                  o_addr,
    output logic [TAG_WIDTH-1:0]                                   o_tag,
    output logic                                                   o_valid,

    // Access D$ data memory for load data
    input  logic [DATA_WIDTH-1:0]                                  i_dc_data,
    output logic [DC_INDEX_WIDTH+DC_WAY_WIDTH+DC_LINE_WIDTH-1:0]   o_dc_addr
);

    logic       is_store;

    // Determine if op is load or store
    assign is_store       = (i_lsu_func == LSU_FUNC_SB) || (i_lsu_func == LSU_FUNC_SH) || (i_lsu_func == LSU_FUNC_SW);

    // Access D$
    assign i_dc_addr      = {i_addr[DC_INDEX_WIDTH+DC_LINE_WIDTH-1:DC_LINE_WIDTH], i_way_addr, i_addr[DC_LINE_WIDTH-1:0]};

    // Output to WB stage
    assign o_addr         = i_addr;
    assign o_tag          = i_tag;
    assign o_valid        = i_valid && i_hit && ~is_store;

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

endmodule
