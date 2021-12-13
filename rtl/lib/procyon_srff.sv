/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// n-bit flip-flop with synchronous reset and enable

module procyon_srff #(
    parameter OPTN_DATA_WIDTH = 1
)(
    input  logic                       clk,
    input  logic                       n_rst,

    input  logic                       i_en,
    input  logic [OPTN_DATA_WIDTH-1:0] i_set,
    input  logic [OPTN_DATA_WIDTH-1:0] i_reset,
    output logic [OPTN_DATA_WIDTH-1:0] o_q
);

    always_ff @(posedge clk) begin
        if (!n_rst)    o_q <= i_reset;
        else if (i_en) o_q <= i_set;
    end

endmodule
