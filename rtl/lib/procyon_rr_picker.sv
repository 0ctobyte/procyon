/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Round robin picker. Given a vector of requests, return a grant vector with only one bit set indicating the grant
// selection. The logic will pick a requestor using a priority scheme where the LSB of the request vector has the highest
// priority but will ensure that requestors with lower priority then the last granted requestor will be selected over
// the higher priority requestors. However, higher priority requestors will still be given grants as long as there no
// lower priority requestors asserting in the same cycle.

module procyon_rr_picker #(
    parameter OPTN_PICKER_DEPTH = 8
)(
    input  logic                         clk,
    input  logic                         n_rst,

    input  logic                         i_valid,
    input  logic [OPTN_PICKER_DEPTH-1:0] i_requests,
    output logic [OPTN_PICKER_DEPTH-1:0] o_grant
);

    // Keep track of the granted mask which is updated based off the last grant
    logic [OPTN_PICKER_DEPTH-1:0] grant_mask_r;

    // Priority arbiter to select the highest priority requestor
    logic [OPTN_PICKER_DEPTH-1:0] selected_unmasked;
    procyon_priority_picker #(OPTN_PICKER_DEPTH) selected_unmasked_priority_picker (.i_in(i_requests), .o_pick(selected_unmasked));

    // Mask out higher priority requestors based off of priority of the previous grant
    logic [OPTN_PICKER_DEPTH-1:0] requests_masked;
    assign requests_masked = i_requests & grant_mask_r;

    // Priority arbiter to select the next highest priority requestor excluding the ones not eligible this round
    logic [OPTN_PICKER_DEPTH-1:0] selected_masked;
    procyon_priority_picker #(OPTN_PICKER_DEPTH) selected_masked_priority_picker (.i_in(requests_masked), .o_pick(selected_masked));

    // Choose either the standard priority arbiter result if no lower priority requestors asserted this round
    logic [OPTN_PICKER_DEPTH-1:0] grant;
    assign grant = (selected_masked == 0) ? selected_unmasked : selected_masked;
    assign o_grant = grant;

    // Update the granted mask based off the grant for this round i.e. mask out requestors with same or higher priority for the next round
    logic [OPTN_PICKER_DEPTH-1:0] grant_mask;
    assign grant_mask = ~(grant | (grant - 1'b1));
    procyon_srff #(OPTN_PICKER_DEPTH) grant_mask_r_srff (.clk(clk), .n_rst(n_rst), .i_en(i_valid), .i_set(grant_mask), .i_reset('0), .o_q(grant_mask_r));

endmodule
