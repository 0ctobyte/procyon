/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// MHQ lookup stage
// Lookup MHQ for address matches and generate byte select signals depending on store type

`include "procyon_constants.svh"

module procyon_mhq_lu #(
    parameter OPTN_DATA_WIDTH   = 32,
    parameter OPTN_ADDR_WIDTH   = 32,
    parameter OPTN_MHQ_DEPTH    = 4,
    parameter OPTN_DC_LINE_SIZE = 32,

    parameter MHQ_IDX_WIDTH     = OPTN_MHQ_DEPTH == 1 ? 1 : $clog2(OPTN_MHQ_DEPTH),
    parameter DC_LINE_WIDTH     = OPTN_DC_LINE_SIZE * 8,
    parameter DC_OFFSET_WIDTH   = $clog2(OPTN_DC_LINE_SIZE)
)(
    input  logic                                     clk,
    input  logic                                     n_rst,

    input  logic                                     i_mhq_full,

    // Forward address and tag information from currently updating MHQ entry
    input  logic [OPTN_MHQ_DEPTH-1:0]                i_mhq_update_bypass_select,
    input  logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] i_mhq_update_bypass_addr,

    // Lookup interface from LSU
    input  logic                                     i_mhq_lookup_valid,
    input  logic                                     i_mhq_lookup_we,
    input  logic                                     i_mhq_lookup_dc_hit,
    input  logic [OPTN_ADDR_WIDTH-1:0]               i_mhq_lookup_addr,
    input  logic [`PCYN_OP_WIDTH-1:0]                i_mhq_lookup_op,
    input  logic [OPTN_DATA_WIDTH-1:0]               i_mhq_lookup_data,
    input  logic [OPTN_MHQ_DEPTH-1:0]                i_mhq_lookup_entry_hit_select,
    input  logic [OPTN_MHQ_DEPTH-1:0]                i_mhq_lookup_entry_alloc_select,
    output logic [MHQ_IDX_WIDTH-1:0]                 o_mhq_lookup_tag,
    output logic                                     o_mhq_lookup_retry,
    output logic                                     o_mhq_lookup_replay,
    output logic                                     o_mhq_lookup_allocating,

    // Outputs to next stage where an entry will get updated
    output logic [OPTN_MHQ_DEPTH-1:0]                o_mhq_update_select,
    output logic                                     o_mhq_update_we,
    output logic [DC_LINE_WIDTH-1:0]                 o_mhq_update_wr_data,
    output logic [OPTN_DC_LINE_SIZE-1:0]             o_mhq_update_byte_select,
    output logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] o_mhq_update_addr,

    // MHQ interface to check for fill conflicts
    input  logic                                     i_ccu_done,
    input  logic                                     i_mhq_completing,
    input  logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] i_mhq_completing_addr,
    input  logic                                     i_mhq_filling,
    input  logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] i_mhq_filling_addr
);

    localparam DATA_SIZE = OPTN_DATA_WIDTH / 8;

    logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] mhq_lookup_addr;
    assign mhq_lookup_addr = i_mhq_lookup_addr[OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH];

    logic mhq_lookup_entry_hit;
    logic mhq_update_bypass_hit;

    assign mhq_lookup_entry_hit = (i_mhq_lookup_entry_hit_select != 0);
    assign mhq_update_bypass_hit = (i_mhq_update_bypass_select != 0) & (i_mhq_update_bypass_addr == mhq_lookup_addr);

    // Find an MHQ entry (i.e. mhq_lookup_tag) with a matching address to the i_mhq_lookup_addr from the LSU
    // Check the bypassed address as well for the currently updating entry. If none can be found, then use the tail
    // entry of the MHQ to allocate a new entry
    logic [OPTN_MHQ_DEPTH-1:0] mhq_lookup_select_mux;

    always_comb begin
        logic [1:0] mhq_lookup_select_mux_sel;
        mhq_lookup_select_mux_sel = {mhq_update_bypass_hit, mhq_lookup_entry_hit};

        case (mhq_lookup_select_mux_sel)
            2'b00: mhq_lookup_select_mux = i_mhq_lookup_entry_alloc_select;
            2'b01: mhq_lookup_select_mux = i_mhq_lookup_entry_hit_select;
            2'b10: mhq_lookup_select_mux = i_mhq_update_bypass_select;
            2'b11: mhq_lookup_select_mux = i_mhq_update_bypass_select;
        endcase
    end

    // Convert one-hot mhq_lookup_select vector into binary MHQ entry #
    logic [MHQ_IDX_WIDTH-1:0] mhq_lookup_entry;
    procyon_onehot2binary #(OPTN_MHQ_DEPTH) mhq_lookup_entry_onehot2binary (.i_onehot(mhq_lookup_select_mux), .o_binary(mhq_lookup_entry));
    procyon_ff #(MHQ_IDX_WIDTH) o_mhq_lookup_tag_ff (.clk(clk), .i_en(1'b1), .i_d(mhq_lookup_entry), .o_q(o_mhq_lookup_tag));

    // Did we get a hit on an address in any of the MHQ entries (including bypass from current entry update)?
    logic mhq_lookup_hit;
    logic n_mhq_lookup_hit;

    assign mhq_lookup_hit = i_mhq_lookup_valid & (mhq_lookup_entry_hit | mhq_update_bypass_hit);
    assign n_mhq_lookup_hit = ~mhq_lookup_hit;

    // mhq_lookup_retry is asserted if the MHQ is full and there was no lookup hit
    logic mhq_lookup_retry;
    assign mhq_lookup_retry = i_mhq_full & n_mhq_lookup_hit;
    procyon_ff #(1) o_mhq_lookup_retry_ff (.clk(clk), .i_en(1'b1), .i_d(mhq_lookup_retry), .o_q(o_mhq_lookup_retry));

    // mhq_lookup_replay is asserted if the CCU signals it is done on the same cycle with the same address as the
    // lookup OR if the MHQ signals that it is about to launch a fill to the LSU on the same cycle with the same
    // address as the lookup OR if the MHQ has launched the fill to the LSU on the same cycle as this lookup with the 
    // same address (fill data is propagated through three cycles, the first coming from the CCU and the second
    // from the MHQ head entry and then to the LSU on the 3rd cycle). The same cycle fill case causes a fill
    // conflict where the lookup will return an MHQ tag and enqueue on that entry when it should be invalidated by the
    // current fill
    logic mhq_lookup_replay;
    assign mhq_lookup_replay = ((i_ccu_done | i_mhq_completing) & (i_mhq_completing_addr == mhq_lookup_addr)) | (i_mhq_filling & (i_mhq_filling_addr == mhq_lookup_addr));
    procyon_ff #(1) o_mhq_lookup_replay_ff (.clk(clk), .i_en(1'b1), .i_d(mhq_lookup_replay), .o_q(o_mhq_lookup_replay));

    // Determine if an entry needs to be updated/allocated
    logic mhq_update_en;
    assign mhq_update_en = i_mhq_lookup_valid & ~i_mhq_lookup_dc_hit & (i_mhq_lookup_op != `PCYN_OP_FILL) & ~mhq_lookup_retry & ~mhq_lookup_replay;
    assign o_mhq_lookup_allocating = mhq_update_en & n_mhq_lookup_hit;

    // Update enable bits for each entry. Only 1 bit should be set or 0 if no update is to take place
    logic [OPTN_MHQ_DEPTH-1:0] mhq_update_select;
    assign mhq_update_select = mhq_update_en ? mhq_lookup_select_mux : '0;
    procyon_srff #(OPTN_MHQ_DEPTH) o_mhq_update_select_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(mhq_update_select), .i_reset('0), .o_q(o_mhq_update_select));

    procyon_ff #(1) o_mhq_update_we_ff (.clk(clk), .i_en(1'b1), .i_d(i_mhq_lookup_we), .o_q(o_mhq_update_we));

    // Get the offset in bytes into the cacheline where the store will write data too
    logic [DC_OFFSET_WIDTH-1:0] mhq_lookup_offset;
    assign mhq_lookup_offset = i_mhq_lookup_addr[DC_OFFSET_WIDTH-1:0];

    // Generate byte select signals based on store type
    logic [OPTN_DC_LINE_SIZE-1:0] mhq_update_byte_select;

    always_comb begin
        case (i_mhq_lookup_op)
            `PCYN_OP_SB: mhq_update_byte_select = OPTN_DC_LINE_SIZE'({{(DATA_SIZE-1){1'b0}}, 1'b1});
            `PCYN_OP_SH: mhq_update_byte_select = OPTN_DC_LINE_SIZE'({{(DATA_SIZE/2){1'b0}}, {(DATA_SIZE/2){1'b1}}});
            `PCYN_OP_SW: mhq_update_byte_select = OPTN_DC_LINE_SIZE'({(DATA_SIZE){1'b1}});
            default:     mhq_update_byte_select = '0;
        endcase

        mhq_update_byte_select = mhq_update_byte_select << mhq_lookup_offset;
    end

    procyon_ff #(OPTN_DC_LINE_SIZE) o_mhq_update_byte_select_ff (.clk(clk), .i_en(1'b1), .i_d(mhq_update_byte_select), .o_q(o_mhq_update_byte_select));

    // Shift write data to correct offset in cacheline masking off writes to certain bytes according to the byte select
    logic [DC_LINE_WIDTH-1:0] mhq_update_wr_data;

    always_comb begin
        mhq_update_wr_data = '0;

        for (int i = 0; i < (OPTN_DC_LINE_SIZE-DATA_SIZE); i++) begin
            if (DC_OFFSET_WIDTH'(i) == mhq_lookup_offset) begin
                for (int j = 0; j < DATA_SIZE; j++) begin
                    mhq_update_wr_data[(i+j)*8 +: 8] = i_mhq_lookup_data[j*8 +: 8];
                end
            end
        end

        // Accessing bytes at the end of the line is tricky. We can't read or write past the end of the data line
        // So special case the writes to the last DATA_SIZE portion of the line by only writing to the number of bytes
        // remaining in the line rather than the whole DATA_SIZE data
        for (int i = (OPTN_DC_LINE_SIZE-DATA_SIZE); i < OPTN_DC_LINE_SIZE; i++) begin
            if (DC_OFFSET_WIDTH'(i) == mhq_lookup_offset) begin
                for (int j = 0; j < (OPTN_DC_LINE_SIZE-i); j++) begin
                    mhq_update_wr_data[(i+j)*8 +: 8] = i_mhq_lookup_data[j*8 +: 8];
                end
            end
        end
    end

    procyon_ff #(DC_LINE_WIDTH) o_mhq_update_wr_data_ff (.clk(clk), .i_en(1'b1), .i_d(mhq_update_wr_data), .o_q(o_mhq_update_wr_data));
    procyon_ff #(OPTN_ADDR_WIDTH-DC_OFFSET_WIDTH) o_mhq_update_addr_ff (.clk(clk), .i_en(1'b1), .i_d(mhq_lookup_addr), .o_q(o_mhq_update_addr));

endmodule
