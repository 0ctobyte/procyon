/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Convert a one-hot vector into a binary number corresponding to the bit position of the one-hot bit

module procyon_onehot2binary #(
    parameter OPTN_ONEHOT_WIDTH = 8,

    parameter BINARY_WIDTH      = OPTN_ONEHOT_WIDTH == 1 ? 1 : $clog2(OPTN_ONEHOT_WIDTH)
)(
    input  logic [OPTN_ONEHOT_WIDTH-1:0] i_onehot,
    output logic [BINARY_WIDTH-1:0]      o_binary
);

    logic [BINARY_WIDTH-1:0] binary;
    always_comb begin
        binary = '0;
        for (int i = 0; i < OPTN_ONEHOT_WIDTH; i++) begin
            if (i_onehot[i]) binary = BINARY_WIDTH'(i);
        end
    end

    assign o_binary = binary;

endmodule
