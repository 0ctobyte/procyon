/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Synchronous FIFO

module procyon_sync_fifo #(
    parameter OPTN_DATA_WIDTH = 8,
    parameter OPTN_FIFO_DEPTH = 8
)(
    input  logic                       clk,
    input  logic                       n_rst,

    input  logic                       i_flush,

    // FIFO read interface
    input  logic                       i_fifo_ack,
    output logic [OPTN_DATA_WIDTH-1:0] o_fifo_data,
    output logic                       o_fifo_valid,

    // FIFO write interface
    input  logic                       i_fifo_we,
    input  logic [OPTN_DATA_WIDTH-1:0] i_fifo_data,
    output logic                       o_fifo_full
);

    localparam FIFO_IDX_WIDTH     = $clog2(OPTN_FIFO_DEPTH);
    localparam FIFO_COUNTER_WIDTH = $clog2(OPTN_FIFO_DEPTH+1);

    logic [FIFO_IDX_WIDTH-1:0] fifo_head_r;
    logic [FIFO_IDX_WIDTH-1:0] fifo_tail_r;
    logic fifo_full_r;
    logic fifo_empty_r;

    // Generate fifo_ack and ram_we control signal
    logic fifo_ack;
    logic ram_we;

    assign fifo_ack = ~fifo_empty_r && i_fifo_ack;
    assign ram_we = ~fifo_full_r && i_fifo_we;

    // Determine next cycle head and tail pointers and register head/tail pointers
    logic [FIFO_IDX_WIDTH-1:0] fifo_head_next;
    logic [FIFO_IDX_WIDTH-1:0] fifo_tail_next;

    always_comb begin
        fifo_head_next = i_flush ? '0 : (fifo_ack ? fifo_head_r + 1'b1 : fifo_head_r);
        fifo_tail_next = i_flush ? '0 : (ram_we ? fifo_tail_r + 1'b1 : fifo_tail_r);

        // Handle wrap around case
        fifo_head_next = (fifo_head_next == (FIFO_IDX_WIDTH)'(OPTN_FIFO_DEPTH)) ? '0 : fifo_head_next;
        fifo_tail_next = (fifo_tail_next == (FIFO_IDX_WIDTH)'(OPTN_FIFO_DEPTH)) ? '0 : fifo_tail_next;
    end

    procyon_srff #(FIFO_IDX_WIDTH) fifo_head_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(fifo_head_next), .i_reset('0), .o_q(fifo_head_r));
    procyon_srff #(FIFO_IDX_WIDTH) fifo_tail_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(fifo_tail_next), .i_reset('0), .o_q(fifo_tail_r));

    // FIFO entry counter. Used for full and empty detection.
    logic [FIFO_COUNTER_WIDTH-1:0] fifo_entry_counter_r;
    logic [FIFO_COUNTER_WIDTH-1:0] fifo_entry_counter_next;

    always_comb begin
        logic [1:0] fifo_entry_counter_sel;
        fifo_entry_counter_sel = {fifo_ack, ram_we};

        fifo_entry_counter_next = fifo_entry_counter_r;

        case (fifo_entry_counter_sel)
            2'b00: fifo_entry_counter_next = fifo_entry_counter_next;
            2'b01: fifo_entry_counter_next = fifo_entry_counter_next - 1'b1;
            2'b10: fifo_entry_counter_next = fifo_entry_counter_next + 1'b1;
            2'b11: fifo_entry_counter_next = fifo_entry_counter_next;
        endcase

        fifo_entry_counter_next = i_flush ? (FIFO_COUNTER_WIDTH)'(OPTN_FIFO_DEPTH) : fifo_entry_counter_next;
    end

    procyon_srff #(FIFO_COUNTER_WIDTH) fifo_entry_counter_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(fifo_entry_counter_next), .i_reset((FIFO_COUNTER_WIDTH)'(OPTN_FIFO_DEPTH)), .o_q(fifo_entry_counter_r));

    logic n_flush;
    assign n_flush = ~i_flush;

    // Calculate fifo full and empty status
    logic fifo_full_next;
    logic fifo_empty_next;

    assign fifo_full_next = n_flush & (fifo_entry_counter_next == 0);
    procyon_srff #(1) fifo_full_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(fifo_full_next), .i_reset(1'b0), .o_q(fifo_full_r));

    assign fifo_empty_next = i_flush | (fifo_entry_counter_next == (FIFO_COUNTER_WIDTH)'(OPTN_FIFO_DEPTH));
    procyon_srff #(1) fifo_empty_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(fifo_empty_next), .i_reset(1'b1), .o_q(fifo_empty_r));

    // fifo output is valid if it is not empty
    assign o_fifo_full = fifo_full_r;

    logic fifo_valid;
    assign fifo_valid = n_flush & ~fifo_empty_r;
    procyon_srff #(1) o_fifo_valid_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(fifo_valid), .i_reset(1'b0), .o_q(o_fifo_valid));

    procyon_ram_sdpb #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_RAM_DEPTH(OPTN_FIFO_DEPTH)
    ) fifo_mem (
        .clk(clk),
        .i_ram_we(ram_we),
        .i_ram_re(fifo_ack),
        .i_ram_addr_r(fifo_head_r),
        .i_ram_addr_w(fifo_tail_r),
        .i_ram_data(i_fifo_data),
        .o_ram_data(o_fifo_data)
    );

endmodule
