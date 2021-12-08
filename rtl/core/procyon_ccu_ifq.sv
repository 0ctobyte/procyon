/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Instruction Fetch Queue
// Queue to receive cachelines for the ICache
// Fetch unit will indicate what address to allocate in the queue and the IFQ will respond some cycles later with a
// fill with the cacheline data

/* verilator lint_off IMPORTSTAR */
import procyon_lib_pkg::*;
import procyon_core_pkg::*;
/* verilator lint_on  IMPORTSTAR */

module procyon_ccu_ifq #(
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_IFQ_DEPTH     = 1,
    parameter OPTN_IC_LINE_SIZE  = 32
)(
    input  logic                                    clk,
    input  logic                                    n_rst,

    output logic                                    o_ifq_full,

    // ICache miss enqueue interface
    input  logic                                    i_ifq_alloc_en,
/* verilator lint_off UNUSED */
    input  logic [OPTN_ADDR_WIDTH-1:0]              i_ifq_alloc_addr,
/* verilator lint_on  UNUSED */

    // ICache fille interface
    output logic                                    o_ifq_fill_en,
    output logic [OPTN_ADDR_WIDTH-1:0]              o_ifq_fill_addr,
    output logic [`PCYN_S2W(OPTN_IC_LINE_SIZE)-1:0] o_ifq_fill_data,

    // CCU interface
    input  logic                                    i_ccu_done,
    input  logic [`PCYN_S2W(OPTN_IC_LINE_SIZE)-1:0] i_ccu_data,
    output logic                                    o_ccu_en,
    output logic                                    o_ccu_we,
    output pcyn_ccu_len_t                           o_ccu_len,
    output logic [OPTN_ADDR_WIDTH-1:0]              o_ccu_addr
);

    localparam IFQ_IDX_WIDTH = `PCYN_C2I(OPTN_IFQ_DEPTH);
    localparam IC_LINE_WIDTH = `PCYN_S2W(OPTN_IC_LINE_SIZE);

    logic [IFQ_IDX_WIDTH-1:0] ifq_queue_head;
    logic [IFQ_IDX_WIDTH-1:0] ifq_queue_tail;
    logic ifq_queue_full;
/* verilator lint_off UNUSED */
    logic ifq_queue_empty;
/* verilator lint_on  UNUSED */

    logic [OPTN_ADDR_WIDTH-1:`PCYN_IC_OFFSET_WIDTH] ifq_alloc_addr;
    assign ifq_alloc_addr = i_ifq_alloc_addr[OPTN_ADDR_WIDTH-1:`PCYN_IC_OFFSET_WIDTH];

    logic [OPTN_IFQ_DEPTH-1:0] ifq_entry_valid;
    logic [OPTN_ADDR_WIDTH-1:`PCYN_IC_OFFSET_WIDTH] ifq_entry_addr [0:OPTN_IFQ_DEPTH-1];

    logic [OPTN_IFQ_DEPTH-1:0] ccu_done;

    always_comb begin
        ccu_done = '0;
        ccu_done[ifq_queue_head] = i_ccu_done;
    end

    // Convert tail pointer to one-hot allocation select vector
    logic [OPTN_IFQ_DEPTH-1:0] ifq_alloc_select;
    procyon_binary2onehot #(OPTN_IFQ_DEPTH) ifq_alloc_select_binary2onehot (.i_binary(ifq_queue_tail), .o_onehot(ifq_alloc_select));

    logic [OPTN_IFQ_DEPTH-1:0] ifq_alloc_en;
    assign ifq_alloc_en = (~i_ifq_alloc_en | ifq_queue_full) ? '0 : ifq_alloc_select;

    genvar inst;
    generate
    for (inst = 0; inst < OPTN_IFQ_DEPTH; inst++) begin : GEN_IFQ_ENTRY_INST
        procyon_ccu_ifq_entry #(
            .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
            .OPTN_IC_LINE_SIZE(OPTN_IC_LINE_SIZE)
        ) procyon_ccu_ifq_entry_inst (
            .clk(clk),
            .n_rst(n_rst),
            .o_ifq_entry_valid(ifq_entry_valid[inst]),
            .o_ifq_entry_addr(ifq_entry_addr[inst]),
            .i_alloc_en(ifq_alloc_en[inst]),
            .i_alloc_addr(ifq_alloc_addr),
            .i_ccu_done(ccu_done[inst])
        );
    end
    endgenerate

    logic ifq_allocating;
    assign ifq_allocating = (ifq_alloc_en != 0);

    // Increment tail pointer if an entry is going to be allocated
    // Increment head pointer when CCU sends grant
    procyon_queue_ctrl #(
        .OPTN_QUEUE_DEPTH(OPTN_IFQ_DEPTH)
    ) ifq_queue_ctrl (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(1'b0),
        .i_incr_head(i_ccu_done),
        .i_incr_tail(ifq_allocating),
        .o_queue_head(ifq_queue_head),
        .o_queue_tail(ifq_queue_tail),
        .o_queue_full(ifq_queue_full),
        .o_queue_empty(ifq_queue_empty)
    );

    // Output fill
    logic [OPTN_ADDR_WIDTH-1:0] ifq_fill_addr;
    logic [IC_LINE_WIDTH-1:0] ifq_fill_data;

    assign ifq_fill_addr = {ifq_entry_addr[ifq_queue_head], `PCYN_IC_OFFSET_WIDTH'(0)};
    assign ifq_fill_data = i_ccu_data[IC_LINE_WIDTH-1:0];

    procyon_srff #(1) o_ifq_fill_en_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(i_ccu_done), .i_reset(1'b0), .o_q(o_ifq_fill_en));
    procyon_ff #(OPTN_ADDR_WIDTH) o_ifq_fill_addr_ff (.clk(clk), .i_en(1'b1), .i_d(ifq_fill_addr), .o_q(o_ifq_fill_addr));
    procyon_ff #(IC_LINE_WIDTH) o_ifq_fill_data_ff (.clk(clk), .i_en(1'b1), .i_d(ifq_fill_data), .o_q(o_ifq_fill_data));

    // Signal to CCU to read data from memory
    assign o_ccu_en = ifq_entry_valid[ifq_queue_head];
    assign o_ccu_we = 1'b0;
    assign o_ccu_addr = {ifq_entry_addr[ifq_queue_head], `PCYN_IC_OFFSET_WIDTH'(0)};

    generate
    case (OPTN_IC_LINE_SIZE)
        4:       assign o_ccu_len = PCYN_CCU_LEN_4B;
        8:       assign o_ccu_len = PCYN_CCU_LEN_8B;
        16:      assign o_ccu_len = PCYN_CCU_LEN_16B;
        32:      assign o_ccu_len = PCYN_CCU_LEN_32B;
        64:      assign o_ccu_len = PCYN_CCU_LEN_64B;
        128:     assign o_ccu_len = PCYN_CCU_LEN_128B;
        default: assign o_ccu_len = PCYN_CCU_LEN_4B;
    endcase
    endgenerate

    // Output queue full signal
    assign o_ifq_full = ifq_queue_full;

endmodule
