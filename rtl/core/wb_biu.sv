// Wishbone Bus Interface Unit
// This module is the interface to the Wishbone Bus
// All transactions from the CPU will go through here

`include "common.svh"
import procyon_types::*;

module wb_biu (
    // Wishbone interface
    input  logic                     i_wb_clk,
    input  logic                     i_wb_rst,
    input  logic                     i_wb_ack,
    input  logic                     i_wb_stall,
    input  wb_data_t                 i_wb_data,
    output logic                     o_wb_cyc,
    output logic                     o_wb_stb,
    output logic                     o_wb_we,
    output wb_byte_select_t          o_wb_sel,
    output wb_addr_t                 o_wb_addr,
    output wb_data_t                 o_wb_data,

    // CCU interface
    input  logic                     i_biu_en,
    input  logic                     i_biu_we,
    input  procyon_addr_t            i_biu_addr,
    input  procyon_cacheline_t       i_biu_data,
    output procyon_cacheline_t       o_biu_data,
    output logic                     o_biu_busy,
    output logic                     o_biu_done
);

    typedef logic [$clog2(`DC_LINE_WIDTH/`WB_DATA_WIDTH):0] biu_req_size_t;

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        REQS = 2'b01,
        ACKS = 2'b10,
        DONE = 2'b11
    } state_t;

    state_t                next_state;
    state_t                state_q;
    biu_req_size_t         num_reqs;
    biu_req_size_t         num_acks;
    biu_req_size_t         req_idx;
    biu_req_size_t         ack_idx;
    biu_req_size_t         addr_offset;
    wb_data_t              next_data;
    procyon_cacheline_t    biu_data;
    logic                  in_progress;
    logic                  state_in_reqs;
    logic                  state_in_idle;
    logic                  requesting;

    assign state_in_idle   = state_q == IDLE;
    assign state_in_reqs   = state_q == REQS;
    assign in_progress     = state_in_reqs | (state_q == ACKS);
    assign requesting      = state_in_reqs & ~i_wb_stall;

    // Output to CCU
    assign o_biu_data      = biu_data;
    assign o_biu_done      = (state_q == DONE);
    assign o_biu_busy      = in_progress;

    // Output to Wishbone interface
    assign o_wb_cyc        = in_progress;
    assign o_wb_stb        = state_in_reqs;
    assign o_wb_we         = i_biu_we;
    assign o_wb_sel        = {{(`WB_DATA_WIDTH/8){1'b1}}};
    assign o_wb_addr       = i_biu_addr + {{(`WB_ADDR_WIDTH-$clog2(`DC_LINE_WIDTH/`WB_DATA_WIDTH)-1){1'b0}}, addr_offset};
    assign o_wb_data       = next_data;

    // Select the next bits of data
    always_comb begin
        next_data = i_biu_data[req_idx*(`WB_DATA_WIDTH) +: (`WB_DATA_WIDTH)];
    end

    // Update state
    always_comb begin
        case (state_q)
            IDLE: next_state = i_biu_en ? REQS : IDLE;
            REQS: next_state = (num_reqs == 0) ? ACKS : REQS;
            ACKS: next_state = (num_acks == 0) ? DONE : ACKS;
            DONE: next_state = ~i_biu_en ? IDLE : DONE;
        endcase
    end

    // Grab data from the Wishbone interface
    always_ff @(posedge i_wb_clk) begin
        if (i_wb_ack & (|num_acks)) begin
            biu_data[ack_idx*(`WB_DATA_WIDTH) +: (`WB_DATA_WIDTH)] <= i_wb_data;
        end
    end

    // Set num_acks and num_reqs when IDLE and then decrement to zero when a transaction is ongoing
    // Increment the ack_idx every cycle a new acknowledgement is recieved
    // Increment the req_idx every cycle a new request is sent
    always_ff @(posedge i_wb_clk) begin
        num_acks    <= state_in_idle ? biu_req_size_t'(`DC_LINE_WIDTH/`WB_DATA_WIDTH) : num_acks - biu_req_size_t'(i_wb_ack);
        num_reqs    <= state_in_idle ? biu_req_size_t'((`DC_LINE_WIDTH/`WB_DATA_WIDTH)-1) : num_reqs - biu_req_size_t'(requesting);
        ack_idx     <= state_in_idle ? {{($clog2(`DC_LINE_WIDTH/`WB_DATA_WIDTH)+1){1'b0}}} : ack_idx + biu_req_size_t'(i_wb_ack);
        req_idx     <= state_in_idle ? {{($clog2(`DC_LINE_WIDTH/`WB_DATA_WIDTH)+1){1'b0}}} : req_idx + biu_req_size_t'(requesting);
        addr_offset <= state_in_idle ? {{($clog2(`DC_LINE_WIDTH/`WB_DATA_WIDTH)+1){1'b0}}} : requesting ? addr_offset + (`WB_DATA_WIDTH/8) : addr_offset;
    end

    always_ff @(posedge i_wb_clk) begin
        if (i_wb_rst) state_q <= IDLE;
        else          state_q <= next_state;
    end

endmodule
