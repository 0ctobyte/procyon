// Data Cache - Data/Tag RAM read stage

`include "common.svh"
import procyon_types::*;

module dcache_d0 (
    input  logic                   clk,
    input  logic                   n_rst,

    input  logic                   i_wr_en,
    input  procyon_dc_tag_t        i_tag,
    input  procyon_dc_index_t      i_index,
    input  procyon_dc_offset_t     i_offset,
    input  procyon_lsu_func_t      i_lsu_func,
    input  procyon_data_t          i_data,
    input  logic                   i_valid,
    input  logic                   i_dirty,
    input  logic                   i_fill,
    input  procyon_cacheline_t     i_fill_data,

    output logic                   o_wr_en,
    output procyon_dc_tag_t        o_tag,
    output procyon_dc_index_t      o_index,
    output procyon_dc_offset_t     o_offset,
    output procyon_byte_select_t   o_byte_sel,
    output procyon_data_t          o_data,
    output logic                   o_valid,
    output logic                   o_dirty,
    output logic                   o_fill,
    output procyon_cacheline_t     o_fill_data
);

    procyon_byte_select_t          byte_sel;

    // Derive byte select signals from the LSU op type
    always_comb begin
        case (i_lsu_func)
            LSU_FUNC_LB:  byte_sel = {{(`WORD_SIZE-1){1'b0}}, 1'b1};
            LSU_FUNC_LH:  byte_sel = {{(`WORD_SIZE/2){1'b0}}, {(`WORD_SIZE/2){1'b1}}};
            LSU_FUNC_LBU: byte_sel = {{(`WORD_SIZE-1){1'b0}}, 1'b1};
            LSU_FUNC_LHU: byte_sel = {{(`WORD_SIZE/2){1'b0}}, {(`WORD_SIZE/2){1'b1}}};
            LSU_FUNC_SB:  byte_sel = {{(`WORD_SIZE-1){1'b0}}, 1'b1};
            LSU_FUNC_SH:  byte_sel = {{(`WORD_SIZE/2){1'b0}}, {(`WORD_SIZE/2){1'b1}}};
            default:      byte_sel = {(`WORD_SIZE){1'b1}};
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
