/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Generic queue control module to keep track of full/empty status and manage head/tail pointers

module procyon_queue_ctrl #(
    parameter OPTN_QUEUE_DEPTH = 8,

    parameter QUEUE_IDX_WIDTH  = $clog2(OPTN_QUEUE_DEPTH)
)(
    input  logic                 clk,
    input  logic                 n_rst,

    input  logic                 i_flush,

    // Queue control signals to indicate when the head and tail pointers should be incremented
    input  logic                 i_incr_head,
    input  logic                 i_incr_tail,

    // Output queue head and tail pointers and full and empty signals
    output [QUEUE_IDX_WIDTH-1:0] o_queue_head,
    output [QUEUE_IDX_WIDTH-1:0] o_queue_tail,
    output                       o_queue_full,
    output                       o_queue_empty
);

    localparam QUEUE_COUNTER_WIDTH = $clog2(OPTN_QUEUE_DEPTH+1);

    logic [QUEUE_IDX_WIDTH-1:0] queue_head_r;
    logic [QUEUE_IDX_WIDTH-1:0] queue_tail_r;
    logic queue_full_r;
    logic queue_empty_r;

    // Increment head and tail pointers according to control signals i_incr_head and i_incr_tail
    logic [QUEUE_IDX_WIDTH-1:0] queue_head_next;
    logic [QUEUE_IDX_WIDTH-1:0] queue_tail_next;

    always_comb begin
        // If i_flush is asserted force the pointers to 0
        queue_head_next = i_flush ? '0 : queue_head_r + (QUEUE_IDX_WIDTH)'(i_incr_head);
        queue_tail_next = i_flush ? '0 : queue_tail_r + (QUEUE_IDX_WIDTH)'(i_incr_tail);

        // Handle wrap around case
        queue_head_next = (queue_head_next == (QUEUE_IDX_WIDTH)'(OPTN_QUEUE_DEPTH)) ? '0 : queue_head_next;
        queue_tail_next = (queue_tail_next == (QUEUE_IDX_WIDTH)'(OPTN_QUEUE_DEPTH)) ? '0 : queue_tail_next;
    end

    procyon_srff #(QUEUE_IDX_WIDTH) queue_head_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(queue_head_next), .i_reset('0), .o_q(queue_head_r));
    procyon_srff #(QUEUE_IDX_WIDTH) queue_tail_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(queue_tail_next), .i_reset('0), .o_q(queue_tail_r));

    assign o_queue_head = queue_head_r;
    assign o_queue_tail = queue_tail_r;

    // Down counter to keep track of number of enqueued items and to detect full and empty
    logic [QUEUE_COUNTER_WIDTH-1:0] queue_entry_counter_r;
    logic [QUEUE_COUNTER_WIDTH-1:0] queue_entry_counter_next;

    always_comb begin
        logic [1:0] queue_entry_counter_sel;
        queue_entry_counter_sel = {i_incr_head, i_incr_tail};

        queue_entry_counter_next = queue_entry_counter_r;

        case (queue_entry_counter_sel)
            2'b00: queue_entry_counter_next = queue_entry_counter_next;
            2'b01: queue_entry_counter_next = queue_entry_counter_next - 1'b1;
            2'b10: queue_entry_counter_next = queue_entry_counter_next + 1'b1;
            2'b11: queue_entry_counter_next = queue_entry_counter_next;
        endcase

        queue_entry_counter_next = i_flush ? (QUEUE_COUNTER_WIDTH)'(OPTN_QUEUE_DEPTH) : queue_entry_counter_next;
    end

    procyon_srff #(QUEUE_COUNTER_WIDTH) queue_entry_counter_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(queue_entry_counter_next), .i_reset((QUEUE_COUNTER_WIDTH)'(OPTN_QUEUE_DEPTH)), .o_q(queue_entry_counter_r));

    // Queue full signal
    logic queue_full;
    assign queue_full = ~i_flush & (queue_entry_counter_next == 0);
    procyon_srff #(1) queue_full_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(queue_full), .i_reset(1'b0), .o_q(queue_full_r));

    assign o_queue_full = queue_full_r;

    // Queue empty signal
    logic queue_empty;
    assign queue_empty = i_flush | (queue_entry_counter_next == (QUEUE_COUNTER_WIDTH)'(OPTN_QUEUE_DEPTH));
    procyon_srff #(1) queue_empty_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(queue_empty), .i_reset(1'b0), .o_q(queue_empty_r));

    assign o_queue_empty = queue_empty_r;

endmodule
