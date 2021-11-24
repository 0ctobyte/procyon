/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Victim Queue
// Queue for victimized cachelines
// Loads will lookup in the victim queue and use the data if available. Stores will not lookup and instead be enqueued
// in the MHQ.
// The VQ consists of a single stage pipeline with two events that need to be handled in the stage
// Lookup event for loads:
// - CAM for valid matching addresses and output hit and data info to LSU_EX
// Allocate event:
// - Enqueue evicted cachelines

`include "procyon_constants.svh"

module procyon_vq #(
    parameter OPTN_DATA_WIDTH   = 32,
    parameter OPTN_ADDR_WIDTH   = 32,
    parameter OPTN_VQ_DEPTH     = 4,
    parameter OPTN_DC_LINE_SIZE = 1024,

    parameter DC_LINE_WIDTH     = OPTN_DC_LINE_SIZE * 8,
    parameter DATA_SIZE         = OPTN_DATA_WIDTH / 8
)(
    input  logic                            clk,
    input  logic                            n_rst,

    output logic                            o_vq_full,

    // Interface to LSU to match lookup address to valid entries and return enqueue tag
    input  logic                            i_vq_lookup_valid,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_vq_lookup_addr,
    input  logic [DATA_SIZE-1:0]            i_vq_lookup_byte_sel,
    output logic                            o_vq_lookup_hit,
    output logic [OPTN_DATA_WIDTH-1:0]      o_vq_lookup_data,

    // Victim enqueue interface
    input  logic                            i_vq_victim_valid,
/* verilator lint_off UNUSED */
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_vq_victim_addr,
/* verilator lint_on  UNUSED */
    input  logic [DC_LINE_WIDTH-1:0]        i_vq_victim_data,

    // CCU interface
    input  logic                            i_ccu_grant,
    output logic                            o_ccu_en,
    output logic                            o_ccu_we,
    output logic [`PCYN_CCU_LEN_WIDTH-1:0]  o_ccu_len,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_ccu_addr,
    output logic [DC_LINE_WIDTH-1:0]        o_ccu_data
);

    localparam VQ_IDX_WIDTH    = OPTN_VQ_DEPTH == 1 ? 1 : $clog2(OPTN_VQ_DEPTH);
    localparam DC_OFFSET_WIDTH = $clog2(OPTN_DC_LINE_SIZE);

    logic [VQ_IDX_WIDTH-1:0] vq_queue_head;
    logic [VQ_IDX_WIDTH-1:0] vq_queue_tail;
    logic vq_queue_full;
/* verilator lint_off UNUSED */
    logic vq_queue_empty;
/* verilator lint_on  UNUSED */

    logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] vq_lookup_addr;
    assign vq_lookup_addr = i_vq_lookup_addr[OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH];

    logic [DC_OFFSET_WIDTH-1:0] vq_lookup_offset;
    assign vq_lookup_offset = i_vq_lookup_addr[DC_OFFSET_WIDTH-1:0];

    logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] vq_victim_addr;
    assign vq_victim_addr = i_vq_victim_addr[OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH];

    logic [OPTN_VQ_DEPTH-1:0] vq_entry_valid;
    logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] vq_entry_addr [0:OPTN_VQ_DEPTH-1];
    logic [DC_LINE_WIDTH-1:0] vq_entry_data [0:OPTN_VQ_DEPTH-1];

    logic [OPTN_VQ_DEPTH-1:0] ccu_grant;

    always_comb begin
        ccu_grant = '0;
        ccu_grant[vq_queue_head] = i_ccu_grant;
    end

    // Convert tail pointer to one-hot allocation select vector
    logic [OPTN_VQ_DEPTH-1:0] vq_alloc_select;
    procyon_binary2onehot #(OPTN_VQ_DEPTH) vq_alloc_select_binary2onehot (.i_binary(vq_queue_tail), .o_onehot(vq_alloc_select));

    logic [OPTN_VQ_DEPTH-1:0] vq_alloc_en;
    assign vq_alloc_en = (~i_vq_victim_valid | vq_queue_full) ? '0 : vq_alloc_select;

    logic [OPTN_VQ_DEPTH-1:0] vq_lookup_hit_select;

    genvar inst;
    generate
    for (inst = 0; inst < OPTN_VQ_DEPTH; inst++) begin : GEN_VQ_ENTRY_INST
        procyon_vq_entry #(
            .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
            .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE)
        ) procyon_vq_entry_inst (
            .clk(clk),
            .n_rst(n_rst),
            .o_vq_entry_valid(vq_entry_valid[inst]),
            .o_vq_entry_addr(vq_entry_addr[inst]),
            .o_vq_entry_data(vq_entry_data[inst]),
            .i_lookup_addr(vq_lookup_addr),
            .o_lookup_hit(vq_lookup_hit_select[inst]),
            .i_alloc_en(vq_alloc_en[inst]),
            .i_alloc_data(i_vq_victim_data),
            .i_alloc_addr(vq_victim_addr),
            .i_ccu_grant(ccu_grant[inst])
        );
    end
    endgenerate

    // Convert lookup hit select vector to entry index
    logic [VQ_IDX_WIDTH-1:0] vq_lookup_hit_idx;
    procyon_onehot2binary #(OPTN_VQ_DEPTH) vq_lookup_hit_select_idx_onehot2binary (.i_onehot(vq_lookup_hit_select), .o_binary(vq_lookup_hit_idx));

    logic vq_allocating;
    assign vq_allocating = (vq_alloc_en != 0);

    // Increment tail pointer if an entry is going to be allocated
    // Increment head pointer when CCU sends grant
    procyon_queue_ctrl #(
        .OPTN_QUEUE_DEPTH(OPTN_VQ_DEPTH)
    ) vq_queue_ctrl (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(1'b0),
        .i_incr_head(i_ccu_grant),
        .i_incr_tail(vq_allocating),
        .o_queue_head(vq_queue_head),
        .o_queue_tail(vq_queue_tail),
        .o_queue_full(vq_queue_full),
        .o_queue_empty(vq_queue_empty)
    );

    // Output lookup results
    logic vq_lookup_hit;
    assign vq_lookup_hit = i_vq_lookup_valid & (vq_lookup_hit_select != 0);

    procyon_srff #(1) o_vq_lookup_hit_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(vq_lookup_hit), .i_reset('0), .o_q(o_vq_lookup_hit));

    // Extract read data word from cacheline masking off bytes according to the byte select
    logic [OPTN_DATA_WIDTH-1:0] vq_lookup_data;

    always_comb begin
        logic [DC_LINE_WIDTH-1:0] vq_lookup_cacheline;
        vq_lookup_cacheline = vq_entry_data[vq_lookup_hit_idx];

        vq_lookup_data = '0;

        for (int i = 0; i < (OPTN_DC_LINE_SIZE-DATA_SIZE); i++) begin
            if (DC_OFFSET_WIDTH'(i) == vq_lookup_offset) begin
                for (int j = 0; j < DATA_SIZE; j++) begin
                    if (i_vq_lookup_byte_sel[j]) begin
                        vq_lookup_data[j*8 +: 8] = vq_lookup_cacheline[(i+j)*8 +: 8];
                    end
                end
            end
        end

        // Accessing bytes at the end of the line is tricky. We can't read or write past the end of the data line
        // So special case the accesses to the last DATA_SIZE portion of the line by only reading the bytes we can access
        for (int i = (OPTN_DC_LINE_SIZE-DATA_SIZE); i < OPTN_DC_LINE_SIZE; i++) begin
            if (DC_OFFSET_WIDTH'(i) == vq_lookup_offset) begin
                for (int j = 0; j < (OPTN_DC_LINE_SIZE-i); j++) begin
                    if (i_vq_lookup_byte_sel[j]) begin
                        vq_lookup_data[j*8 +: 8] = vq_lookup_cacheline[(i+j)*8 +: 8];
                    end
                end
            end
        end
    end


    procyon_ff #(OPTN_DATA_WIDTH) o_vq_lookup_data_ff (.clk(clk), .i_en(1'b1), .i_d(vq_lookup_data), .o_q(o_vq_lookup_data));

    // Signal to CCU to write data to memory
    assign o_ccu_en = vq_entry_valid[vq_queue_head];
    assign o_ccu_we = 1'b1;
    assign o_ccu_data = vq_entry_data[vq_queue_head];
    assign o_ccu_addr = {vq_entry_addr[vq_queue_head], {(DC_OFFSET_WIDTH){1'b0}}};

    generate
    case (OPTN_DC_LINE_SIZE)
        4:       assign o_ccu_len = `PCYN_CCU_LEN_4B;
        8:       assign o_ccu_len = `PCYN_CCU_LEN_8B;
        16:      assign o_ccu_len = `PCYN_CCU_LEN_16B;
        32:      assign o_ccu_len = `PCYN_CCU_LEN_32B;
        64:      assign o_ccu_len = `PCYN_CCU_LEN_64B;
        128:     assign o_ccu_len = `PCYN_CCU_LEN_128B;
        default: assign o_ccu_len = `PCYN_CCU_LEN_4B;
    endcase
    endgenerate

    // Output queue full signal
    assign o_vq_full = vq_queue_full;

endmodule
