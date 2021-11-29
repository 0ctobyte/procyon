/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Instruction Cache
// There are two stages
// IT stage - Read out data/tag RAM and cache state
// IR stage - Generate hit signal and read data word

`include "procyon_constants.svh"

module procyon_icache #(
    parameter OPTN_INSN_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_IC_CACHE_SIZE = 1024,
    parameter OPTN_IC_LINE_SIZE  = 32,
    parameter OPTN_IC_WAY_COUNT  = 1,

    parameter IC_LINE_WIDTH      = OPTN_IC_LINE_SIZE * 8
)(
    input  logic                            clk,
    input  logic                            n_rst,

    input  logic                            i_ic_en,
/* verilator lint_off UNUSED */
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_ic_addr,
/* verilator lint_on  UNUSED */
    output logic                            o_ic_hit,
    output logic [OPTN_INSN_WIDTH-1:0]      o_ic_data,

    input  logic                            i_ic_fill_en,
/* verilator lint_off UNUSED */
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_ic_fill_addr,
/* verilator lint_on  UNUSED */
    input  logic [IC_LINE_WIDTH-1:0]        i_ic_fill_data
);

    localparam INSN_SIZE               = OPTN_INSN_WIDTH / 8;
    localparam INSN_SIZE_WIDTH         = $clog2(INSN_SIZE);
    localparam IC_OFFSET_WIDTH         = $clog2(OPTN_IC_LINE_SIZE);
    localparam IC_ALIGNED_OFFSET_WIDTH = IC_OFFSET_WIDTH - INSN_SIZE_WIDTH;
    localparam IC_INDEX_WIDTH          = OPTN_IC_CACHE_SIZE == OPTN_IC_LINE_SIZE ? 1 : $clog2(OPTN_IC_CACHE_SIZE / OPTN_IC_LINE_SIZE / OPTN_IC_WAY_COUNT);
    localparam IC_TAG_WIDTH            = OPTN_ADDR_WIDTH - (IC_INDEX_WIDTH == 1 ? 0 : IC_INDEX_WIDTH) - IC_OFFSET_WIDTH;

    // Crack open address into tag, index & offset
    logic [IC_TAG_WIDTH-1:0] ic_tag;
    logic [IC_INDEX_WIDTH-1:0] ic_index;
    logic [IC_OFFSET_WIDTH-1:INSN_SIZE_WIDTH] ic_offset;
    logic [IC_TAG_WIDTH-1:0] ic_fill_tag;
    logic [IC_INDEX_WIDTH-1:0] ic_fill_index;

    assign ic_tag = i_ic_addr[OPTN_ADDR_WIDTH-1:OPTN_ADDR_WIDTH-IC_TAG_WIDTH];
    assign ic_fill_tag = i_ic_fill_addr[OPTN_ADDR_WIDTH-1:OPTN_ADDR_WIDTH-IC_TAG_WIDTH];

    generate
    if (IC_INDEX_WIDTH == 1) begin
        assign ic_index = '0;
        assign ic_fill_index = '0;
    end
    else begin
        assign ic_index = i_ic_addr[IC_INDEX_WIDTH+IC_OFFSET_WIDTH-1:IC_OFFSET_WIDTH];
        assign ic_fill_index = i_ic_fill_addr[IC_INDEX_WIDTH+IC_OFFSET_WIDTH-1:IC_OFFSET_WIDTH];
    end
    endgenerate

    assign ic_offset = i_ic_addr[IC_OFFSET_WIDTH-1:INSN_SIZE_WIDTH];

    logic cache_rd_valid;
/* verilator lint_off UNUSED */
    logic cache_rd_dirty;
/* verilator lint_on  UNUSED */
    logic [IC_TAG_WIDTH-1:0] cache_rd_tag;
    logic [IC_LINE_WIDTH-1:0] cache_rd_data;

    procyon_cache #(
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_CACHE_SIZE(OPTN_IC_CACHE_SIZE),
        .OPTN_CACHE_LINE_SIZE(OPTN_IC_LINE_SIZE)
    ) procyon_instruction_cache_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_cache_wr_en(i_ic_fill_en),
        .i_cache_wr_index(ic_fill_index),
        .i_cache_wr_valid('1),
        .i_cache_wr_dirty('0),
        .i_cache_wr_tag(ic_fill_tag),
        .i_cache_wr_data(i_ic_fill_data),
        .i_cache_rd_en(i_ic_en),
        .i_cache_rd_index(ic_index),
        .o_cache_rd_valid(cache_rd_valid),
        .o_cache_rd_dirty(cache_rd_dirty),
        .o_cache_rd_tag(cache_rd_tag),
        .o_cache_rd_data(cache_rd_data)
    );

    // Pipeline register for IT -> IR stage
    logic [IC_TAG_WIDTH-1:0] ic_it_tag_r;
    logic [IC_OFFSET_WIDTH-1:INSN_SIZE_WIDTH] ic_it_offset_r;

    procyon_ff #(IC_TAG_WIDTH) ic_it_tag_r_ff (.clk(clk), .i_en(1'b1), .i_d(ic_tag), .o_q(ic_it_tag_r));
    procyon_ff #(IC_ALIGNED_OFFSET_WIDTH) ic_it_offset_r_ff (.clk(clk), .i_en(1'b1), .i_d(ic_offset), .o_q(ic_it_offset_r));

    // Generate cache hit and data
    logic ic_hit;
    assign ic_hit = (cache_rd_tag == ic_it_tag_r) & cache_rd_valid;

    procyon_srff #(1) o_ic_hit_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(ic_hit), .i_reset('0), .o_q(o_ic_hit));

    // Extract instruction bytes from cacheline. Instructions must be aligned to INSN_SIZE boundary and must be exactly
    // OPTN_INSN_WIDTH bits wide.
    logic [OPTN_INSN_WIDTH-1:0] insn_data;

    always_comb begin
        insn_data = '0;

        for (int i = 0; i < (IC_LINE_WIDTH / OPTN_INSN_WIDTH); i++) begin
            if (IC_ALIGNED_OFFSET_WIDTH'(i) == ic_it_offset_r) begin
                insn_data = cache_rd_data[i*OPTN_INSN_WIDTH +: OPTN_INSN_WIDTH];
            end
        end
    end

    procyon_ff #(OPTN_INSN_WIDTH) o_ic_data_ff (.clk(clk), .i_en(1'b1), .i_d(insn_data), .o_q(o_ic_data));

endmodule
