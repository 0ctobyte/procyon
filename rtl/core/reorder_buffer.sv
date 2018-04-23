// Re-Order Buffer
// Every cycle a new entry may be allocated at the tail of the buffer
// Every cycle a ready entry from the head of the FIFO is committed to the register file
// This enforces instructions to complete in program order

`include "common.svh"
import procyon_types::*;

/* verilator lint_off MULTIDRIVEN */
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
    input  logic             i_lsu_retire_stall,
    input  logic             i_lsu_retire_mis_speculated,
    output logic             o_lsu_retire_lq_en,
    output logic             o_lsu_retire_sq_en,
    output procyon_tag_t     o_lsu_retire_tag
);

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

    typedef struct packed {
        // It's convenient to add an extra bit for the head and tail pointers so that they may wrap around and allow for easier queue full/empty detection
        procyon_tag_t                    head_addr;
        procyon_tag_t                    tail_addr;
        logic                            full;
        logic                            empty;
    } rob_t;
 
    procyon_tagp_t               rob_head;
    procyon_tagp_t               rob_tail;
    rob_entry_t [`ROB_DEPTH-1:0] rob_entries;
    rob_t                        rob;
    logic                        redirect;
    logic                        rob_dispatch_en;
    logic                        rob_retire_rdy;
    logic                        rob_retire_en;
    logic                        lsu_retire_stall;
    logic                        lsu_retire_mis_speculated;
    logic       [`ROB_DEPTH-1:0] rob_dispatch_select;
    logic       [`ROB_DEPTH-1:0] cdb_tag_select [0:`CDB_DEPTH-1];

    assign rob_dispatch_select           = 1 << rob.tail_addr;

    assign rob_dispatch_en               = i_rob_en && ~rob.full;
    assign lsu_retire_stall              = i_lsu_retire_stall && (rob_entries[rob.head_addr].op == ROB_OP_ST);
    assign rob_retire_rdy                = rob_entries[rob.head_addr].rdy && ~rob.empty;
    assign rob_retire_en                 = rob_retire_rdy && ~lsu_retire_stall;

    // If the instruction to be retired generated a branch and it is ready then assert the redirect signal
    assign lsu_retire_mis_speculated     = i_lsu_retire_mis_speculated && (rob_entries[rob.head_addr].op == ROB_OP_LD);
    assign redirect                      = rob_retire_en && (rob_entries[rob.head_addr].redirect || lsu_retire_mis_speculated);
    assign o_redirect                    = redirect;
    assign o_redirect_addr               = (rob_entries[rob.head_addr].op == ROB_OP_BR) ? rob_entries[rob.head_addr].addr : rob_entries[rob.head_addr].iaddr;

    assign rob.tail_addr                 = rob_tail[`TAG_WIDTH-1:0];
    assign rob.head_addr                 = rob_head[`TAG_WIDTH-1:0];
    assign rob.full                      = ({~rob_tail[`TAG_WIDTH], rob_tail[`TAG_WIDTH-1:0]} == rob_head);
    assign rob.empty                     = (rob_tail == rob_head);

    // Assign outputs to regmap
    assign o_regmap_retire_data          = rob_entries[rob.head_addr].data;
    assign o_regmap_retire_rdest         = rob_entries[rob.head_addr].rdest;
    assign o_regmap_retire_tag           = rob.head_addr;
    assign o_regmap_retire_wr_en         = rob_retire_en;

    assign o_regmap_rename_tag           = rob.tail_addr;
    assign o_regmap_rename_rdest         = i_rob_rdest;
    assign o_regmap_rename_wr_en         = rob_dispatch_en;

    // Assign outputs to dispatcher
    // Stall if the ROB is full
    assign o_rob_stall                   = rob.full;
    assign o_rob_tag                     = rob.tail_addr;

    // Assign outputs to LSU
    assign o_lsu_retire_tag              = rob.head_addr;
    assign o_lsu_retire_sq_en            = (rob_entries[rob.head_addr].op == ROB_OP_ST) && rob_retire_rdy;
    assign o_lsu_retire_lq_en            = (rob_entries[rob.head_addr].op == ROB_OP_LD) && rob_retire_rdy;

    genvar gvar;
    generate
        for (gvar = 0; gvar < 2; gvar++) begin : ASSIGN_REGMAP_LOOKUP_RSRC
            assign o_regmap_lookup_rsrc[gvar] = i_rob_rsrc[gvar];
        end

        for (gvar = 0; gvar < `CDB_DEPTH; gvar++) begin : ASSIGN_CDB_SELECT_SIGNALS
            assign cdb_tag_select[gvar]       = 1 << i_cdb_tag[gvar];
        end
    endgenerate

    // Getting the right source register tags/data is tricky
    // If the register map has ready data then that must be used
    // Otherwise the ROB entry corresponding to the tag in the register map for the
    // source register is looked up and the data, if available, is retrieved from that
    // entry. If it's not available then the instruction must wait for the tag to be broadcast
    // on the CDB. Now if there is something available on the CDB in the same cycle and it
    // matches the tag from the register map, then that value must be used over the ROB data.
    always_comb begin
        for (int i = 0; i < 2; i++) begin
            {o_rob_src_data[i], o_rob_src_tag[i], o_rob_src_rdy[i]} = {rob_entries[i_regmap_lookup_tag[i]].data, i_regmap_lookup_tag[i], rob_entries[i_regmap_lookup_tag[i]].rdy};
            if (i_regmap_lookup_rdy[i]) begin
                {o_rob_src_data[i], o_rob_src_tag[i], o_rob_src_rdy[i]} = {i_regmap_lookup_data[i], i_regmap_lookup_tag[i], i_regmap_lookup_rdy[i]};
            end else begin
                for (int j = 0; j < `CDB_DEPTH; j++) begin
                    if (i_cdb_en[j] && (i_cdb_tag[j] == i_regmap_lookup_tag[i])) begin
                        {o_rob_src_data[i], o_rob_src_tag[i], o_rob_src_rdy[i]} = {i_cdb_data[j], i_cdb_tag[j], 1'b1};
                    end
                end
            end
        end
    end

    // Now update the ROB entry with the newly dispatched instruction
    // Or with the data broadcast over the CDB
    always_ff @(posedge clk) begin
        for (int i = 0; i < `ROB_DEPTH; i++) begin
            if (rob_dispatch_en && rob_dispatch_select[i]) begin
                {rob_entries[i].op, rob_entries[i].iaddr, rob_entries[i].rdest} <= {i_rob_op, i_rob_iaddr, i_rob_rdest};
            end
        end
    end

    always_ff @(posedge clk) begin
        for (int i = 0; i < `ROB_DEPTH; i++) begin
            if (rob_dispatch_en && rob_dispatch_select[i]) begin
                {rob_entries[i].redirect, rob_entries[i].addr, rob_entries[i].data} <= {1'b0, i_rob_addr, i_rob_data};
            end else begin
                for (int j = 0; j < `CDB_DEPTH; j++) begin
                    if (i_cdb_en[j] && cdb_tag_select[j][i]) begin
                        {rob_entries[i].redirect, rob_entries[i].addr, rob_entries[i].data} <= {i_cdb_redirect[j], i_cdb_addr[j], i_cdb_data[j]};
                    end
                end
            end
        end
    end

    // Clear the ready bits on a flush or reset
    always_ff @(posedge clk, negedge n_rst) begin
        for (int i = 0; i < `ROB_DEPTH; i++) begin
            if (~n_rst) begin
                rob_entries[i].rdy <= 1'b0;
            end else if (redirect) begin
                rob_entries[i].rdy <= 1'b0;
            end else if (rob_dispatch_en && rob_dispatch_select[i]) begin
                rob_entries[i].rdy <= i_rob_rdy;
            end else begin
                for (int j = 0; j < `CDB_DEPTH; j++) begin
                    if (i_cdb_en[j] && cdb_tag_select[j][i]) begin
                        rob_entries[i].rdy <= 1'b1;
                    end
                end
            end
        end
    end

    // Increment the tail pointer if the dispatcher signals a new instruction to be enqueued
    // and the ROB is not full. Reset if redirect asserted
    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            rob_tail <= 'b0;
        end else if (redirect) begin
            rob_tail <= 'b0;
        end else if (rob_dispatch_en) begin
            rob_tail <= rob_tail + 1'b1;
        end
    end

    // Increment the head pointer if the instruction to be retired is ready and the ROB is not
    // empty (of course this should never be the case). Reset if redirect asserted
    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            rob_head <= 'b0;
        end else if (redirect) begin
            rob_head <= 'b0;
        end else if (rob_retire_en) begin
            rob_head <= rob_head + 1'b1;
        end
    end

endmodule
/* verilator lint_on  MULTIDRIVEN */
