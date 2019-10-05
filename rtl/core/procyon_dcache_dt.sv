/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Data Cache - Data/Tag RAM read stage

`include "procyon_constants.svh"

module procyon_dcache_dt #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_DC_CACHE_SIZE = 1024,
    parameter OPTN_DC_LINE_SIZE  = 32,
    parameter OPTN_DC_WAY_COUNT  = 1,

    parameter DC_LINE_WIDTH      = OPTN_DC_LINE_SIZE * 8,
    parameter DC_OFFSET_WIDTH    = $clog2(OPTN_DC_LINE_SIZE),
    parameter DC_INDEX_WIDTH     = $clog2(OPTN_DC_CACHE_SIZE / OPTN_DC_LINE_SIZE / OPTN_DC_WAY_COUNT),
    parameter DC_TAG_WIDTH       = OPTN_ADDR_WIDTH - DC_INDEX_WIDTH - DC_OFFSET_WIDTH,
    parameter DATA_SIZE          = OPTN_DATA_WIDTH / 8
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
    output logic [DATA_SIZE-1:0]            o_byte_sel,
    output logic [OPTN_DATA_WIDTH-1:0]      o_data,
    output logic                            o_valid,
    output logic                            o_dirty,
    output logic                            o_fill,
    output logic [DC_LINE_WIDTH-1:0]        o_fill_data
);

    procyon_srff #(1) o_wr_en_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(i_wr_en), .i_reset(1'b0), .o_q(o_wr_en));
    procyon_ff #(DC_TAG_WIDTH) o_tag_ff (.clk(clk), .i_en(1'b1), .i_d(i_tag), .o_q(o_tag));
    procyon_ff #(DC_INDEX_WIDTH) o_index_ff (.clk(clk), .i_en(1'b1), .i_d(i_index), .o_q(o_index));
    procyon_ff #(DC_OFFSET_WIDTH) o_offset_ff (.clk(clk), .i_en(1'b1), .i_d(i_offset), .o_q(o_offset));
    procyon_ff #(OPTN_DATA_WIDTH) o_data_ff (.clk(clk), .i_en(1'b1), .i_d(i_data), .o_q(o_data));
    procyon_ff #(1) o_valid_ff (.clk(clk), .i_en(1'b1), .i_d(i_valid), .o_q(o_valid));
    procyon_ff #(1) o_dirty_ff (.clk(clk), .i_en(1'b1), .i_d(i_dirty), .o_q(o_dirty));
    procyon_ff #(1) o_fill_ff (.clk(clk), .i_en(1'b1), .i_d(i_fill), .o_q(o_fill));
    procyon_ff #(DC_LINE_WIDTH) o_fill_data_ff (.clk(clk), .i_en(1'b1), .i_d(i_fill_data), .o_q(o_fill_data));

    logic [DATA_SIZE-1:0] byte_sel;

    // Derive byte select signals from the LSU op type
    always_comb begin
        case (i_lsu_func)
            `PCYN_LSU_FUNC_LB:  byte_sel = {{(DATA_SIZE-1){1'b0}}, 1'b1};
            `PCYN_LSU_FUNC_LH:  byte_sel = {{(DATA_SIZE/2){1'b0}}, {(DATA_SIZE/2){1'b1}}};
            `PCYN_LSU_FUNC_LBU: byte_sel = {{(DATA_SIZE-1){1'b0}}, 1'b1};
            `PCYN_LSU_FUNC_LHU: byte_sel = {{(DATA_SIZE/2){1'b0}}, {(DATA_SIZE/2){1'b1}}};
            `PCYN_LSU_FUNC_SB:  byte_sel = {{(DATA_SIZE-1){1'b0}}, 1'b1};
            `PCYN_LSU_FUNC_SH:  byte_sel = {{(DATA_SIZE/2){1'b0}}, {(DATA_SIZE/2){1'b1}}};
            default:            byte_sel = '1;
        endcase
    end

    procyon_ff #(DATA_SIZE) o_byte_sel_ff (.clk(clk), .i_en(1'b1), .i_d(byte_sel), .o_q(o_byte_sel));

endmodule
