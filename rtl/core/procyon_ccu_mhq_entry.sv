/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

module procyon_ccu_mhq_entry
    import procyon_lib_pkg::*, procyon_core_pkg::*;
#(
    parameter OPTN_ADDR_WIDTH   = 32,
    parameter OPTN_DC_LINE_SIZE = 32
)(
    input  logic                                           clk,
    input  logic                                           n_rst,

    output logic                                           o_mhq_entry_valid,
    output logic                                           o_mhq_entry_complete,
    output logic                                           o_mhq_entry_dirty,
    output logic [OPTN_ADDR_WIDTH-1:`PCYN_DC_OFFSET_WIDTH] o_mhq_entry_addr,
    output logic [`PCYN_S2W(OPTN_DC_LINE_SIZE)-1:0]        o_mhq_entry_data,

    // LSU lookup interface, check for address match
    input  logic [OPTN_ADDR_WIDTH-1:`PCYN_DC_OFFSET_WIDTH] i_lookup_addr,
    output logic                                           o_lookup_hit,

    // Allocate or merge to this entry
    input  logic                                           i_update_en,
    input  logic                                           i_update_we,
    input  logic [`PCYN_S2W(OPTN_DC_LINE_SIZE)-1:0]        i_update_wr_data,
    input  logic [OPTN_DC_LINE_SIZE-1:0]                   i_update_byte_select,
    input  logic [OPTN_ADDR_WIDTH-1:`PCYN_DC_OFFSET_WIDTH] i_update_addr,

    // CCU interface
    input  logic                                           i_ccu_done,
    input  logic [`PCYN_S2W(OPTN_DC_LINE_SIZE)-1:0]        i_ccu_data,

    // Indicates that this entry has been sent to LSU to fill the DCache
    input  logic                                           i_fill_launched
);

    localparam DC_LINE_WIDTH = `PCYN_S2W(OPTN_DC_LINE_SIZE);
    localparam MHQ_ENTRY_STATE_WIDTH = 2;

    // Each entry in the MHQ can be in one of the following states
    // INVALID:       Entry is empty
    // VALID:         Entry is occupied
    // COMPLETE:      Entry is finished being serviced by CCU and is ready to be sent to the LSU to fill the cache
    typedef enum logic [MHQ_ENTRY_STATE_WIDTH-1:0] {
        MHQ_ENTRY_STATE_INVALID  = MHQ_ENTRY_STATE_WIDTH'('b00),
        MHQ_ENTRY_STATE_VALID    = MHQ_ENTRY_STATE_WIDTH'('b01),
        MHQ_ENTRY_STATE_COMPLETE = MHQ_ENTRY_STATE_WIDTH'('b10)
    } mhq_entry_state_t;

    // Each entry in the MHQ contains the following
    // state:          State of the MHQ entry
    // dirty:          Indicates if a store has written data to this entry. This is passed along to the DCache.
    // addr:           A cacheline address indicating which address this entry is servicing
    // data:           The actual cacheline data
    // byte_updated:   Each bit, if set to 1, indicates that byte has been written to by a store. This is used to select
    //                 between data from memory and updated store data stored in the data register.
    mhq_entry_state_t mhq_entry_state_r;
    logic mhq_entry_dirty_r;
    logic [OPTN_ADDR_WIDTH-1:`PCYN_DC_OFFSET_WIDTH] mhq_entry_addr_r;
    logic [DC_LINE_WIDTH-1:0] mhq_entry_data_r;
    logic [OPTN_DC_LINE_SIZE-1:0] mhq_entry_byte_updated_r;

    // MHQ entry FSM
    mhq_entry_state_t mhq_entry_state_next;

    always_comb begin
        mhq_entry_state_next = mhq_entry_state_r;

        unique case (mhq_entry_state_next)
            MHQ_ENTRY_STATE_INVALID:  mhq_entry_state_next = i_update_en ? MHQ_ENTRY_STATE_VALID : mhq_entry_state_next;
            MHQ_ENTRY_STATE_VALID:    mhq_entry_state_next = i_ccu_done ? MHQ_ENTRY_STATE_COMPLETE : mhq_entry_state_next;
            MHQ_ENTRY_STATE_COMPLETE: mhq_entry_state_next = i_fill_launched ? MHQ_ENTRY_STATE_INVALID : mhq_entry_state_next;
            default:                  mhq_entry_state_next = MHQ_ENTRY_STATE_INVALID;
        endcase
    end

    procyon_srff #(MHQ_ENTRY_STATE_WIDTH) mhq_entry_state_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(mhq_entry_state_next), .i_reset(MHQ_ENTRY_STATE_INVALID), .o_q(mhq_entry_state_r));

    // This entry is a new allocation if the entry was not previously valid. Otherwise it's being merged with another request
    logic allocating;
    assign allocating = i_update_en & (mhq_entry_state_r == MHQ_ENTRY_STATE_INVALID);

    // Set dirty bit for entry if it's being written too. Clear it if it's a newly allocated entry and not being written to
    logic mhq_entry_dirty;
    assign mhq_entry_dirty = i_update_we | (~allocating & mhq_entry_dirty_r);
    procyon_ff #(1) mhq_entry_dirty_r_ff (.clk(clk), .i_en(i_update_en), .i_d(mhq_entry_dirty), .o_q(mhq_entry_dirty_r));

    procyon_ff #(OPTN_ADDR_WIDTH-`PCYN_DC_OFFSET_WIDTH) mhq_entry_addr_r_ff (.clk(clk), .i_en(allocating), .i_d(i_update_addr), .o_q(mhq_entry_addr_r));

    // Update data and byte_updated merging data from a store or from the CCU or both
    logic [DC_LINE_WIDTH-1:0] mhq_entry_data_mux;
    logic [OPTN_DC_LINE_SIZE-1:0] mhq_entry_byte_updated_mux;
    logic update_we;

    assign update_we = i_update_en & i_update_we;

    always_comb begin
        mhq_entry_data_mux = mhq_entry_data_r;
        mhq_entry_byte_updated_mux = allocating ? '0 : mhq_entry_byte_updated_r;

        for (int i = 0; i < OPTN_DC_LINE_SIZE; i++) begin
            logic update_byte;
            update_byte = update_we & i_update_byte_select[i];

            // Merge store data into miss queue entry and update the byte_updated field
            mhq_entry_data_mux[i*8 +: 8] = update_byte ? i_update_wr_data[i*8 +: 8] : mhq_entry_data_mux[i*8 +: 8];
            mhq_entry_byte_updated_mux[i]  = update_byte | mhq_entry_byte_updated_mux[i];

            // If the CCU is finished receiving data on the same cycle as a store, then merge all the bytes from the CCU
            // Don't overwrite bytes that have been updated by stores to this entry
            mhq_entry_data_mux[i*8 +: 8] = (~i_ccu_done | mhq_entry_byte_updated_mux[i]) ? mhq_entry_data_mux[i*8 +: 8] : i_ccu_data[i*8 +: 8];
        end
    end

    procyon_ff #(DC_LINE_WIDTH) mhq_entry_data_r_ff (.clk(clk), .i_en(1'b1), .i_d(mhq_entry_data_mux), .o_q(mhq_entry_data_r));
    procyon_ff #(OPTN_DC_LINE_SIZE) mhq_entry_byte_updated_r_ff (.clk(clk), .i_en(1'b1), .i_d(mhq_entry_byte_updated_mux), .o_q(mhq_entry_byte_updated_r));

    // Check if the lookup address matches this entry's address
    logic mhq_entry_valid;
    assign mhq_entry_valid = (mhq_entry_state_r != MHQ_ENTRY_STATE_INVALID);
    assign o_lookup_hit = mhq_entry_valid & (mhq_entry_addr_r == i_lookup_addr);

    // Output entry registers. De-assert the entry_complete signal if the entry is currently being written too by a
    // retiring store otherwise the fill request sent to the DCache will have outdated data.
    assign o_mhq_entry_valid = mhq_entry_valid;
    assign o_mhq_entry_complete = (mhq_entry_state_r == MHQ_ENTRY_STATE_COMPLETE) & ~update_we;
    assign o_mhq_entry_dirty = mhq_entry_dirty_r;
    assign o_mhq_entry_addr = mhq_entry_addr_r;
    assign o_mhq_entry_data = mhq_entry_data_r;

endmodule
