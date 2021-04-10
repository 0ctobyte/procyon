/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Priority encoder; given an array of bits, return the same width array with only one of the bits set
// Bit 0 is assumed the highest priority with each MSB decreasing in priority

module procyon_priority_picker #(
    parameter OPTN_PICKER_DEPTH = 8
)(
    input  logic [OPTN_PICKER_DEPTH-1:0] i_in,
    output logic [OPTN_PICKER_DEPTH-1:0] o_pick
);

    assign o_pick = i_in & ~(i_in - 1'b1);

endmodule
