/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Core Communications Unit Arbiter
// This module will select requests to forward to the BIU using priority arbitration

module procyon_ccu_arb #(
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_CCU_ARB_DEPTH = 1,
    parameter OPTN_CCU_LINE_SIZE = 32,

    parameter CCU_LINE_WIDTH     = OPTN_CCU_LINE_SIZE * 8
)(
    input  logic                            clk,
    input  logic                            n_rst,

    // CCU request handshake signals
    input  logic [OPTN_CCU_ARB_DEPTH-1:0]   i_ccu_arb_valid,
    input  logic [OPTN_CCU_ARB_DEPTH-1:0]   i_ccu_arb_we,
    input  logic [`PCYN_CCU_LEN_WIDTH-1:0]  i_ccu_arb_len [0:OPTN_CCU_ARB_DEPTH-1],
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_ccu_arb_addr [0:OPTN_CCU_ARB_DEPTH-1],
    input  logic [CCU_LINE_WIDTH-1:0]       i_ccu_arb_data [0:OPTN_CCU_ARB_DEPTH-1],
    output logic [OPTN_CCU_ARB_DEPTH-1:0]   o_ccu_arb_done,
    output logic [OPTN_CCU_ARB_DEPTH-1:0]   o_ccu_arb_grant,
    output logic [CCU_LINE_WIDTH-1:0]       o_ccu_arb_data,

    // BIU interface
    input  logic                            i_biu_done,
    input  logic [CCU_LINE_WIDTH-1:0]       i_biu_data,
    output logic                            o_biu_en,
    output logic [`PCYN_BIU_FUNC_WIDTH-1:0] o_biu_func,
    output logic [`PCYN_BIU_LEN_WIDTH-1:0]  o_biu_len,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_biu_addr,
    output logic [CCU_LINE_WIDTH-1:0]       o_biu_data
);

    localparam CCU_ARB_IDX_WIDTH   = OPTN_CCU_ARB_DEPTH == 1 ? 1 : $clog2(OPTN_CCU_ARB_DEPTH);
    localparam CCU_ARB_STATE_WIDTH = 2;

    typedef enum logic [CCU_ARB_STATE_WIDTH-1:0] {
        CCU_ARB_STATE_IDLE  = 2'b00,
        CCU_ARB_STATE_BUSY  = 2'b01,
        CCU_ARB_STATE_DONE  = 2'b10
    } ccu_arb_state_t;

    // Pick a requestor giving priority to the requestor mapped to bit 0
    logic [OPTN_CCU_ARB_DEPTH-1:0] ccu_arb_select;
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
    ccu_arb_state_t ccu_arb_state_r;
    ccu_arb_state_t ccu_arb_state_next;
    logic [OPTN_CCU_ARB_DEPTH-1:0] ccu_arb_done;
    logic [OPTN_CCU_ARB_DEPTH-1:0] ccu_arb_grant;
    logic biu_en;

    always_comb begin
        logic any_valid;
        any_valid = (ccu_arb_select != 0);

        ccu_arb_done = '0;
        ccu_arb_grant = '0;

        case (ccu_arb_state_r)
            CCU_ARB_STATE_IDLE: begin
                ccu_arb_done = '0;
                ccu_arb_grant = ccu_arb_select;
                biu_en = 1'b0;
                ccu_arb_state_next = any_valid ? CCU_ARB_STATE_BUSY : ccu_arb_state_r;
            end
            CCU_ARB_STATE_BUSY: begin
                ccu_arb_done[ccu_arb_idx_r] = i_biu_done;
                ccu_arb_grant = '0;
                biu_en = i_biu_done ? 1'b0 : i_ccu_arb_valid[ccu_arb_idx_r];
                ccu_arb_state_next = i_biu_done ? CCU_ARB_STATE_DONE : ccu_arb_state_r;
            end
            CCU_ARB_STATE_DONE: begin
                ccu_arb_done = '0;
                ccu_arb_grant = '0;
                biu_en = 1'b0;
                ccu_arb_state_next = CCU_ARB_STATE_IDLE;
            end
            default: begin
                ccu_arb_done = '0;
                ccu_arb_grant = '0;
                biu_en = 1'b0;
                ccu_arb_state_next = CCU_ARB_STATE_IDLE;
            end
        endcase
    end

    procyon_srff #(CCU_ARB_STATE_WIDTH) ccu_arb_state_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(ccu_arb_state_next), .i_reset(CCU_ARB_STATE_IDLE), .o_q(ccu_arb_state_r));

    // Only set the DONE and GRANT signals for the selected requestor
    procyon_srff #(OPTN_CCU_ARB_DEPTH) o_ccu_arb_done_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(ccu_arb_done), .i_reset('0), .o_q(o_ccu_arb_done));
    procyon_srff #(OPTN_CCU_ARB_DEPTH) o_ccu_arb_grant_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(ccu_arb_grant), .i_reset('0), .o_q(o_ccu_arb_grant));

    procyon_ff #(CCU_LINE_WIDTH) o_ccu_arb_data_ff (.clk(clk), .i_en(1'b1), .i_d(i_biu_data), .o_q(o_ccu_arb_data));

    // Output to BIU
    procyon_srff #(1) o_biu_en_ff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(biu_en), .i_reset(1'b0), .o_q(o_biu_en));
    procyon_ff #(`PCYN_BIU_LEN_WIDTH) o_biu_len_ff (.clk(clk), .i_en(1'b1), .i_d(i_ccu_arb_len[ccu_arb_idx_r]), .o_q(o_biu_len));
    procyon_ff #(OPTN_ADDR_WIDTH) o_biu_addr_ff (.clk(clk), .i_en(1'b1), .i_d(i_ccu_arb_addr[ccu_arb_idx_r]), .o_q(o_biu_addr));
    procyon_ff #(CCU_LINE_WIDTH) o_biu_data_ff (.clk(clk), .i_en(1'b1), .i_d(i_ccu_arb_data[ccu_arb_idx_r]), .o_q(o_biu_data));

    logic [`PCYN_BIU_FUNC_WIDTH-1:0] biu_func;
    assign biu_func = i_ccu_arb_we[ccu_arb_idx_r] ? `PCYN_BIU_FUNC_WRITE : `PCYN_BIU_FUNC_READ;

    procyon_ff #(`PCYN_BIU_FUNC_WIDTH) o_biu_func_ff (.clk(clk), .i_en(1'b1), .i_d(biu_func), .o_q(o_biu_func));

endmodule
