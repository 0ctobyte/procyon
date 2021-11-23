/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Convert a binary number to a one-hot vector

module procyon_binary2onehot #(
    parameter OPTN_ONEHOT_WIDTH = 8,

    parameter BINARY_WIDTH      = OPTN_ONEHOT_WIDTH == 1 ? 1 : $clog2(OPTN_ONEHOT_WIDTH)
)(
    input  logic [BINARY_WIDTH-1:0]      i_binary,
    output logic [OPTN_ONEHOT_WIDTH-1:0] o_onehot
);

    logic [OPTN_ONEHOT_WIDTH-1:0] onehot;
    always_comb begin
        for (int i = 0; i < OPTN_ONEHOT_WIDTH; i++) begin
            onehot[i] = (BINARY_WIDTH'(i) == i_binary);
        end
    end

    assign o_onehot = onehot;

endmodule
