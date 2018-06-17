// Load Queue
// Every cycle a new load op may be allocated in the load queue when issued
// from the reservation station
// Every cycle a load may be deallocated from the load queue when retired from
// the ROB
// The purpose of the load queue is to keep track of load ops until they are
// retired and to detect mis-speculated loads whenever a store op has been retired

`include "common.svh"
import procyon_types::*;

module lsu_lq (
    input  logic                 clk,
    input  logic                 n_rst,

    input  logic                 i_flush,
    output logic                 o_full,

    // Signals from LSU_ID to allocate new load op
    input  procyon_tag_t         i_alloc_tag,
    input  procyon_addr_t        i_alloc_addr,
    input  procyon_lsu_func_t    i_alloc_lsu_func,
    input  logic                 i_alloc_en,

    // Signals to LSU_EX for replaying loads
    input  logic                 i_replay_stall,
    output logic                 o_replay_en,
    output procyon_lsu_func_t    o_replay_lsu_func,
    output procyon_addr_t        o_replay_addr,
    output procyon_tag_t         o_replay_tag,

    // Signals from LSU_EX to update a load when it needs replaying
    input  logic                 i_update_lq_en,
    input  logic                 i_update_lq_retry,
    input  procyon_mhq_tag_t     i_update_lq_mhq_tag,

    // MHQ fill broadcast
    input  logic                 i_mhq_fill,
    input  procyon_mhq_tag_t     i_mhq_fill_tag,

    // SQ will send address of retiring store for mis-speculation detection
    input  procyon_addr_t        i_sq_retire_addr,
    input  procyon_lsu_func_t    i_sq_retire_lsu_func,
    input  logic                 i_sq_retire_en,

    // ROB signal that a load has been retired
    input  procyon_tag_t         i_rob_retire_tag,
    input  logic                 i_rob_retire_en,
    output logic                 o_rob_retire_misspeculated
);

    // Each entry in the LQ contains the following
    // addr:              The load address
    // tag:               ROB tag used to determine age of the load op
    // lsu_func:          LSU op i.e. LB, LH, LW, LBU, LHU
    // valid:             Indicates if entry is valid
    // needs_replay:      Loads need to be replayed if they miss in the cache
    // replay_rdy:        Indicates that load is ready to be replayed
    // replay_retry:      Indicates if load was marked as needing to be replayed when the MHQ was full
    // replay_mhq_tag:    MHQ entry which corresponds to the cacheline that this load is waiting for
    // misspeculated:     Indicates if load has been mis-speculatively executed
    typedef struct packed {
        procyon_addr_t           addr;
        procyon_tag_t            tag;
        procyon_lsu_func_t       lsu_func;
        logic                    valid;
        logic                    needs_replay;
        logic                    replay_rdy;
        logic                    replay_retry;
        procyon_mhq_tag_t        replay_mhq_tag;
        logic                    misspeculated;
    } lq_slot_t;

    typedef struct packed {
        logic                     full;
        logic     [`LQ_DEPTH-1:0] empty;
        logic     [`LQ_DEPTH-1:0] replay;
        logic     [`LQ_DEPTH-1:0] allocate_select;
        logic     [`LQ_DEPTH-1:0] misspeculated_select;
        logic     [`LQ_DEPTH-1:0] retire_select;
        logic     [`LQ_DEPTH-1:0] replay_select;
        logic     [`LQ_DEPTH-1:0] update_select;
    } lq_t;

/* verilator lint_off MULTIDRIVEN */
    lq_slot_t [`LQ_DEPTH-1:0]         lq_slots;
/* verilator lint_on  MULTIDRIVEN */
/* verilator lint_off UNOPTFLAT */
    lq_t                              lq;
/* verilator lint_on  UNOPTFLAT */
    logic                             allocating;
    logic                             retiring;
    logic                             updating;
    logic                             replaying;
    logic     [`LQ_TAG_WIDTH-1:0]     retire_slot;
    logic     [`LQ_TAG_WIDTH-1:0]     replay_slot;
    logic     [`LQ_DEPTH-1:0]         update_select_q;
    procyon_addr_t                    sq_retire_addr_start;
    procyon_addr_t                    sq_retire_addr_end;

    genvar gvar;
    generate
        // Use the ROB tag to determine which slot will be retired
        // by generating a retire_select one-hot bit vector
        for (gvar = 0; gvar < `LQ_DEPTH; gvar++) begin : ASSIGN_LQ_RETIRE_VECTORS
            // Only one valid slot should have the matching tag
            assign lq.retire_select[gvar] = (lq_slots[gvar].tag == i_rob_retire_tag) && lq_slots[gvar].valid;
        end

        // Compare retired store address with all valid load addresses to detect mis-speculated loads
        for (gvar = 0; gvar < `LQ_DEPTH; gvar++) begin : ASSIGN_LQ_MISSPECULATED_LOAD_VECTORS
            assign lq.misspeculated_select[gvar] = ((lq_slots[gvar].addr >= sq_retire_addr_start) && (lq_slots[gvar].addr < sq_retire_addr_end));
        end

        for (gvar = 0; gvar < `LQ_DEPTH; gvar++) begin : ASSIGN_LQ_EMPTY_VECTORS
            // A slot is considered empty if it is marked as not valid
            assign lq.empty[gvar] = ~lq_slots[gvar].valid;
        end

        for (gvar = 0; gvar < `LQ_DEPTH; gvar++) begin : ASSIGN_LQ_REPLAY_VECTORS
            // A slot is considered replayable if it is marked as replay ready
            assign lq.replay[gvar] = lq_slots[gvar].replay_rdy;
        end
    endgenerate

    // Grab retired store address
    assign sq_retire_addr_start         = i_sq_retire_addr;

    // Produce a one-hot bit vector of the slot that will be used to allocate
    // the next load op. LQ is full if no bits are set in the empty vector
    assign lq.allocate_select           = lq.empty & ~(lq.empty - 1'b1);
    assign lq.full                      = ~|(lq.empty);
    assign allocating                   = ^(lq.allocate_select) && ~lq.full && i_alloc_en;

    // Let ROB know that retired load was mis-speculated
    // Bypass misspeculated signal if a store is retiring on the same cycle
    assign o_rob_retire_misspeculated   = lq_slots[retire_slot].misspeculated || (i_sq_retire_en && lq.misspeculated_select[retire_slot]);
    assign retiring                     = i_rob_retire_en;

    // Update only if lq is not empty and LSU_EX sends the update signal
    assign updating                     = ~&(lq.empty) && i_update_lq_en;
    assign lq.update_select             = update_select_q;

    // Replay loads if any loads are ready to be replayed
    // Make sure no stores are being retired during the same cycle
    assign lq.replay_select             = lq.replay & ~(lq.replay - 1'b1);
    assign replaying                    = |(lq.replay) && ~i_replay_stall;

    // Output replaying load
    assign o_replay_en                  = replaying;
    assign o_replay_lsu_func            = lq_slots[replay_slot].lsu_func;
    assign o_replay_addr                = lq_slots[replay_slot].addr;
    assign o_replay_tag                 = lq_slots[replay_slot].tag;

    // Ouput full signal
    assign o_full                       = lq.full;

    // Calculate retiring store end address based off of store type
    always_comb begin
        case (i_sq_retire_lsu_func)
            LSU_FUNC_SB: sq_retire_addr_end = i_sq_retire_addr + 32'b0001;
            LSU_FUNC_SH: sq_retire_addr_end = i_sq_retire_addr + 32'b0010;
            LSU_FUNC_SW: sq_retire_addr_end = i_sq_retire_addr + 32'b0100;
            default:     sq_retire_addr_end = i_sq_retire_addr + 32'b0100;
        endcase
    end

    // Convert one-hot retire_select vector into binary LQ slot #
    always_comb begin
        int r;
        r = 0;
        for (int i = 0; i < `LQ_DEPTH; i++) begin
            if (lq.retire_select[i]) begin
                r = r | i;
            end
        end
        retire_slot = r[`LQ_TAG_WIDTH-1:0];
    end

    // Convert one-hot replay_select vector into binary LQ slot #
    always_comb begin
        int r;
        r = 0;
        for (int i = 0; i < `LQ_DEPTH; i++) begin
            if (lq.replay_select[i]) begin
                r = r | i;
            end
        end
        replay_slot = r[`LQ_TAG_WIDTH-1:0];
    end

    // Register the update_select when a load is allocated or being replayed
    // This is used when LSU_EX needs to update LQ entry to mark a load as replayable
    always_ff @(posedge clk) begin
        if (replaying) begin
            update_select_q <= lq.replay_select;
        end else if (allocating) begin
            update_select_q <= lq.allocate_select;
        end
    end

    // Set the valid when a slot is allocated, clear on flush, reset or retire
    always_ff @(posedge clk, negedge n_rst) begin
        for (int i = 0; i < `LQ_DEPTH; i++) begin
            if (~n_rst) begin
                lq_slots[i].valid <= 1'b0;
            end else if (i_flush) begin
                lq_slots[i].valid <= 1'b0;
            end else if (allocating && lq.allocate_select[i]) begin
                lq_slots[i].valid <= 1'b1;
            end else if (retiring && lq.retire_select[i]) begin
                lq_slots[i].valid <= 1'b0;
            end
        end
    end

    // Update slot for newly allocated load op
    always_ff @(posedge clk) begin
        for (int i = 0; i < `LQ_DEPTH; i++) begin
            if (allocating && lq.allocate_select[i]) begin
                lq_slots[i].addr        <= i_alloc_addr;
                lq_slots[i].tag         <= i_alloc_tag;
                lq_slots[i].lsu_func    <= i_alloc_lsu_func;
            end
        end
    end

    // Update slot for loads that need to be replayed
    // Loads need to be replayed for two reasons:
    // 1. Cache miss where the loads will be replayed when the MHQ broadcasts
    // a fill with the matching MHQ tag that the load is waiting on
    // 2. Cache miss and the MHQ is full where the loads will be replayed on
    // any MHQ fill broadcast
    always_ff @(posedge clk) begin
        for (int i = 0; i < `LQ_DEPTH; i++) begin
            if (allocating && lq.allocate_select[i]) begin
                lq_slots[i].needs_replay <= 1'b0;
            end else if (updating && lq.update_select[i]) begin
                lq_slots[i].needs_replay <= 1'b1;
            end else if (replaying && lq.replay_select[i]) begin
                lq_slots[i].needs_replay <= 1'b0;
            end
        end
    end

    // Mark loads as replay_rdy if they need replaying and one of two conditions apply:
    // 1. If they need replaying due to a cache miss then confirm that the MHQ
    // fill tag matches the fill tag they are waiting on
    // 2. If they need replaying due to a cache miss while the MHQ is full
    // then mark replay_rdy on any fill broadcasted by the MHQ (i.e. when replay_retry is set)
    always_ff @(posedge clk) begin
        for (int i = 0; i < `LQ_DEPTH; i++) begin
            if (allocating && lq.allocate_select[i]) begin
                lq_slots[i].replay_rdy <= 1'b0;
            end else if (replaying && lq.replay_select[i]) begin
                lq_slots[i].replay_rdy <= 1'b0;
            end else if (i_mhq_fill && lq_slots[i].needs_replay) begin
                lq_slots[i].replay_rdy <= lq_slots[i].replay_retry || (i_mhq_fill_tag == lq_slots[i].replay_mhq_tag);
            end
        end
    end

    // Update the replay_retry and replay_mhq_tag fields when a load is
    // marked as needing to be replayed
    always_ff @(posedge clk) begin
        for (int i = 0; i < `LQ_DEPTH; i++) begin
            if (updating && lq.update_select[i]) begin
                lq_slots[i].replay_retry    <= i_update_lq_retry;
                lq_slots[i].replay_mhq_tag  <= i_update_lq_mhq_tag;
            end
        end
    end

    // Update mis-speculated bit for mis-speculated loads, only if the loads
    // don't need replaying (i.e. they didn't miss in the cache)
    always_ff @(posedge clk, negedge n_rst) begin
        for (int i = 0; i < `LQ_DEPTH; i++) begin
            if (~n_rst) begin
                lq_slots[i].misspeculated <= 1'b0;
            end else if (allocating && lq.allocate_select[i]) begin
                lq_slots[i].misspeculated <= 1'b0;
            end else if (updating && lq.update_select[i]) begin
                lq_slots[i].misspeculated <= 1'b0;
            end else if (i_sq_retire_en && ~lq_slots[i].needs_replay && lq.misspeculated_select[i]) begin
                lq_slots[i].misspeculated <= 1'b1;
            end
        end
    end

endmodule
