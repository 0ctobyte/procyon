/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Instruction fetch unit

module procyon_fetch #(
    parameter OPTN_DATA_WIDTH = 32,
    parameter OPTN_ADDR_WIDTH = 32,
    parameter OPTN_INSN_FIFO_DEPTH = 8
)(
    input  logic                       clk,
    input  logic                       n_rst,

    input  logic                       i_redirect,
    input  logic [OPTN_ADDR_WIDTH-1:0] i_redirect_addr,

    // Interface to instruction memory simple, needs cache interface)
    input  logic [OPTN_DATA_WIDTH-1:0] i_insn,
    input  logic                       i_data_valid,
    output logic [OPTN_ADDR_WIDTH-1:0] o_pc,
    output logic                       o_en,

    // Interface to decoder
    input  logic                       i_decode_stall,
    output logic [OPTN_ADDR_WIDTH-1:0] o_fetch_pc,
    output logic [OPTN_DATA_WIDTH-1:0] o_fetch_insn,
    output logic                       o_fetch_valid
);

    logic insn_fifo_ack;
    logic insn_fifo_full;
    logic [OPTN_ADDR_WIDTH+OPTN_DATA_WIDTH-1:0] insn_fifo_data_o;
    logic [OPTN_ADDR_WIDTH+OPTN_DATA_WIDTH-1:0] insn_fifo_data_i;

    procyon_sync_fifo #(
        .OPTN_DATA_WIDTH(OPTN_ADDR_WIDTH+OPTN_DATA_WIDTH),
        .OPTN_FIFO_DEPTH(OPTN_INSN_FIFO_DEPTH)
    ) procyon_insn_fifo (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_redirect),
        .i_fifo_ack(insn_fifo_ack),
        .o_fifo_data(insn_fifo_data_o),
        .o_fifo_valid(o_fetch_valid),
        .i_fifo_we(i_data_valid),
        .i_fifo_data(insn_fifo_data_i),
        .o_fifo_full(insn_fifo_full)
    );

    logic data_valid;
    assign data_valid = i_data_valid | redirect_r;

    logic n_insn_fifo_full;
    assign n_insn_fifo_full = ~insn_fifo_full;

    // PC mux
    logic [OPTN_ADDR_WIDTH-1:0] pc_r;
    logic [OPTN_ADDR_WIDTH-1:0] next_pc;

    always_comb begin
        logic [1:0] pc_sel;
        logic [OPTN_ADDR_WIDTH-1:0] pc_plus_4;

        pc_sel = {i_redirect, data_valid & n_insn_fifo_full};
        pc_plus_4 = pc_r + 4;

        case (pc_sel)
            2'b00: next_pc = pc_r;
            2'b01: next_pc = pc_plus_4;
            2'b10: next_pc = i_redirect_addr;
            2'b11: next_pc = i_redirect_addr;
        endcase
    end

    procyon_srff #(OPTN_ADDR_WIDTH) pc_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(next_pc), .i_reset('0), .o_q(pc_r));

    // Register the current redirect status. This is used in the next cycle to control the PC sent to bootrom/ICache
    logic redirect_r;
    procyon_srff #(1) redirect_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(i_redirect), .i_reset(1'b0), .o_q(redirect_r));

    logic [OPTN_ADDR_WIDTH-1:0] insn_pc_r;

    // Register the current PC. This is used in the next cycle when the data at the PC is returned from bootrom/ICache
    procyon_ff #(OPTN_ADDR_WIDTH) insn_pc_r_ff (.clk(clk), .i_en(n_insn_fifo_full), .i_d(pc_r), .o_q(insn_pc_r));

    // Data to be enqueued in the FIFO
    assign insn_fifo_data_i = {insn_pc_r, i_insn};

    // Output PC and enable to bootrom/ICache
    assign o_pc = insn_fifo_full | ~data_valid ? insn_pc_r : pc_r;
    assign o_en = ~i_redirect;

    // Pop FIFO data and send to dispatch stage. Ack the FIFO to allow it to remove the heaad entry
    assign o_fetch_pc = insn_fifo_data_o[OPTN_ADDR_WIDTH+OPTN_DATA_WIDTH-1:OPTN_DATA_WIDTH];
    assign o_fetch_insn = insn_fifo_data_o[OPTN_DATA_WIDTH-1:0];
    assign insn_fifo_ack = ~i_decode_stall;

endmodule
