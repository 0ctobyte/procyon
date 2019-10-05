/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// n-bit flip-flop with enable

module procyon_ff #(
    parameter OPTN_DATA_WIDTH = 1
)(
    input  logic                       clk,

    input  logic                       i_en,
    input  logic [OPTN_DATA_WIDTH-1:0] i_d,
    output logic [OPTN_DATA_WIDTH-1:0] o_q
);

    always_ff @(posedge clk) if (i_en) o_q <= i_d;

endmodule
