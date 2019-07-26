// Wishbone Bus Interface Unit
// This module is the interface to the Wishbone Bus
// All transactions from the CPU will go through here

module wb_biu #(
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_WB_DATA_WIDTH = 16,
    parameter OPTN_WB_ADDR_WIDTH = 32,
    parameter OPTN_DC_LINE_SIZE  = 32,

    parameter WB_WORD_SIZE       = OPTN_WB_DATA_WIDTH / 8,
    parameter DC_LINE_WIDTH      = OPTN_DC_LINE_SIZE * 8
)(
    // Wishbone interface
    input  logic                          i_wb_clk,
    input  logic                          i_wb_rst,
    input  logic                          i_wb_ack,
    input  logic                          i_wb_stall,
    input  logic [OPTN_WB_DATA_WIDTH-1:0] i_wb_data,
    output logic                          o_wb_cyc,
    output logic                          o_wb_stb,
    output logic                          o_wb_we,
    output logic [WB_WORD_SIZE-1:0]       o_wb_sel,
    output logic [OPTN_WB_ADDR_WIDTH-1:0] o_wb_addr,
    output logic [OPTN_WB_DATA_WIDTH-1:0] o_wb_data,

    // CCU interface
    input  logic                          i_biu_en,
    input  logic                          i_biu_we,
    input  logic [OPTN_ADDR_WIDTH-1:0]    i_biu_addr,
    input  logic [DC_LINE_WIDTH-1:0]      i_biu_data,
    output logic [DC_LINE_WIDTH-1:0]      o_biu_data,
    output logic                          o_biu_busy,
    output logic                          o_biu_done
);

    localparam BIU_REQ_COUNT       = DC_LINE_WIDTH / OPTN_WB_DATA_WIDTH;
    localparam BIU_REQ_COUNT_WIDTH = $clog2(BIU_REQ_COUNT);
    localparam BIU_STATE_WIDTH     = 2;
    localparam BIU_STATE_IDLE      = 2'b00;
    localparam BIU_STATE_REQS      = 2'b01;
    localparam BIU_STATE_ACKS      = 2'b10;
    localparam BIU_STATE_DONE      = 2'b11;

    logic [BIU_STATE_WIDTH-1:0]    next_state;
    logic [BIU_STATE_WIDTH-1:0]    state_q;
    logic [BIU_REQ_COUNT_WIDTH:0]  num_reqs;
    logic [BIU_REQ_COUNT_WIDTH:0]  num_acks;
    logic [BIU_REQ_COUNT_WIDTH:0]  req_idx;
    logic [BIU_REQ_COUNT_WIDTH:0]  ack_idx;
    logic [BIU_REQ_COUNT_WIDTH:0]  addr_offset;
    logic [OPTN_WB_DATA_WIDTH-1:0] next_data;
    logic [DC_LINE_WIDTH-1:0]      biu_data;
    logic                          in_progress;
    logic                          state_in_reqs;
    logic                          state_in_idle;
    logic                          requesting;

    assign state_in_idle = state_q == BIU_STATE_IDLE;
    assign state_in_reqs = state_q == BIU_STATE_REQS;
    assign in_progress   = state_in_reqs | (state_q == BIU_STATE_ACKS);
    assign requesting    = state_in_reqs & ~i_wb_stall;

    // Output to CCU
    assign o_biu_data    = biu_data;
    assign o_biu_done    = (state_q == BIU_STATE_DONE);
    assign o_biu_busy    = in_progress;

    // Output to Wishbone interface
    assign o_wb_cyc      = in_progress;
    assign o_wb_stb      = state_in_reqs;
    assign o_wb_we       = i_biu_we;
    assign o_wb_sel      = {{(OPTN_WB_DATA_WIDTH/8){1'b1}}};
    assign o_wb_addr     = i_biu_addr + {{(OPTN_WB_ADDR_WIDTH-BIU_REQ_COUNT_WIDTH-1){1'b0}}, addr_offset};
    assign o_wb_data     = next_data;

    // Select the next bits of data
    always_comb begin
        next_data = i_biu_data[req_idx*(OPTN_WB_DATA_WIDTH) +: (OPTN_WB_DATA_WIDTH)];
    end

    // Update state
    always_comb begin
        case (state_q)
            BIU_STATE_IDLE: next_state = i_biu_en ? BIU_STATE_REQS : BIU_STATE_IDLE;
            BIU_STATE_REQS: next_state = (num_reqs == 0) ? BIU_STATE_ACKS : BIU_STATE_REQS;
            BIU_STATE_ACKS: next_state = (num_acks == 0) ? BIU_STATE_DONE : BIU_STATE_ACKS;
            BIU_STATE_DONE: next_state = ~i_biu_en ? BIU_STATE_IDLE : BIU_STATE_DONE;
        endcase
    end

    // Grab data from the Wishbone interface
    always_ff @(posedge i_wb_clk) begin
        if (i_wb_ack & (|num_acks)) begin
            biu_data[ack_idx*(OPTN_WB_DATA_WIDTH) +: (OPTN_WB_DATA_WIDTH)] <= i_wb_data;
        end
    end

    // Set num_acks and num_reqs when BIU_STATE_IDLE and then decrement to zero when a transaction is ongoing
    // Increment the ack_idx every cycle a new acknowledgement is recieved
    // Increment the req_idx every cycle a new request is sent
    always_ff @(posedge i_wb_clk) begin
        num_acks    <= state_in_idle ? (BIU_REQ_COUNT_WIDTH+1)'(BIU_REQ_COUNT) : num_acks - (BIU_REQ_COUNT_WIDTH+1)'(i_wb_ack);
        num_reqs    <= state_in_idle ? (BIU_REQ_COUNT_WIDTH+1)'(BIU_REQ_COUNT-1) : num_reqs - (BIU_REQ_COUNT_WIDTH+1)'(requesting);
        ack_idx     <= state_in_idle ? {{(BIU_REQ_COUNT_WIDTH+1){1'b0}}} : ack_idx + BIU_REQ_COUNT_WIDTH'(i_wb_ack);
        req_idx     <= state_in_idle ? {{(BIU_REQ_COUNT_WIDTH+1){1'b0}}} : req_idx + BIU_REQ_COUNT_WIDTH'(requesting);
        addr_offset <= state_in_idle ? {{(BIU_REQ_COUNT_WIDTH+1){1'b0}}} : requesting ? addr_offset + (WB_WORD_SIZE) : addr_offset;
    end

    always_ff @(posedge i_wb_clk) begin
        if (i_wb_rst) state_q <= BIU_STATE_IDLE;
        else          state_q <= next_state;
    end

endmodule
