// Re-Order Buffer
// Every cycle a new entry may be allocated at the tail of the buffer
// Every cycle a ready entry from the head of the FIFO is committed to the register file
// This enforces instructions to complete in program order

`include "common.svh"
import procyon_types::*;

module reorder_buffer (
    input  logic             clk,
    input  logic             n_rst,

    // The redirect signal and addr/iaddr are used by the Fetch unit to jump to the redirect address
    // Used for branches, exception etc.
    output logic             o_redirect,
    output procyon_addr_t    o_redirect_addr,

    // Common Data Bus networks
    input  logic             i_cdb_en                [0:`CDB_DEPTH-1],
    input  logic             i_cdb_redirect          [0:`CDB_DEPTH-1],
    input  procyon_data_t    i_cdb_data              [0:`CDB_DEPTH-1],
    input  procyon_addr_t    i_cdb_addr              [0:`CDB_DEPTH-1],
    input  procyon_tag_t     i_cdb_tag               [0:`CDB_DEPTH-1],

    // Dispatcher <-> ROB interface to enqueue a new instruction and lookup
    // data/tags for source operands of newly enqueued instructions
    input  logic             i_rob_en,
    input  logic             i_rob_rdy,
    input  procyon_rob_op_t  i_rob_op,
    input  procyon_addr_t    i_rob_iaddr,
    input  procyon_addr_t    i_rob_addr,
    input  procyon_data_t    i_rob_data,
    input  procyon_reg_t     i_rob_rdest,
    input  procyon_reg_t     i_rob_rsrc              [0:1],
    output procyon_tag_t     o_rob_tag,
    output procyon_data_t    o_rob_src_data          [0:1],
    output procyon_tag_t     o_rob_src_tag           [0:1],
    output logic             o_rob_src_rdy           [0:1],
    output logic             o_rob_stall,

    // Interface to register map to update destination register for retired instruction
    output procyon_data_t    o_regmap_retire_data,
    output procyon_reg_t     o_regmap_retire_rdest,
    output procyon_tag_t     o_regmap_retire_tag,
    output logic             o_regmap_retire_wr_en,

    // Interface to register map to update tag information of the destination register of the
    // newly enqueued instruction
    output procyon_tag_t     o_regmap_rename_tag,
    output procyon_reg_t     o_regmap_rename_rdest,
    output logic             o_regmap_rename_wr_en,

    // Interface to register map to lookeup src register data/tags/rdy for newly enqueued instructions
    input  logic             i_regmap_lookup_rdy     [0:1],
    input  procyon_tag_t     i_regmap_lookup_tag     [0:1],
    input  procyon_data_t    i_regmap_lookup_data    [0:1],
    output procyon_reg_t     o_regmap_lookup_rsrc    [0:1],

    // Interface to LSU to retire loads/stores
    input  logic             i_lsu_retire_misspeculated,
    input  logic             i_lsu_retire_launched,
    output logic             o_lsu_retire_lq_en,
    output logic             o_lsu_retire_sq_en,
    output procyon_tag_t     o_lsu_retire_tag
);

    typedef logic [`ROB_DEPTH-1:0] rob_vec_t;

    // ROB entry consists of the following:
    // rdy:      Is the data valid/ready?
    // redirect: Asserted by branches or instructions that cause exceptions
    // op:       What operation is the instruction doing?
    // iaddr:    Address of the instruction (to rollback on exception)
    // addr:     Destination address for branch
    // data:     The data for the destination register
    // rdest:    The destination register
    typedef struct packed {
        logic                            rdy;
        logic                            redirect;
        procyon_rob_op_t                 op;
        procyon_addr_t                   iaddr;
        procyon_addr_t                   addr;
        procyon_data_t                   data;
        procyon_reg_t                    rdest;
    } rob_entry_t;

/* verilator lint_off MULTIDRIVEN */
    rob_entry_t     [`ROB_DEPTH-1:0]     rob_entries;
/* verilator lint_on  MULTIDRIVEN */
    procyon_tagp_t                       rob_head;
    procyon_tagp_t                       rob_tail;
    // It's convenient to add an extra bit for the head and tail pointers so that they may wrap around and allow for easier queue full/empty detection
    procyon_tag_t                        rob_head_addr;
    procyon_tag_t                        rob_tail_addr;
    logic                                rob_full;
    logic                                rob_empty;
    logic                                redirect;
    logic                                rob_dispatch_en;
    logic                                rob_retire_is_load;
    logic                                rob_retire_is_store;
    logic                                rob_retire_load_stall;
    logic                                rob_retire_en;
    logic                                lsu_retire_misspeculated;
    rob_vec_t                            rob_dispatch_select;
    rob_vec_t                            cdb_tag_select [0:`CDB_DEPTH-1];
    logic          [1:0]                 cdb_lookup_bypass [0:`CDB_DEPTH-1];
    rob_vec_t                            dispatch_en;
    rob_vec_t                            rob_entries_redirect;
    rob_vec_t                            rob_entries_rdy;
    procyon_addr_t [`ROB_DEPTH-1:0]      rob_entries_addr;
    procyon_data_t [`ROB_DEPTH-1:0]      rob_entries_data;
    procyon_data_t                       rob_src_data [0:1];
    procyon_tag_t                        rob_src_tag  [0:1];
    logic                                rob_src_rdy  [0:1];

    assign dispatch_en                   = {(`ROB_DEPTH){rob_dispatch_en}} & rob_dispatch_select;
    assign rob_dispatch_select           = 1 << rob_tail_addr;
    assign rob_dispatch_en               = i_rob_en & ~rob_full;
    assign rob_retire_is_load            = (rob_entries[rob_head_addr].op == ROB_OP_LD);
    assign rob_retire_is_store           = (rob_entries[rob_head_addr].op == ROB_OP_ST);
    assign rob_retire_load_stall         = rob_retire_is_load & i_lsu_retire_launched;
    assign rob_retire_en                 = rob_entries[rob_head_addr].rdy & ~rob_empty & ~rob_retire_load_stall;

    // If the instruction to be retired generated a branch and it is ready then assert the redirect signal
    assign lsu_retire_misspeculated      = i_lsu_retire_misspeculated & (rob_entries[rob_head_addr].op == ROB_OP_LD);
    assign redirect                      = rob_retire_en & (rob_entries[rob_head_addr].redirect | lsu_retire_misspeculated);
    assign o_redirect                    = redirect;
    assign o_redirect_addr               = (rob_entries[rob_head_addr].op == ROB_OP_BR) ? rob_entries[rob_head_addr].addr : rob_entries[rob_head_addr].iaddr;

    assign rob_tail_addr                 = rob_tail[`TAG_WIDTH-1:0];
    assign rob_head_addr                 = rob_head[`TAG_WIDTH-1:0];
    assign rob_full                      = ({~rob_tail[`TAG_WIDTH], rob_tail[`TAG_WIDTH-1:0]} == rob_head);
    assign rob_empty                     = (rob_tail == rob_head);

    // Assign outputs to regmap
    assign o_regmap_retire_data          = rob_entries[rob_head_addr].data;
    assign o_regmap_retire_rdest         = rob_entries[rob_head_addr].rdest;
    assign o_regmap_retire_tag           = rob_head_addr;
    assign o_regmap_retire_wr_en         = rob_retire_en;

    assign o_regmap_rename_tag           = rob_tail_addr;
    assign o_regmap_rename_rdest         = i_rob_rdest;
    assign o_regmap_rename_wr_en         = rob_dispatch_en;

    // Assign outputs to dispatcher
    // Stall if the ROB is full
    assign o_rob_stall                   = rob_full;
    assign o_rob_tag                     = rob_tail_addr;
    assign o_rob_src_data                = rob_src_data;
    assign o_rob_src_tag                 = rob_src_tag;
    assign o_rob_src_rdy                 = rob_src_rdy;

    // Assign outputs to LSU
    assign o_lsu_retire_tag              = rob_head_addr;
    assign o_lsu_retire_sq_en            = rob_retire_is_store & rob_retire_en;
    assign o_lsu_retire_lq_en            = rob_retire_is_load & rob_retire_en;

    // Lookup source data from register map
    assign o_regmap_lookup_rsrc          = i_rob_rsrc;

    // Check if we need to bypass source data from the CDB when dispatching a new instruction
    // But only if the register map does not have up to date data
    always_comb begin
        for (int cdb_idx = 0; cdb_idx < `CDB_DEPTH; cdb_idx++) begin
            for (int src_idx = 0; src_idx < 2; src_idx++) begin
                cdb_lookup_bypass[cdb_idx][src_idx] = ~i_regmap_lookup_rdy[src_idx] & i_cdb_en[cdb_idx] & (i_cdb_tag[cdb_idx] == i_regmap_lookup_tag[src_idx]);
            end
        end
    end

    // Getting the right source register tags/data is tricky. If the register map has ready data then that must be used
    // Otherwise the ROB entry corresponding to the tag in the register map for the source register is looked up and the data,
    // if available, is retrieved from that entry. If it's not available then the instruction must wait for the tag to be broadcast
    // on the CDB. Now if there is something available on the CDB in the same cycle and it matches the tag from the register map,
    // then that value must be used over the ROB data.
    always_comb begin
        for (int src_idx = 0; src_idx < 2; src_idx++) begin
            rob_src_rdy[src_idx]  = i_regmap_lookup_rdy[src_idx] | rob_entries[i_regmap_lookup_tag[src_idx]].rdy;

            for (int cdb_idx = 0; cdb_idx < `CDB_DEPTH; cdb_idx++) begin
                rob_src_rdy[src_idx] = cdb_lookup_bypass[cdb_idx][src_idx] | rob_src_rdy[src_idx];
            end
        end
    end

    always_comb begin
        for (int src_idx = 0; src_idx < 2; src_idx++) begin
            rob_src_data[src_idx] = i_regmap_lookup_rdy[src_idx] ? i_regmap_lookup_data[src_idx] : rob_entries[i_regmap_lookup_tag[src_idx]].data;
            rob_src_tag[src_idx]  = i_regmap_lookup_tag[src_idx];

            for (int cdb_idx = 0; cdb_idx < `CDB_DEPTH; cdb_idx++) begin
                if (cdb_lookup_bypass[cdb_idx][src_idx]) begin
                    rob_src_data[src_idx] = i_cdb_data[cdb_idx];
                    rob_src_tag[src_idx]  = i_cdb_tag[cdb_idx];
                end
             end
        end
    end

    // Generate enable bits for each CDB for each ROB entry when updating entry due to CDB broadcast
    always_comb begin
        for (int i = 0; i < `CDB_DEPTH; i++) begin
            cdb_tag_select[i] = {(`ROB_DEPTH){i_cdb_en[i]}} & (1 << i_cdb_tag[i]);
        end
    end

    // Set the redirect bit for an entry if the CDB broadcast asserts the redirect signal
    // Set the rdy bit if any of the CDB busses broadcasts a valid ROB tag
    always_comb begin
        for (int rob_idx = 0; rob_idx < `ROB_DEPTH; rob_idx++) begin
            rob_entries_redirect[rob_idx] = rob_entries[rob_idx].redirect;
            rob_entries_rdy[rob_idx]      = rob_entries[rob_idx].rdy;

            for (int cdb_idx = 0; cdb_idx < `CDB_DEPTH; cdb_idx++) begin
                rob_entries_redirect[rob_idx] = (cdb_tag_select[cdb_idx][rob_idx] & i_cdb_redirect[cdb_idx]) | rob_entries_redirect[rob_idx];
                rob_entries_rdy[rob_idx]      = cdb_tag_select[cdb_idx][rob_idx] | rob_entries_rdy[rob_idx];
            end
        end
    end

    // Priority mux the CDB address and data for each entry
    always_comb begin
        for (int rob_idx = 0; rob_idx < `ROB_DEPTH; rob_idx++) begin
            rob_entries_addr[rob_idx] = rob_entries[rob_idx].addr;
            rob_entries_data[rob_idx] = rob_entries[rob_idx].data;

            for (int cdb_idx = 0; cdb_idx < `CDB_DEPTH; cdb_idx++) begin
                if (cdb_tag_select[cdb_idx][rob_idx]) begin
                    rob_entries_addr[rob_idx] = i_cdb_addr[cdb_idx];
                    rob_entries_data[rob_idx] = i_cdb_data[cdb_idx];
                end
            end
        end
    end

    // Now update the ROB entry with the newly dispatched instruction Or with the data broadcast over the CDB
    always_ff @(posedge clk) begin
        for (int i = 0; i < `ROB_DEPTH; i++) begin
            rob_entries[i].redirect <= ~dispatch_en[i] & rob_entries_redirect[i];
            rob_entries[i].addr     <= dispatch_en[i] ? i_rob_addr  : rob_entries_addr[i];
            rob_entries[i].data     <= dispatch_en[i] ? i_rob_data  : rob_entries_data[i];
            rob_entries[i].op       <= dispatch_en[i] ? i_rob_op    : rob_entries[i].op;
            rob_entries[i].iaddr    <= dispatch_en[i] ? i_rob_iaddr : rob_entries[i].iaddr;;
            rob_entries[i].rdest    <= dispatch_en[i] ? i_rob_rdest : rob_entries[i].rdest;
        end
    end

    // Clear the ready bits on a flush or reset
    always_ff @(posedge clk) begin
        for (int i = 0; i < `ROB_DEPTH; i++) begin
            if (~n_rst) rob_entries[i].rdy <= 1'b0;
            else        rob_entries[i].rdy <= mux4_1b(rob_entries_rdy[i], i_rob_rdy, 1'b0, 1'b0, {redirect, dispatch_en[i]});
        end
    end

    // Increment the tail pointer if the dispatcher signals a new instruction to be enqueued
    // and the ROB is not full. Reset if redirect asserted
    always_ff @(posedge clk) begin
        if (~n_rst) rob_tail <= {(`TAG_WIDTH+1){1'b0}};
        else        rob_tail <= redirect ? {(`TAG_WIDTH+1){1'b0}} : rob_dispatch_en ? rob_tail + 1'b1 : rob_tail;
    end

    // Increment the head pointer if the instruction to be retired is ready and the ROB is not
    // empty (of course this should never be the case). Reset if redirect asserted
    always_ff @(posedge clk) begin
        if (~n_rst) rob_head <= {(`TAG_WIDTH+1){1'b0}};
        else        rob_head <= redirect ? {(`TAG_WIDTH+1){1'b0}} : rob_retire_en ? rob_head + 1'b1 : rob_head;
    end

endmodule
