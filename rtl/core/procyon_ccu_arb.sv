/* 
 * Copyright (c) 2019 Sekhar Bhattacharya
 *
 * SPDS-License-Identifier: MIT
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
    input  logic                       i_ccu_arb_we    [0:OPTN_CCU_ARB_DEPTH-1],
    input  logic [OPTN_ADDR_WIDTH-1:0] i_ccu_arb_addr  [0:OPTN_CCU_ARB_DEPTH-1],
    input  logic [DC_LINE_WIDTH-1:0]   i_ccu_arb_data  [0:OPTN_CCU_ARB_DEPTH-1],
    output logic                       o_ccu_arb_done  [0:OPTN_CCU_ARB_DEPTH-1],
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

    logic [CCU_ARB_STATE_WIDTH-1:0] ccu_arb_state;
    logic [CCU_ARB_STATE_WIDTH-1:0] ccu_arb_state_next;
    logic [CCU_ARB_IDX_WIDTH-1:0]   ccu_arb_select;
    logic [CCU_ARB_IDX_WIDTH-1:0]   ccu_arb_idx;
    logic [CCU_ARB_IDX_WIDTH-1:0]   ccu_arb_idx_q;
    logic                           any_valid;

    assign any_valid      = (ccu_arb_select != {(OPTN_CCU_ARB_DEPTH){1'b0}});

    always_comb begin
        logic [CCU_ARB_IDX_WIDTH-1:0] ccu_arb_valid;
        for (int i = 0; i < CCU_ARB_IDX_WIDTH; i++) begin
            ccu_arb_valid[i] = i_ccu_arb_valid[i];
        end
        ccu_arb_select = ccu_arb_valid & ~(ccu_arb_valid - 1'b1);
    end

    // Output to CCU
    always_ff @(posedge clk) begin
        o_ccu_arb_done[ccu_arb_idx_q] <= (ccu_arb_state_next == CCU_ARB_STATE_DONE);
        o_ccu_arb_data                <= i_biu_data;
    end

    // Output to BIU
    always_ff @(posedge clk) begin
        o_biu_we   <= i_ccu_arb_we[ccu_arb_idx_q];
        o_biu_addr <= i_ccu_arb_addr[ccu_arb_idx_q];
        o_biu_data <= i_ccu_arb_data[ccu_arb_idx_q];
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_biu_en <= 1'b0;
        else        o_biu_en <= (ccu_arb_state == CCU_ARB_STATE_BUSY) & i_ccu_arb_valid[ccu_arb_idx_q];
    end

    // Convert one-hot ccu_arb_select vector into binary mux index
    always_comb begin
        ccu_arb_idx = {(CCU_ARB_IDX_WIDTH){1'b0}};
        for (int i = 0; i < OPTN_CCU_ARB_DEPTH; i++) begin
            if (ccu_arb_select[i]) begin
                ccu_arb_idx = CCU_ARB_IDX_WIDTH'(i);
            end
        end
    end

    always_ff @(posedge clk) begin
        if (ccu_arb_state == CCU_ARB_STATE_IDLE) ccu_arb_idx_q <= ccu_arb_idx;
    end

    // Update state
    always_comb begin
        ccu_arb_state_next = ccu_arb_state;
        case (ccu_arb_state_next)
            CCU_ARB_STATE_IDLE: ccu_arb_state_next = any_valid ? CCU_ARB_STATE_BUSY : ccu_arb_state_next;
            CCU_ARB_STATE_BUSY: ccu_arb_state_next = i_biu_done ? CCU_ARB_STATE_DONE : ccu_arb_state_next;
            CCU_ARB_STATE_DONE: ccu_arb_state_next = CCU_ARB_STATE_IDLE;
            default:            ccu_arb_state_next = CCU_ARB_STATE_IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        if (~n_rst) ccu_arb_state <= CCU_ARB_STATE_IDLE;
        else        ccu_arb_state <= ccu_arb_state_next;
    end

endmodule
