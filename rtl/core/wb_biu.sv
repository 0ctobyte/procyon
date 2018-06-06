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

    state_t              state;
    state_t              state_q;
    biu_req_size_t       num_reqs;
    biu_req_size_t       num_acks;
    biu_req_size_t       req_idx;
    biu_req_size_t       ack_idx;
    biu_req_size_t       addr_offset;
    wb_data_t            next_data;
    procyon_cacheline_t  biu_data;
    logic                in_progress;

    assign in_progress     = (state_q == REQS) || (state_q == ACKS);

    // Output to CCU
    assign o_biu_data      = biu_data;
    assign o_biu_done      = (state_q == DONE);
    assign o_biu_busy      = in_progress;

    // Output to Wishbone interface
    assign o_wb_cyc        = in_progress;
    assign o_wb_stb        = (state_q == REQS);
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
            IDLE: state = i_biu_en ? REQS : IDLE;
            REQS: state = (num_reqs == 0) ? ACKS : REQS;
            ACKS: state = (num_acks == 0) ? DONE : ACKS;
            DONE: state = ~i_biu_en ? IDLE : DONE;
        endcase
    end

    // Grab data from the Wishbone interface
    always_ff @(posedge i_wb_clk) begin
        if (i_wb_ack && (|num_acks)) begin
            biu_data[ack_idx*(`WB_DATA_WIDTH) +: (`WB_DATA_WIDTH)] <= i_wb_data;
        end
    end

    // Increment the req_idx every cycle a new request is sent
    always_ff @(posedge i_wb_clk) begin
        if (state_q == IDLE) begin
            req_idx     <= {{($clog2(`DC_LINE_WIDTH/`WB_DATA_WIDTH)+1){1'b0}}};
            addr_offset <= {{($clog2(`DC_LINE_WIDTH/`WB_DATA_WIDTH)+1){1'b0}}};
        end else if (state_q == REQS && ~i_wb_stall) begin
            req_idx     <= req_idx + 1'b1;
            addr_offset <= addr_offset + (`WB_DATA_WIDTH/8);
        end
    end

    // Set num_acks and num_reqs when IDLE and then decrement to zero when
    // a transaction is ongoing
    always_ff @(posedge i_wb_clk) begin
        if (state_q == IDLE) begin
/* verilator lint_off WIDTH */
            num_reqs <= (`DC_LINE_WIDTH/`WB_DATA_WIDTH)-1'b1;
/* verilator lint_on  WIDTH */
        end else if (state_q == REQS && ~i_wb_stall) begin
            num_reqs <= num_reqs - 1'b1;
        end
    end

    // Increment the ack_idx every cycle a new acknowledgement is recieved
    always_ff @(posedge i_wb_clk) begin
        if (state_q == IDLE) begin
            ack_idx  <= {{($clog2(`DC_LINE_WIDTH/`WB_DATA_WIDTH)+1){1'b0}}};
/* verilator lint_off WIDTH */
            num_acks <= (`DC_LINE_WIDTH/`WB_DATA_WIDTH);
/* verilator lint_on  WIDTH */
        end else if (i_wb_ack) begin
            ack_idx  <= ack_idx + 1'b1;
            num_acks <= num_acks - 1'b1;
        end
    end

    always_ff @(posedge i_wb_clk, posedge i_wb_rst) begin
        if (i_wb_rst) begin
            state_q <= IDLE;
        end else begin
            state_q <= state;
        end
    end

endmodule
