/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// n-bit, m-deep Synchronizer
// Synchronizes an asynchronous signal into the clock domain
// The synchronization depth, m, (i.e. the number of flops from input signal to output signal) can be adjusted

module procyon_sync #(
    parameter                       OPTN_DATA_WIDTH = 1,
    parameter                       OPTN_SYNC_DEPTH = 2,
    parameter [OPTN_DATA_WIDTH-1:0] OPTN_RESET_VAL  = 0
)(
    input  logic                  clk,
    input  logic                  n_rst,

    input  logic [OPTN_DATA_WIDTH-1:0] i_async_data,
    output logic [OPTN_DATA_WIDTH-1:0] o_sync_data
);

    // Synchronization flops
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [OPTN_DATA_WIDTH-1:0] sync_flops [0:OPTN_SYNC_DEPTH-1];

    // Capture the async signal
    procyon_srff #(OPTN_DATA_WIDTH) sync_flops_0_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(i_async_data), .i_reset(OPTN_RESET_VAL), .o_q(sync_flops[0]));

    // Every clock cycle, propagate the captured async signal through the synchronization pipeline
    genvar i;
    generate
    for (i = 1; i < OPTN_SYNC_DEPTH; i = i + 1) begin : GEN_SYNC_FLOPS_PROPAGATE
        procyon_srff #(OPTN_DATA_WIDTH) sync_flops_i_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(sync_flops[i-1]), .i_reset(OPTN_RESET_VAL), .o_q(sync_flops[i]));
    end
    endgenerate

    // The last stage of flops in the synchronization pipeline holds our synchronized signal
    assign o_sync_data = sync_flops[OPTN_SYNC_DEPTH-1];

endmodule
