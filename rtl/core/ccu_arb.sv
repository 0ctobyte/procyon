// Core Communications Unit Arbiter
// This module will select requests to forward to the BIU using priority arbitration

`include "common.svh"
import procyon_types::*;

module ccu_arb (
    input  logic                   clk,
    input  logic                   n_rst,

    // CCU request handshake signals
    input  logic                   i_ccu_arb_valid [`CCU_ARB_DEPTH-1:0],
    input  logic                   i_ccu_arb_we    [`CCU_ARB_DEPTH-1:0],
    input  procyon_addr_t          i_ccu_arb_addr  [`CCU_ARB_DEPTH-1:0],
    input  procyon_cacheline_t     i_ccu_arb_data  [`CCU_ARB_DEPTH-1:0],
    output logic                   o_ccu_arb_done  [`CCU_ARB_DEPTH-1:0],
    output procyon_cacheline_t     o_ccu_arb_data,

    // BIU interface
    input  logic                   i_biu_done,
    input  logic                   i_biu_busy,
    input  procyon_cacheline_t     i_biu_data,
    output logic                   o_biu_en,
    output logic                   o_biu_we,
    output procyon_addr_t          o_biu_addr,
    output procyon_cacheline_t     o_biu_data
);

    typedef enum logic [`CCU_ARB_DEPTH-1:0]        ccu_arb_vec_t;
    typedef enum logic [$clog(`CCU_ARB_DEPTH)-1:0] ccu_arb_idx_t;

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        BUSY = 2'b01,
        DONE = 2'b10
    } ccu_arb_state_t;

    ccu_arb_state_t                ccu_arb_state;
    ccu_arb_state_t                ccu_arb_state_next;
    ccu_arb_vec_t                  ccu_arb_select;
    ccu_arb_idx_t                  ccu_arb_idx;
    ccu_arb_idx_t                  ccu_arb_idx_q;
    logic                          any_valid;

    ccu_arb_select                 = i_ccu_arb_valid & ~(i_ccu_arb_valid - 1'b1);
    any_valid                      = (ccu_arb_select != {(`CCU_ARB_DEPTH){1'b0}});

    // Output to CCU
    always_ff @(posedge clk) begin
        o_ccu_arb_done[ccu_arb_idx_q] <= (ccu_arb_state_next == DONE);
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
        else        o_biu_en <= (ccu_arb_state == BUSY) & i_ccu_arb_valid[ccu_arb_idx_q];
    end

    // Convert one-hot ccu_arb_select vector into binary mux index
    always_comb begin
        lq_retire_slot = {($clog(`CCU_ARB_DEPTH)){1'b0}};
        for (int i = 0; i < `CCU_ARB_DEPTH; i++) begin
            if (ccu_arb_select[i]) begin
                ccu_arb_idx = ccu_arb_idx_t'(i);
            end
        end
    end

    always_ff @(posedge clk) begin
        if (ccu_arb_state == IDLE) ccu_arb_idx_q <= ccu_arb_idx;
    end

    // Update state
    always_comb begin
        ccu_arb_state_next = ccu_arb_state;
        case (ccu_arb_state_next)
            IDLE:    ccu_arb_state_next = any_valid ? BUSY : ccu_arb_state_next;
            BUSY:    ccu_arb_state_next = i_biu_done ? DONE : ccu_arb_state_next;
            DONE:    ccu_arb_state_next = IDLE;
            default: ccu_arb_state_next = IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        if (~n_rst) ccu_arb_state <= IDLE;
        else        ccu_arb_state <= ccu_arb_state_next;
    end

endmodule
