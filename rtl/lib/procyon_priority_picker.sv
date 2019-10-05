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

    genvar i;
    generate
    if (OPTN_PICKER_DEPTH == 1) begin
        assign o_pick = i_in;
    end else begin
        // bit 0 gets highest priority
        assign o_pick[0] = i_in[0];

        // For each bit after, generate a 1 if it is set and all LSBs are zero
        for (i = 1; i < OPTN_PICKER_DEPTH; i++) begin : GEN_PICKER_SIGNALS
            assign o_pick[i] = i_in[i] & ~(|i_in[i-1:0]);
        end
    end
    endgenerate

endmodule
