/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

module procyon_vq_entry #(
    parameter OPTN_ADDR_WIDTH   = 32,
    parameter OPTN_DC_LINE_SIZE = 32,

    parameter DC_LINE_WIDTH     = OPTN_DC_LINE_SIZE * 8,
    parameter DC_OFFSET_WIDTH   = $clog2(OPTN_DC_LINE_SIZE)
)(
    input  logic                                      clk,
    input  logic                                      n_rst,

    output logic                                      o_vq_entry_valid,
    output logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH]  o_vq_entry_addr,
    output logic [DC_LINE_WIDTH-1:0]                  o_vq_entry_data,

    // LSU lookup interface, check for address match
    input  logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH]  i_lookup_addr,
    output logic                                      o_lookup_hit,

    // Allocate to this entry
    input  logic                                      i_alloc_en,
    input  logic [DC_LINE_WIDTH-1:0]                  i_alloc_data,
    input  logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH]  i_alloc_addr,

    // CCU interface
    input  logic                                      i_ccu_done
);

    // Each entry in the VQ can be in one of the following states
    // INVALID:       Entry is empty
    // VALID:         Entry is occupied
    localparam VQ_STATE_WIDTH    = 1;
    localparam VQ_STATE_INVALID  = 1'b0;
    localparam VQ_STATE_VALID    = 1'b1;

    // Each entry in the VQ contains the following
    // state:          State of the VQ entry
    // addr:           Address of the victimized cacheline
    // data:           The actual cacheline data
    logic [VQ_STATE_WIDTH-1:0] vq_entry_state_r;
    logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] vq_entry_addr_r;
    logic [DC_LINE_WIDTH-1:0] vq_entry_data_r;

    // VQ entry FSM
    logic [VQ_STATE_WIDTH-1:0] vq_entry_state_next;

    always_comb begin
        vq_entry_state_next = vq_entry_state_r;

        case (vq_entry_state_next)
            VQ_STATE_INVALID: vq_entry_state_next = i_alloc_en ? VQ_STATE_VALID : vq_entry_state_next;
            VQ_STATE_VALID:   vq_entry_state_next = i_ccu_done ? VQ_STATE_INVALID : vq_entry_state_next;
            default:          vq_entry_state_next = VQ_STATE_INVALID;
        endcase
    end

    procyon_srff #(VQ_STATE_WIDTH) vq_entry_state_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(vq_entry_state_next), .i_reset(VQ_STATE_INVALID), .o_q(vq_entry_state_r));
    procyon_ff #(OPTN_ADDR_WIDTH-DC_OFFSET_WIDTH) vq_entry_addr_r_ff (.clk(clk), .i_en(i_alloc_en), .i_d(i_alloc_addr), .o_q(vq_entry_addr_r));
    procyon_ff #(DC_LINE_WIDTH) vq_entry_data_r_ff (.clk(clk), .i_en(i_alloc_en), .i_d(i_alloc_data), .o_q(vq_entry_data_r));

    // Check if the lookup address matches this entry's address
    logic vq_entry_valid;
    assign vq_entry_valid = (vq_entry_state_r != VQ_STATE_INVALID);
    assign o_lookup_hit = vq_entry_valid & (vq_entry_addr_r == i_lookup_addr);

    // Output entry registers
    assign o_vq_entry_valid = vq_entry_valid;
    assign o_vq_entry_addr = vq_entry_addr_r;
    assign o_vq_entry_data = vq_entry_data_r;

endmodule
