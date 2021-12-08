/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Synchronous FIFO

/* verilator lint_off IMPORTSTAR */
import procyon_lib_pkg::*;
/* verilator lint_on  IMPORTSTAR */

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
    output logic                       o_fifo_empty,

    // FIFO write interface
    input  logic                       i_fifo_we,
    input  logic [OPTN_DATA_WIDTH-1:0] i_fifo_data,
    output logic                       o_fifo_full
);

    localparam FIFO_IDX_WIDTH = `PCYN_C2I(OPTN_FIFO_DEPTH);

    logic [FIFO_IDX_WIDTH-1:0] fifo_queue_head;
    logic [FIFO_IDX_WIDTH-1:0] fifo_queue_tail;
    logic fifo_queue_full;
    logic fifo_queue_empty;

    // Generate fifo_ack and ram_we control signal
    logic fifo_ack;
    logic ram_we;

    assign fifo_ack = ~fifo_queue_empty & i_fifo_ack;
    assign ram_we = ~fifo_queue_full & i_fifo_we;

    // Determine next cycle head and tail pointers and register head/tail pointers
    procyon_queue_ctrl #(
        .OPTN_QUEUE_DEPTH(OPTN_FIFO_DEPTH)
    ) sync_fifo_queue_ctrl (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .i_incr_head(fifo_ack),
        .i_incr_tail(ram_we),
        .o_queue_head(fifo_queue_head),
        .o_queue_tail(fifo_queue_tail),
        .o_queue_full(fifo_queue_full),
        .o_queue_empty(fifo_queue_empty)
    );

    assign o_fifo_full = fifo_queue_full;
    assign o_fifo_empty = fifo_queue_empty;

    procyon_ram_sdpb #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_RAM_DEPTH(OPTN_FIFO_DEPTH)
    ) fifo_mem (
        .clk(clk),
        .i_ram_rd_en(fifo_ack),
        .i_ram_rd_addr(fifo_queue_head),
        .o_ram_rd_data(o_fifo_data),
        .i_ram_wr_en(ram_we),
        .i_ram_wr_addr(fifo_queue_tail),
        .i_ram_wr_data(i_fifo_data)
    );

endmodule
