// Data Cache - Data/Tag RAM read stage

`include "procyon_constants.svh"

module procyon_dcache_d0 #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_DC_CACHE_SIZE = 1024,
    parameter OPTN_DC_LINE_SIZE  = 32,
    parameter OPTN_DC_WAY_COUNT  = 1,

    parameter DC_LINE_WIDTH      = OPTN_DC_LINE_SIZE * 8,
    parameter DC_OFFSET_WIDTH    = $clog2(OPTN_DC_LINE_SIZE),
    parameter DC_INDEX_WIDTH     = $clog2(OPTN_DC_CACHE_SIZE / OPTN_DC_LINE_SIZE / OPTN_DC_WAY_COUNT),
    parameter DC_TAG_WIDTH       = OPTN_ADDR_WIDTH - DC_INDEX_WIDTH - DC_OFFSET_WIDTH,
    parameter WORD_SIZE          = OPTN_DATA_WIDTH / 8
)(
    input  logic                            clk,
    input  logic                            n_rst,

    input  logic                            i_wr_en,
    input  logic [DC_TAG_WIDTH-1:0]         i_tag,
    input  logic [DC_INDEX_WIDTH-1:0]       i_index,
    input  logic [DC_OFFSET_WIDTH-1:0]      i_offset,
    input  logic [`PCYN_LSU_FUNC_WIDTH-1:0] i_lsu_func,
    input  logic [OPTN_DATA_WIDTH-1:0]      i_data,
    input  logic                            i_valid,
    input  logic                            i_dirty,
    input  logic                            i_fill,
    input  logic [DC_LINE_WIDTH-1:0]        i_fill_data,

    output logic                            o_wr_en,
    output logic [DC_TAG_WIDTH-1:0]         o_tag,
    output logic [DC_INDEX_WIDTH-1:0]       o_index,
    output logic [DC_OFFSET_WIDTH-1:0]      o_offset,
    output logic [WORD_SIZE-1:0]            o_byte_sel,
    output logic [OPTN_DATA_WIDTH-1:0]      o_data,
    output logic                            o_valid,
    output logic                            o_dirty,
    output logic                            o_fill,
    output logic [DC_LINE_WIDTH-1:0]        o_fill_data
);

    logic [WORD_SIZE-1:0] byte_sel;

    // Derive byte select signals from the LSU op type
    always_comb begin
        case (i_lsu_func)
            `PCYN_LSU_FUNC_LB:  byte_sel = {{(WORD_SIZE-1){1'b0}}, 1'b1};
            `PCYN_LSU_FUNC_LH:  byte_sel = {{(WORD_SIZE/2){1'b0}}, {(WORD_SIZE/2){1'b1}}};
            `PCYN_LSU_FUNC_LBU: byte_sel = {{(WORD_SIZE-1){1'b0}}, 1'b1};
            `PCYN_LSU_FUNC_LHU: byte_sel = {{(WORD_SIZE/2){1'b0}}, {(WORD_SIZE/2){1'b1}}};
            `PCYN_LSU_FUNC_SB:  byte_sel = {{(WORD_SIZE-1){1'b0}}, 1'b1};
            `PCYN_LSU_FUNC_SH:  byte_sel = {{(WORD_SIZE/2){1'b0}}, {(WORD_SIZE/2){1'b1}}};
            default:            byte_sel = {(WORD_SIZE){1'b1}};
        endcase
    end

    always_ff @(posedge clk) begin
        o_tag       <= i_tag;
        o_index     <= i_index;
        o_offset    <= i_offset;
        o_byte_sel  <= byte_sel;
        o_data      <= i_data;
        o_valid     <= i_valid;
        o_dirty     <= i_dirty;
        o_fill      <= i_fill;
        o_fill_data <= i_fill_data;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_wr_en <= 1'b0;
        else        o_wr_en <= i_wr_en;
    end

endmodule
