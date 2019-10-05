/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Posedge/Negedge Detector
// Use a synchronizer because the edge is most likely asynchronous
// Posedge detection is easy, the nth flop in the delay line LOW and the n-1 flop is HIGH
// Similarly for negedge detection, the nth flop is HIGH an the n-1 flop is LOW

module procyon_edge_detector #(
    parameter OPTN_EDGE = 1  // Default "1" == detect posedge
)(
    input  logic clk,
    input  logic n_rst,

    input  logic i_async,
    output logic o_pulse
);

    // Last two flops in the synchronization pipeline
    logic pulse1;
    logic pulse0;

    procyon_sync #(.OPTN_DATA_WIDTH(1), .OPTN_SYNC_DEPTH(2)) pulse0_sync (.clk(clk), .n_rst(n_rst), .i_async_data(i_async), .o_sync_data(pulse0));
    procyon_srff #(1) pulse1_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(pulse0), .i_reset(1'b0), .o_q(pulse1));

    // Edge detection logic
    generate
    if (!OPTN_EDGE) assign o_pulse = pulse1 & ~pulse0;
    else            assign o_pulse = ~pulse1 & pulse0;
    endgenerate

endmodule
