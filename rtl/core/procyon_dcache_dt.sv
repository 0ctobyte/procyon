/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Data Cache - Data/Tag RAM read stage

module procyon_dcache_dt
    import procyon_lib_pkg::*, procyon_core_pkg::*;
#(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_DC_CACHE_SIZE = 1024,
    parameter OPTN_DC_LINE_SIZE  = 32,
    parameter OPTN_DC_WAY_COUNT  = 1
)(
    input  logic                                    clk,
    input  logic                                    n_rst,

    input  logic                                    i_wr_en,
    input  logic [`PCYN_DC_TAG_WIDTH-1:0]           i_tag,
    input  logic [`PCYN_DC_INDEX_WIDTH-1:0]         i_index,
    input  logic [`PCYN_DC_OFFSET_WIDTH-1:0]        i_offset,
    input  pcyn_op_t                                i_op,
    input  logic [OPTN_DATA_WIDTH-1:0]              i_data,
    input  logic                                    i_valid,
    input  logic                                    i_dirty,
    input  logic                                    i_fill,
    input  logic [`PCYN_S2W(OPTN_DC_LINE_SIZE)-1:0] i_fill_data,

    output logic                                    o_wr_en,
    output logic [`PCYN_DC_TAG_WIDTH-1:0]           o_tag,
    output logic [`PCYN_DC_INDEX_WIDTH-1:0]         o_index,
    output logic [`PCYN_DC_OFFSET_WIDTH-1:0]        o_offset,
    output logic [`PCYN_W2S(OPTN_DATA_WIDTH)-1:0]   o_byte_sel,
    output logic [OPTN_DATA_WIDTH-1:0]              o_data,
    output logic                                    o_valid,
    output logic                                    o_dirty,
    output logic                                    o_fill,
    output logic [`PCYN_S2W(OPTN_DC_LINE_SIZE)-1:0] o_fill_data
);

    localparam DC_LINE_WIDTH = `PCYN_S2W(OPTN_DC_LINE_SIZE);
    localparam DATA_SIZE = `PCYN_W2S(OPTN_DATA_WIDTH);

    procyon_srff #(1) o_wr_en_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(i_wr_en), .i_reset(1'b0), .o_q(o_wr_en));
    procyon_ff #(`PCYN_DC_TAG_WIDTH) o_tag_ff (.clk(clk), .i_en(1'b1), .i_d(i_tag), .o_q(o_tag));
    procyon_ff #(`PCYN_DC_INDEX_WIDTH) o_index_ff (.clk(clk), .i_en(1'b1), .i_d(i_index), .o_q(o_index));
    procyon_ff #(`PCYN_DC_OFFSET_WIDTH) o_offset_ff (.clk(clk), .i_en(1'b1), .i_d(i_offset), .o_q(o_offset));
    procyon_ff #(OPTN_DATA_WIDTH) o_data_ff (.clk(clk), .i_en(1'b1), .i_d(i_data), .o_q(o_data));
    procyon_ff #(1) o_valid_ff (.clk(clk), .i_en(1'b1), .i_d(i_valid), .o_q(o_valid));
    procyon_ff #(1) o_dirty_ff (.clk(clk), .i_en(1'b1), .i_d(i_dirty), .o_q(o_dirty));
    procyon_ff #(1) o_fill_ff (.clk(clk), .i_en(1'b1), .i_d(i_fill), .o_q(o_fill));
    procyon_ff #(DC_LINE_WIDTH) o_fill_data_ff (.clk(clk), .i_en(1'b1), .i_d(i_fill_data), .o_q(o_fill_data));

    logic [DATA_SIZE-1:0] byte_sel;

    // Derive byte select signals from the LSU op type
    always_comb begin
        unique case (i_op)
            PCYN_OP_LB:  byte_sel = {{(DATA_SIZE-1){1'b0}}, 1'b1};
            PCYN_OP_LH:  byte_sel = {{(DATA_SIZE/2){1'b0}}, {(DATA_SIZE/2){1'b1}}};
            PCYN_OP_LBU: byte_sel = {{(DATA_SIZE-1){1'b0}}, 1'b1};
            PCYN_OP_LHU: byte_sel = {{(DATA_SIZE/2){1'b0}}, {(DATA_SIZE/2){1'b1}}};
            PCYN_OP_SB:  byte_sel = {{(DATA_SIZE-1){1'b0}}, 1'b1};
            PCYN_OP_SH:  byte_sel = {{(DATA_SIZE/2){1'b0}}, {(DATA_SIZE/2){1'b1}}};
            default:     byte_sel = '1;
        endcase
    end

    procyon_ff #(DATA_SIZE) o_byte_sel_ff (.clk(clk), .i_en(1'b1), .i_d(byte_sel), .o_q(o_byte_sel));

endmodule
