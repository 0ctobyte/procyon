/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Core Communications Unit Arbiter
// This module will select requests to forward to the BIU using priority arbitration

module procyon_ccu_arb #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_CCU_ARB_DEPTH = 1,
    parameter OPTN_DC_LINE_SIZE  = 32,

    parameter DC_LINE_WIDTH      = OPTN_DC_LINE_SIZE * 8
)(
    input  logic                       clk,
    input  logic                       n_rst,

    // CCU request handshake signals
    input  logic                       i_ccu_arb_valid [0:OPTN_CCU_ARB_DEPTH-1],
    input  logic                       i_ccu_arb_we [0:OPTN_CCU_ARB_DEPTH-1],
    input  logic [OPTN_ADDR_WIDTH-1:0] i_ccu_arb_addr [0:OPTN_CCU_ARB_DEPTH-1],
    input  logic [DC_LINE_WIDTH-1:0]   i_ccu_arb_data [0:OPTN_CCU_ARB_DEPTH-1],
    output logic                       o_ccu_arb_done [0:OPTN_CCU_ARB_DEPTH-1],
    output logic [DC_LINE_WIDTH-1:0]   o_ccu_arb_data,

    // BIU interface
    input  logic                       i_biu_done,
    input  logic                       i_biu_busy,
    input  logic [DC_LINE_WIDTH-1:0]   i_biu_data,
    output logic                       o_biu_en,
    output logic                       o_biu_we,
    output logic [OPTN_ADDR_WIDTH-1:0] o_biu_addr,
    output logic [DC_LINE_WIDTH-1:0]   o_biu_data
);

    localparam CCU_ARB_IDX_WIDTH   = $clog2(OPTN_CCU_ARB_DEPTH);
    localparam CCU_ARB_STATE_WIDTH = 2;
    localparam CCU_ARB_STATE_IDLE  = 2'b00;
    localparam CCU_ARB_STATE_BUSY  = 2'b01;
    localparam CCU_ARB_STATE_DONE  = 2'b10;

    // Pick a requestor giving priority to the requestor mapped to bit 0
    logic [CCU_ARB_IDX_WIDTH-1:0] ccu_arb_select;
    procyon_priority_picker #(OPTN_CCU_ARB_DEPTH) ccu_arb_select_priority_picker (.i_in(i_ccu_arb_valid), .o_pick(ccu_arb_select));

    logic ccu_arb_state_is_idle;
    assign ccu_arb_state_is_idle = (ccu_arb_state_r == CCU_ARB_STATE_IDLE);

    // Convert one-hot ccu_arb_select vector into binary mux index
    logic [CCU_ARB_IDX_WIDTH-1:0] ccu_arb_idx_r;
    logic [CCU_ARB_IDX_WIDTH-1:0] ccu_arb_idx;

    procyon_onehot2binary #(OPTN_CCU_ARB_DEPTH) ccu_arb_idx_onehot2binary (.i_onehot(ccu_arb_select), .o_binary(ccu_arb_idx));
    procyon_ff #(CCU_ARB_IDX_WIDTH) ccu_arb_idx_r_ff (.clk(clk), .i_en(ccu_arb_state_is_idle), .i_d(ccu_arb_idx), .o_q(ccu_arb_idx_r));

    // CCU FSM
    // CCU can begin transaction if a requestor asserts valid and the FSM is in IDLE
    // CCU will be busy while the BIU is servicing that transaction. When it receives ack from BIU it will signal done to the requestor
    // After one cycle of asserting done, it will return back to the idle state.
    logic [CCU_ARB_STATE_WIDTH-1:0] ccu_arb_state_r;
    logic [CCU_ARB_STATE_WIDTH-1:0] ccu_arb_state_next;
    logic ccu_arb_done;
    logic biu_en;

    always_comb begin
        logic any_valid;
        any_valid = (ccu_arb_select != 0);

        case (ccu_arb_state_r)
            CCU_ARB_STATE_IDLE: begin
                ccu_arb_done = 1'b0;
                biu_en = 1'b0;
                ccu_arb_state_next = any_valid ? CCU_ARB_STATE_BUSY : ccu_arb_state_r;
            end
            CCU_ARB_STATE_BUSY: begin
                ccu_arb_done = i_biu_done;
                biu_en = i_ccu_arb_valid[ccu_arb_idx_r];
                ccu_arb_state_next = i_biu_done ? CCU_ARB_STATE_DONE : ccu_arb_state_r;
            end
            CCU_ARB_STATE_DONE: begin
                ccu_arb_done = 1'b0;
                biu_en = 1'b0;
                ccu_arb_state_next = CCU_ARB_STATE_IDLE;
            end
            default: begin
                ccu_arb_done = 1'b0;
                biu_en = 1'b0;
                ccu_arb_state_next = CCU_ARB_STATE_IDLE;
            end
        endcase
    end

    procyon_srff #(CCU_ARB_STATE_WIDTH) ccu_arb_state_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(ccu_arb_state_next), .i_reset(CCU_ARB_STATE_IDLE), .o_q(ccu_arb_state_r));

    // Only set the DONE signal for the selected requestor
    logic ccu_arb_idx_select;
    logic ccu_arb_done_select;

    procyon_binary2onehot #(OPTN_CCU_ARB_DEPTH) ccu_arb_idx_select_binary2onehot (.i_binary(ccu_arb_idx_r), .o_onehot(ccu_arb_idx_select));
    assign ccu_arb_done_select = {(OPTN_CCU_ARB_DEPTH){ccu_arb_done}} & ccu_arb_idx_select;
    procyon_srff #(1) o_ccu_arb_done_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(ccu_arb_done_select), .i_reset(1'b0), .o_q(o_ccu_arb_done));

    procyon_ff #(OPTN_DATA_WIDTH) o_ccu_arb_data_ff (.clk(clk), .i_en(1'b1), .i_d(i_biu_data), .o_q(o_ccu_arb_data));

    // Output to BIU
    procyon_srff #(1) o_biu_en_ff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(biu_en), .i_reset(1'b0), .o_q(o_biu_en));
    procyon_ff #(1) o_biu_we_ff (.clk(clk), .i_en(1'b1), .i_d(i_ccu_arb_we[ccu_arb_idx_r]), .o_q(o_biu_we));
    procyon_ff #(OPTN_ADDR_WIDTH) o_biu_addr_ff (.clk(clk), .i_en(1'b1), .i_d(i_ccu_arb_addr[ccu_arb_idx_r]), .o_q(o_biu_addr));
    procyon_ff #(OPTN_DATA_WIDTH) o_biu_data_ff (.clk(clk), .i_en(1'b1), .i_d(i_ccu_arb_data[ccu_arb_idx_r]), .o_q(o_biu_data));

endmodule
