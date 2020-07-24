/* 
 * Copyright (c) 2019 Sekhar Bhattacharya
 *
 * SPDS-License-Identifier: MIT
 */

// Instruction fetch unit

module procyon_fetch #(
    parameter OPTN_DATA_WIDTH = 32,
    parameter OPTN_ADDR_WIDTH = 32
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

    // Interface to dispatcher
    input  logic                       i_dispatch_stall,
    output logic [OPTN_ADDR_WIDTH-1:0] o_dispatch_pc,
    output logic [OPTN_DATA_WIDTH-1:0] o_dispatch_insn,
    output logic                       o_dispatch_valid
);

    logic [OPTN_ADDR_WIDTH-1:0]                 pc;
    logic [OPTN_ADDR_WIDTH-1:0]                 insn_pc;
    logic [OPTN_ADDR_WIDTH-1:0]                 next_pc;
    logic [OPTN_ADDR_WIDTH-1:0]                 pc_plus_4;
    logic [1:0]                                 pc_sel;
    logic                                       insn_fifo_ack;
    logic                                       insn_fifo_full;
    logic [OPTN_ADDR_WIDTH+OPTN_DATA_WIDTH-1:0] insn_fifo_data_o;
    logic [OPTN_ADDR_WIDTH+OPTN_DATA_WIDTH-1:0] insn_fifo_data_i;
    logic                                       redirect_d;
    logic                                       data_valid;

    assign data_valid       = i_data_valid | redirect_d;
    assign insn_fifo_ack    = ~i_dispatch_stall;
    assign insn_fifo_data_i = {insn_pc, i_insn};

    assign pc_sel           = {i_redirect, data_valid & ~insn_fifo_full};
    assign pc_plus_4        = pc + 4;

    assign o_en             = ~i_redirect;
    assign o_pc             = insn_fifo_full | ~data_valid ? insn_pc : pc;

    assign o_dispatch_pc    = insn_fifo_data_o[OPTN_ADDR_WIDTH+OPTN_DATA_WIDTH-1:OPTN_DATA_WIDTH];
    assign o_dispatch_insn  = insn_fifo_data_o[OPTN_DATA_WIDTH-1:0];

    // PC mux
    always_comb begin
        case (pc_sel)
            2'b00: next_pc = pc;
            2'b01: next_pc = pc_plus_4;
            2'b10: next_pc = i_redirect_addr;
            2'b11: next_pc = i_redirect_addr;
        endcase
    end

    always_ff @(posedge clk) begin
        if (~n_rst) begin
            pc         <= {(OPTN_ADDR_WIDTH){1'b0}};
            redirect_d <= 1'b0;
        end else begin
            pc         <= next_pc;
            redirect_d <= i_redirect;
        end
    end

    always_ff @(posedge clk) begin
        if (~insn_fifo_full) insn_pc <= pc;
    end

    procyon_sync_fifo #(
        .OPTN_DATA_WIDTH(OPTN_ADDR_WIDTH+OPTN_DATA_WIDTH),
        .OPTN_FIFO_DEPTH(8)
    ) procyon_insn_fifo (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_redirect),
        .i_fifo_ack(insn_fifo_ack),
        .o_fifo_data(insn_fifo_data_o),
        .o_fifo_valid(o_dispatch_valid),
        .i_fifo_we(i_data_valid),
        .i_fifo_data(insn_fifo_data_i),
        .o_fifo_full(insn_fifo_full)
    );

endmodule
