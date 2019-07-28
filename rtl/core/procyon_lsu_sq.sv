// Store Queue
// Every cycle a new store op may be allocated in the store queue when issued from the reservation station
// Every cycle a store may be launched to memory from the store queue after being retired from the ROB
// The purpose of the store queue is to keep track of store ops and commit them to memory in program order
// and to detect mis-speculated loads in the load queue

`include "procyon_constants.svh"

module procyon_lsu_sq #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_SQ_DEPTH      = 8,
    parameter OPTN_ROB_IDX_WIDTH = 5
)(
    input  logic                            clk,
    input  logic                            n_rst,

    input  logic                            i_flush,
    output logic                            o_full,

    // Signals from LSU_ID to allocate new store op in SQ
    input  logic                            i_alloc_en,
    input  logic [`PCYN_LSU_FUNC_WIDTH-1:0] i_alloc_lsu_func,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]   i_alloc_tag,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_alloc_addr,
    input  logic [OPTN_DATA_WIDTH-1:0]      i_alloc_data,

    // Send out store to LSU on retirement and to the load queue for
    // detection of mis-speculated loads
    input  logic                            i_sq_retire_stall,
    output logic                            o_sq_retire_en,
    output logic [OPTN_SQ_DEPTH-1:0]        o_sq_retire_select,
    output logic [`PCYN_LSU_FUNC_WIDTH-1:0] o_sq_retire_lsu_func,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_sq_retire_addr,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]   o_sq_retire_tag,
    output logic [OPTN_DATA_WIDTH-1:0]      o_sq_retire_data,

    // Signals from the LSU and MHQ to indicate if the last retiring store needs to be retried
    input  logic                            i_update_en,
    input  logic [OPTN_SQ_DEPTH-1:0]        i_update_select,
    input  logic                            i_update_retry,
    input  logic                            i_update_mhq_retry,

    // MHQ fill interface for waking up waiting stores
    input  logic                            i_mhq_fill_en,

    // ROB signal that a store has been retired
    input  logic                            i_rob_retire_en,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]   i_rob_retire_tag,
    output logic                            o_rob_retire_ack
);

    // Each SQ entry is in one of the following states:
    // INVALID:        Slot is empty
    // VALID:          Slot contains a valid but not retired store operation
    // MHQ_FILL_WAIT:  Slot contains a store op that is waiting for an MHQ fill broadcast
    // NONSPECULATIVE: Slot contains a store that is at the head of the ROB and thus is ready to be retired
    // LAUNCHED:       Slot contains a retired store that has been launched into the LSU pipeline
    //                 It must wait in this state until the LSU indicates if it was retired successfully or if it needs to be relaunched
    localparam SQ_IDX_WIDTH            = $clog2(OPTN_SQ_DEPTH);
    localparam SQ_STATE_WIDTH          = 3;
    localparam SQ_STATE_INVALID        = 3'b000;
    localparam SQ_STATE_VALID          = 3'b001;
    localparam SQ_STATE_MHQ_FILL_WAIT  = 3'b010;
    localparam SQ_STATE_NONSPECULATIVE = 3'b011;
    localparam SQ_STATE_LAUNCHED       = 3'b100;

    // Each SQ entry contains:
    // lsu_func:        Indicates type of store op (SB, SH, SW)
    // addr:            Store address updated in ID stage
    // data:            Store data updated in ID stage
    // tag:             Destination tag in ROB (used for age comparison for store-to-load forwarding)
    // state:           Current state of the entry
    logic [`PCYN_LSU_FUNC_WIDTH-1:0] sq_entry_lsu_func_q [0:OPTN_SQ_DEPTH-1];
    logic [OPTN_ADDR_WIDTH-1:0]      sq_entry_addr_q     [0:OPTN_SQ_DEPTH-1];
    logic [OPTN_DATA_WIDTH-1:0]      sq_entry_data_q     [0:OPTN_SQ_DEPTH-1];
    logic [OPTN_ROB_IDX_WIDTH-1:0]   sq_entry_tag_q      [0:OPTN_SQ_DEPTH-1];
    logic [SQ_STATE_WIDTH-1:0]       sq_entry_state_q    [0:OPTN_SQ_DEPTH-1];

    logic [SQ_STATE_WIDTH-1:0]       sq_entry_state_next [0:OPTN_SQ_DEPTH-1];
    logic                            sq_full;
    logic [OPTN_SQ_DEPTH-1:0]        sq_empty;
    logic [OPTN_SQ_DEPTH-1:0]        sq_retirable;
    logic [OPTN_SQ_DEPTH-1:0]        sq_rob_tag_match;
    logic [OPTN_SQ_DEPTH-1:0]        sq_allocate_select;
    logic [OPTN_SQ_DEPTH-1:0]        sq_rob_select;
    logic [OPTN_SQ_DEPTH-1:0]        sq_update_select;
    logic [OPTN_SQ_DEPTH-1:0]        sq_retire_select;
    logic [SQ_IDX_WIDTH-1:0]         sq_retire_entry;
    logic                            sq_retire_en;
    logic                            sq_retire_ack;

    assign sq_allocate_select = {(OPTN_SQ_DEPTH){i_alloc_en}} & (sq_empty & ~(sq_empty - 1'b1));
    assign sq_rob_select      = {(OPTN_SQ_DEPTH){i_rob_retire_en}} & sq_rob_tag_match;
    assign sq_retire_select   = {(OPTN_SQ_DEPTH){~i_sq_retire_stall}} & (sq_retirable & ~(sq_retirable - 1'b1));
    assign sq_update_select   = {(OPTN_SQ_DEPTH){i_update_en}} & i_update_select;

    assign sq_retire_en       = sq_retire_select != {(OPTN_SQ_DEPTH){1'b0}};
    assign sq_retire_ack      = i_rob_retire_en & sq_retire_en & (sq_entry_tag_q[sq_retire_entry] == i_rob_retire_tag);

    // Output full signal
    // FIXME: Can this be registered?
    assign sq_full                          = ((sq_empty & ~sq_allocate_select) == {(OPTN_SQ_DEPTH){1'b0}});
    assign o_full                           = sq_full;

    always_comb begin
        for (int i = 0; i < OPTN_SQ_DEPTH; i++) begin
            // A entry is ready to be retired if it is non-speculative
            sq_retirable[i]     = (sq_entry_state_q[i] == SQ_STATE_NONSPECULATIVE);

            // Match the ROB retire tag with an entry to determine which entry should be marked nonspeculative (i.e. retirable)
            // Only one valid entry should have the matching tag
            sq_rob_tag_match[i] = (sq_entry_tag_q[i] == i_rob_retire_tag);

            // A entry is considered empty if it is invalid
            sq_empty[i]         = (sq_entry_state_q[i] == SQ_STATE_INVALID);
        end
    end

    // Update state for each SQ entry
    always_comb begin
        logic [SQ_STATE_WIDTH-1:0] sq_fill_bypass_mux;
        logic [SQ_STATE_WIDTH-1:0] sq_update_state_mux;

        // Bypass fill broadcast if an update comes through on the same cycle as the fill
        sq_fill_bypass_mux  = i_mhq_fill_en ? SQ_STATE_NONSPECULATIVE : SQ_STATE_MHQ_FILL_WAIT;
        sq_update_state_mux = (i_update_retry & i_update_mhq_retry) ? sq_fill_bypass_mux : SQ_STATE_INVALID;

        for (int i = 0; i < OPTN_SQ_DEPTH; i++) begin
            sq_entry_state_next[i] = sq_entry_state_q[i];
            case (sq_entry_state_next[i])
                SQ_STATE_INVALID:        sq_entry_state_next[i] = sq_allocate_select[i] ? SQ_STATE_VALID : sq_entry_state_next[i];
                SQ_STATE_VALID:          sq_entry_state_next[i] = i_flush ? SQ_STATE_INVALID : (sq_rob_select[i] ? SQ_STATE_NONSPECULATIVE : sq_entry_state_next[i]);
                SQ_STATE_MHQ_FILL_WAIT:  sq_entry_state_next[i] = i_mhq_fill_en ? SQ_STATE_NONSPECULATIVE : sq_entry_state_next[i];
                SQ_STATE_NONSPECULATIVE: sq_entry_state_next[i] = sq_retire_select[i] ? SQ_STATE_LAUNCHED : sq_entry_state_next[i];
                SQ_STATE_LAUNCHED:       sq_entry_state_next[i] = sq_update_select[i] ? sq_update_state_mux : sq_entry_state_next[i];
                default:                 sq_entry_state_next[i] = SQ_STATE_INVALID;
            endcase
        end
    end

    // Convert one-hot retire_select vector into binary SQ entry #
    always_comb begin
        sq_retire_entry = {($clog2(OPTN_SQ_DEPTH)){1'b0}};
        for (int i = 0; i < OPTN_SQ_DEPTH; i++) begin
            if (sq_retire_select[i]) begin
                sq_retire_entry = SQ_IDX_WIDTH'(i);
            end
        end
    end

    // Send ack back to ROB when launching the retired store
    always_ff @(posedge clk) begin
        if (~n_rst) o_rob_retire_ack <= 1'b0;
        else        o_rob_retire_ack <= sq_retire_ack;
    end

    // Retire stores to D$ or to the MHQ if it misses in the cache
    // The retiring store address and type and sq_retire_en signals is also sent to the LQ for possible load bypass violation detection
    always_ff @(posedge clk) begin
        if (~n_rst || i_flush)       o_sq_retire_en <= 1'b0;
        else if (~i_sq_retire_stall) o_sq_retire_en <= sq_retire_en;
    end

    always_ff @(posedge clk) begin
        if (~i_sq_retire_stall) begin
            o_sq_retire_data     <= sq_entry_data_q[sq_retire_entry];
            o_sq_retire_addr     <= sq_entry_addr_q[sq_retire_entry];
            o_sq_retire_tag      <= sq_entry_tag_q[sq_retire_entry];
            o_sq_retire_lsu_func <= sq_entry_lsu_func_q[sq_retire_entry];
            o_sq_retire_select   <= sq_retire_select;
        end
    end

    // Update entry for newly allocated store op
    always_ff @(posedge clk) begin
        for (int i = 0; i < OPTN_SQ_DEPTH; i++) begin
            if (~n_rst) sq_entry_state_q[i] <= SQ_STATE_INVALID;
            else        sq_entry_state_q[i] <= sq_entry_state_next[i];
        end
    end

    always_ff @(posedge clk) begin
        for (int i = 0; i < OPTN_SQ_DEPTH; i++) begin
            if (sq_allocate_select[i] & (sq_entry_state_q[i] == SQ_STATE_INVALID)) begin
                sq_entry_data_q[i]       <= i_alloc_data;
                sq_entry_addr_q[i]       <= i_alloc_addr;
                sq_entry_lsu_func_q[i]   <= i_alloc_lsu_func;
                sq_entry_tag_q[i]        <= i_alloc_tag;
            end
        end
    end

endmodule
