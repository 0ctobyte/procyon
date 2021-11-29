/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Instruction fetch unit

module procyon_fetch #(
    parameter OPTN_INSN_WIDTH      = 32,
    parameter OPTN_ADDR_WIDTH      = 32,
    parameter OPTN_INSN_FIFO_DEPTH = 8,
    parameter OPTN_IC_CACHE_SIZE   = 1024,
    parameter OPTN_IC_LINE_SIZE    = 32,
    parameter OPTN_IC_WAY_COUNT    = 1,

    parameter IC_LINE_WIDTH        = OPTN_IC_LINE_SIZE * 8
)(
    input  logic                            clk,
    input  logic                            n_rst,

    input  logic                            i_redirect,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_redirect_addr,

    input  logic                            i_ifq_full,

    // Interface to the IFQ
    input  logic                            i_ifq_fill_en,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_ifq_fill_addr,
    input  logic [IC_LINE_WIDTH-1:0]        i_ifq_fill_data,
    output logic                            o_ifq_alloc_en,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_ifq_alloc_addr,

    // Interface to decoder
    input  logic                            i_decode_stall,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_fetch_pc,
    output logic [OPTN_INSN_WIDTH-1:0]      o_fetch_insn,
    output logic                            o_fetch_valid
);

    // NEXT_FETCH:  Continue fetching next PC
    // IFQ_ENQUEUE: Enqueue PC in the IFQ
    // IFQ_STALL:   Stall fetch pipeline until IFQ signals a fill
    // FIFO_STALL:  Stall fetch pipeline until the instruction FIFO has room again
    localparam FETCH_STATE_WIDTH       = 2;
    localparam FETCH_STATE_NEXT_FETCH  = 2'b00;
    localparam FETCH_STATE_IFQ_ENQUEUE = 2'b01;
    localparam FETCH_STATE_IFQ_STALL   = 2'b10;
    localparam FETCH_STATE_FIFO_STALL  = 2'b11;

    logic [FETCH_STATE_WIDTH-1:0] fetch_state_r;

    logic fetch_it_valid_r;
    logic [OPTN_INSN_WIDTH-1:0] fetch_it_addr_r;
    logic fetch_ir_valid_r;
    logic [OPTN_INSN_WIDTH-1:0] fetch_ir_addr_r;
    logic fetch_ifq_valid_r;
    logic [OPTN_INSN_WIDTH-1:0] fetch_ifq_addr_r;
    logic ic_hit;
    logic [OPTN_INSN_WIDTH-1:0] ic_data;
    logic insn_fifo_ack;
    logic insn_fifo_empty;
    logic insn_fifo_full;
    logic [OPTN_ADDR_WIDTH+OPTN_INSN_WIDTH-1:0] insn_fifo_data_o;
    logic [OPTN_ADDR_WIDTH+OPTN_INSN_WIDTH-1:0] insn_fifo_data_i;

    logic n_insn_fifo_full;
    assign n_insn_fifo_full = ~insn_fifo_full;

    logic hit;
    assign hit = ic_hit & fetch_ir_valid_r;

    logic n_hit;
    assign n_hit = ~ic_hit & fetch_ir_valid_r;

    logic n_redirect;
    assign n_redirect = ~i_redirect;

    logic fetch_state_is_next_fetch;
    assign fetch_state_is_next_fetch = (fetch_state_r == FETCH_STATE_NEXT_FETCH);

    // Save fetch valid signal through IT and IR pipeline stages
    logic fetch_it_valid;
    assign fetch_it_valid = fetch_state_is_next_fetch & n_insn_fifo_full & n_redirect;

    procyon_srff #(1) fetch_it_valid_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(fetch_it_valid), .i_reset('0), .o_q(fetch_it_valid_r));

    logic fetch_ir_valid;
    assign fetch_ir_valid = fetch_it_valid_r & n_redirect;

    procyon_srff #(1) fetch_ir_valid_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(fetch_ir_valid), .i_reset('0), .o_q(fetch_ir_valid_r));

    logic fetch_ifq_valid;
    assign fetch_ifq_valid = fetch_ir_valid_r & n_hit & (fetch_state_next == FETCH_STATE_IFQ_ENQUEUE) & n_redirect;

    procyon_srff #(1) fetch_ifq_valid_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(fetch_ifq_valid), .i_reset('0), .o_q(fetch_ifq_valid_r));

    // Save fetch addr signal through IT and IR pipeline stages. Also save the PC sent to the IFQ to restart the
    // pipeline when the fill arrives
    procyon_ff #(OPTN_INSN_WIDTH) fetch_it_addr_r_ff (.clk(clk), .i_en(1'b1), .i_d(pc_r), .o_q(fetch_it_addr_r));
    procyon_ff #(OPTN_INSN_WIDTH) fetch_ir_addr_r_ff (.clk(clk), .i_en(1'b1), .i_d(fetch_it_addr_r), .o_q(fetch_ir_addr_r));
    procyon_ff #(OPTN_INSN_WIDTH) fetch_ifq_addr_r_ff (.clk(clk), .i_en(fetch_state_is_next_fetch), .i_d(fetch_ir_addr_r), .o_q(fetch_ifq_addr_r));

    // FSM
    logic [FETCH_STATE_WIDTH-1:0] fetch_state_next;

    always_comb begin
        fetch_state_next = fetch_state_r;

        case (fetch_state_next)
            FETCH_STATE_NEXT_FETCH:  fetch_state_next = insn_fifo_full ? FETCH_STATE_FIFO_STALL : (n_hit ? FETCH_STATE_IFQ_ENQUEUE : FETCH_STATE_NEXT_FETCH);
            FETCH_STATE_IFQ_ENQUEUE: fetch_state_next = ~i_ifq_full ? FETCH_STATE_IFQ_STALL : FETCH_STATE_IFQ_ENQUEUE;
            FETCH_STATE_IFQ_STALL:   fetch_state_next = i_ifq_fill_en ? FETCH_STATE_NEXT_FETCH : FETCH_STATE_IFQ_STALL;
            FETCH_STATE_FIFO_STALL:  fetch_state_next = n_insn_fifo_full ? FETCH_STATE_NEXT_FETCH : FETCH_STATE_FIFO_STALL;
            default:                 fetch_state_next = FETCH_STATE_NEXT_FETCH;
        endcase

        fetch_state_next = i_redirect ? FETCH_STATE_NEXT_FETCH : fetch_state_next;
    end

    procyon_srff #(FETCH_STATE_WIDTH) fetch_state_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(fetch_state_next), .i_reset(FETCH_STATE_NEXT_FETCH), .o_q(fetch_state_r));

    // PC mux
    logic [OPTN_ADDR_WIDTH-1:0] pc_r;
    logic [OPTN_ADDR_WIDTH-1:0] pc_next;

    always_comb begin
        logic [OPTN_ADDR_WIDTH-1:0] pc_plus_4;
        pc_plus_4 = pc_r + 4;

        case (fetch_state_r)
            FETCH_STATE_NEXT_FETCH:  pc_next = pc_plus_4;
            FETCH_STATE_IFQ_ENQUEUE: pc_next = pc_plus_4;
            FETCH_STATE_IFQ_STALL:   pc_next = fetch_ifq_addr_r;
            FETCH_STATE_FIFO_STALL:  pc_next = fetch_ifq_addr_r;
            default:                 pc_next = pc_r;
        endcase

        pc_next = i_redirect ? i_redirect_addr : pc_next;
    end

    procyon_srff #(OPTN_INSN_WIDTH) pc_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(pc_next), .i_reset('0), .o_q(pc_r));

    procyon_icache #(
        .OPTN_INSN_WIDTH(OPTN_INSN_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_IC_CACHE_SIZE(OPTN_IC_CACHE_SIZE),
        .OPTN_IC_LINE_SIZE(OPTN_IC_LINE_SIZE),
        .OPTN_IC_WAY_COUNT(OPTN_IC_WAY_COUNT)
    ) procyon_icache_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_ic_en(fetch_it_valid),
        .i_ic_addr(pc_r),
        .o_ic_hit(ic_hit),
        .o_ic_data(ic_data),
        .i_ic_fill_en(i_ifq_fill_en),
        .i_ic_fill_addr(i_ifq_fill_addr),
        .i_ic_fill_data(i_ifq_fill_data)
    );

    procyon_sync_fifo #(
        .OPTN_DATA_WIDTH(OPTN_ADDR_WIDTH+OPTN_INSN_WIDTH),
        .OPTN_FIFO_DEPTH(OPTN_INSN_FIFO_DEPTH)
    ) procyon_insn_fifo (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_redirect),
        .i_fifo_ack(insn_fifo_ack),
        .o_fifo_data(insn_fifo_data_o),
        .o_fifo_empty(insn_fifo_empty),
        .i_fifo_we(hit),
        .i_fifo_data(insn_fifo_data_i),
        .o_fifo_full(insn_fifo_full)
    );

    assign insn_fifo_data_i = {fetch_ir_addr_r, ic_data};
    assign insn_fifo_ack = ~insn_fifo_empty & ~i_decode_stall & n_redirect;

    logic insn_fifo_ack_r;
    procyon_srff #(1) insn_fifo_ack_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(insn_fifo_ack), .i_reset('0), .o_q(insn_fifo_ack_r));

    // Pop FIFO data and send to dispatch stage. Ack the FIFO to allow it to remove the head entry
    assign o_fetch_pc = insn_fifo_data_o[OPTN_ADDR_WIDTH+OPTN_INSN_WIDTH-1:OPTN_INSN_WIDTH];
    assign o_fetch_insn = insn_fifo_data_o[OPTN_INSN_WIDTH-1:0];
    assign o_fetch_valid = insn_fifo_ack_r;

    // Send request to the IFQ if PC misses in the icache
    assign o_ifq_alloc_en = fetch_ifq_valid_r;
    assign o_ifq_alloc_addr = fetch_ifq_addr_r;

endmodule
