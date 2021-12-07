/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

module procyon_ccu_ifq_entry #(
    parameter OPTN_ADDR_WIDTH   = 32,
    parameter OPTN_IC_LINE_SIZE = 32,

    parameter IC_LINE_WIDTH     = OPTN_IC_LINE_SIZE * 8,
    parameter IC_OFFSET_WIDTH   = $clog2(OPTN_IC_LINE_SIZE)
)(
    input  logic                                      clk,
    input  logic                                      n_rst,

    output logic                                      o_ifq_entry_valid,
    output logic [OPTN_ADDR_WIDTH-1:IC_OFFSET_WIDTH]  o_ifq_entry_addr,

    // Allocate to this entry
    input  logic                                      i_alloc_en,
    input  logic [OPTN_ADDR_WIDTH-1:IC_OFFSET_WIDTH]  i_alloc_addr,

    // CCU interface
    input  logic                                      i_ccu_done
);

    // Each entry in the IFQ can be in one of the following states
    // INVALID:       Entry is empty
    // VALID:         Entry is occupied
    localparam IFQ_ENTRY_STATE_WIDTH = 2;

    typedef enum logic [IFQ_ENTRY_STATE_WIDTH-1:0] {
        IFQ_ENTRY_STATE_INVALID  = (IFQ_ENTRY_STATE_WIDTH)'('b00),
        IFQ_ENTRY_STATE_VALID    = (IFQ_ENTRY_STATE_WIDTH)'('b01)
    } ifq_entry_state_t;

    // Each entry in the IFQ contains the following
    // state:          State of the IFQ entry
    // addr:           Address of the cacheline to fetch
    ifq_entry_state_t ifq_entry_state_r;
    logic [OPTN_ADDR_WIDTH-1:IC_OFFSET_WIDTH] ifq_entry_addr_r;

    // IFQ entry FSM
    ifq_entry_state_t ifq_entry_state_next;

    always_comb begin
        ifq_entry_state_next = ifq_entry_state_r;

        unique case (ifq_entry_state_next)
            IFQ_ENTRY_STATE_INVALID: ifq_entry_state_next = i_alloc_en ? IFQ_ENTRY_STATE_VALID : ifq_entry_state_next;
            IFQ_ENTRY_STATE_VALID:   ifq_entry_state_next = i_ccu_done ? IFQ_ENTRY_STATE_INVALID : ifq_entry_state_next;
            default:                 ifq_entry_state_next = IFQ_ENTRY_STATE_INVALID;
        endcase
    end

    procyon_srff #(IFQ_ENTRY_STATE_WIDTH) ifq_entry_state_r_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(ifq_entry_state_next), .i_reset(IFQ_ENTRY_STATE_INVALID), .o_q(ifq_entry_state_r));
    procyon_ff #(OPTN_ADDR_WIDTH-IC_OFFSET_WIDTH) ifq_entry_addr_r_ff (.clk(clk), .i_en(i_alloc_en), .i_d(i_alloc_addr), .o_q(ifq_entry_addr_r));

    logic ifq_entry_valid;
    assign ifq_entry_valid = (ifq_entry_state_r != IFQ_ENTRY_STATE_INVALID);

    // Output entry registers
    assign o_ifq_entry_valid = ifq_entry_valid;
    assign o_ifq_entry_addr = ifq_entry_addr_r;

endmodule
