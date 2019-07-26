// Re-Order Buffer
// Every cycle a new entry may be allocated at the tail of the buffer
// Every cycle a ready entry from the head of the FIFO is committed to the register file
// This enforces instructions to complete in program order

`include "procyon_constants.svh"

module reorder_buffer #(
    parameter OPTN_DATA_WIDTH       = 32,
    parameter OPTN_ADDR_WIDTH       = 32,
    parameter OPTN_CDB_DEPTH        = 2,
    parameter OPTN_ROB_DEPTH        = 32,
    parameter OPTN_REGMAP_IDX_WIDTH = 5,

    parameter ROB_IDX_WIDTH         = $clog2(OPTN_ROB_DEPTH)
)(
    input  logic                              clk,
    input  logic                              n_rst,

    input  logic                              i_rs_stall,
    output logic                              o_rob_stall,

    // The redirect signal and addr/pc are used by the Fetch unit to jump to the redirect address
    // Used for branches, exception etc.
    output logic                              o_redirect,
    output logic [OPTN_ADDR_WIDTH-1:0]        o_redirect_addr,

    // Common Data Bus networks
    input  logic                              i_cdb_en              [0:OPTN_CDB_DEPTH-1],
    input  logic                              i_cdb_redirect        [0:OPTN_CDB_DEPTH-1],
    input  logic [OPTN_DATA_WIDTH-1:0]        i_cdb_data            [0:OPTN_CDB_DEPTH-1],
    input  logic [OPTN_ADDR_WIDTH-1:0]        i_cdb_addr            [0:OPTN_CDB_DEPTH-1],
    input  logic [ROB_IDX_WIDTH-1:0]          i_cdb_tag             [0:OPTN_CDB_DEPTH-1],

    // Dispatcher <-> ROB interface to enqueue a new instruction
    input  logic                              i_rob_enq_en,
    input  logic [`PCYN_ROB_OP_WIDTH-1:0]     i_rob_enq_op,
    input  logic [OPTN_ADDR_WIDTH-1:0]        i_rob_enq_pc,
    input  logic [OPTN_REGMAP_IDX_WIDTH-1:0]  i_rob_enq_rdest,

    // Looup data/tags for source operands of newly enqueued instructions
    input  logic [OPTN_DATA_WIDTH-1:0]        i_rob_lookup_data     [0:1],
    input  logic [ROB_IDX_WIDTH-1:0]          i_rob_lookup_tag      [0:1],
    input  logic                              i_rob_lookup_rdy      [0:1],
    input  logic                              i_rob_lookup_rdy_ovrd [0:1],
    output logic [OPTN_DATA_WIDTH-1:0]        o_rs_src_data         [0:1],
    output logic [ROB_IDX_WIDTH-1:0]          o_rs_src_tag          [0:1],
    output logic                              o_rs_src_rdy          [0:1],

    // Interface to register map to update destination register for retired instruction
    output logic [OPTN_DATA_WIDTH-1:0]        o_regmap_retire_data,
    output logic [OPTN_REGMAP_IDX_WIDTH-1:0]  o_regmap_retire_rdest,
    output logic [ROB_IDX_WIDTH-1:0]          o_regmap_retire_tag,
    output logic                              o_regmap_retire_en,

    // Interface to register map to update tag information of the destination register of the
    // newly enqueued instruction
    output logic [ROB_IDX_WIDTH-1:0]          o_regmap_rename_tag,
    input  logic                              i_regmap_rename_en,

    // Interface to LSU to retire loads/stores
    input  logic                              i_lsu_retire_lq_ack,
    input  logic                              i_lsu_retire_sq_ack,
    input  logic                              i_lsu_retire_misspeculated,
    output logic                              o_lsu_retire_lq_en,
    output logic                              o_lsu_retire_sq_en,
    output logic [ROB_IDX_WIDTH-1:0]          o_lsu_retire_tag
);

    // ROB entry consists of the following:
    // rdy:         Is the data valid/ready?
    // lsu_retired: Indicates if the load/store op has been retired in the LSU (only for LSU ops)
    // redirect:    Asserted by branches or instructions that cause exceptions
    // op:          What operation is the instruction doing?
    // pc:          Address of the instruction (to rollback on exception
    // addr:        Destination address for branch
    // data:        The data for the destination register
    // rdest:       The destination register
    logic                              rob_entry_rdy_q         [0:OPTN_ROB_DEPTH-1];
    logic                              rob_entry_lsu_retired_q [0:OPTN_ROB_DEPTH-1];
    logic                              rob_entry_redirect_q    [0:OPTN_ROB_DEPTH-1];
    logic [`PCYN_ROB_OP_WIDTH-1:0]     rob_entry_op_q          [0:OPTN_ROB_DEPTH-1];
    logic [OPTN_ADDR_WIDTH-1:0]        rob_entry_pc_q          [0:OPTN_ROB_DEPTH-1];
    logic [OPTN_ADDR_WIDTH-1:0]        rob_entry_addr_q        [0:OPTN_ROB_DEPTH-1];
    logic [OPTN_DATA_WIDTH-1:0]        rob_entry_data_q        [0:OPTN_ROB_DEPTH-1];
    logic [OPTN_REGMAP_IDX_WIDTH-1:0]  rob_entry_rdest_q       [0:OPTN_ROB_DEPTH-1];

    // It's convenient to add an extra bit for the head and tail pointers so that they may wrap around and allow for easier queue full/empty detection
    logic [ROB_IDX_WIDTH:0]            rob_head;
    logic [ROB_IDX_WIDTH:0]            rob_tail;
    logic [ROB_IDX_WIDTH:0]            rob_tail_next;
    logic [ROB_IDX_WIDTH:0]            rob_head_next;
    logic [ROB_IDX_WIDTH-1:0]          rob_head_addr;
    logic [ROB_IDX_WIDTH-1:0]          rob_tail_addr;
    logic                              rob_full;
    logic                              rob_empty;
    logic                              redirect;
    logic                              rob_enq_en;
    logic                              rob_rename_en;
    logic                              rob_retire_is_load;
    logic                              rob_retire_is_store;
    logic                              rob_lsu_retire_en;
    logic                              rob_retire_en;
    logic [OPTN_ROB_DEPTH-1:0]         rob_lsu_retired_ack;
    logic [OPTN_ROB_DEPTH-1:0]         rob_dispatch_select;
    logic [OPTN_ROB_DEPTH-1:0]         rob_dispatch_en;
    logic                              rob_enq_op_not_ld_or_st;
    logic [OPTN_ROB_DEPTH-1:0]         cdb_tag_select          [0:OPTN_CDB_DEPTH-1];
    logic [1:0]                        cdb_lookup_bypass       [0:OPTN_CDB_DEPTH-1];
    logic [OPTN_ROB_DEPTH-1:0]         rob_entry_redirect;
    logic [OPTN_ROB_DEPTH-1:0]         rob_entry_rdy;
    logic [OPTN_ADDR_WIDTH-1:0]        rob_entry_addr          [0:OPTN_ROB_DEPTH-1];
    logic [OPTN_DATA_WIDTH-1:0]        rob_entry_data          [0:OPTN_ROB_DEPTH-1];
    logic [OPTN_DATA_WIDTH-1:0]        rs_src_data             [0:1];
    logic [ROB_IDX_WIDTH-1:0]          rs_src_tag              [0:1];
    logic                              rs_src_rdy              [0:1];
    logic                              rob_lookup_rdy          [0:1];
    logic [OPTN_ROB_DEPTH-1:0]         rob_entry_lsu_retired_mux;

    assign rob_tail_addr           = rob_tail[ROB_IDX_WIDTH-1:0];
    assign rob_head_addr           = rob_head[ROB_IDX_WIDTH-1:0];
    assign rob_tail_next           = redirect ? {(ROB_IDX_WIDTH+1){1'b0}} : rob_rename_en ? rob_tail + 1'b1 : rob_tail;
    assign rob_head_next           = redirect ? {(ROB_IDX_WIDTH+1){1'b0}} : rob_retire_en ? rob_head + 1'b1 : rob_head;

    assign rob_enq_en              = i_rob_enq_en & ~rob_full;
    assign rob_rename_en           = i_regmap_rename_en & ~rob_full;
    assign rob_retire_is_load      = (rob_entry_op_q[rob_head_addr] == `PCYN_ROB_OP_LD);
    assign rob_retire_is_store     = (rob_entry_op_q[rob_head_addr] == `PCYN_ROB_OP_ST);
    assign rob_lsu_retire_en       = rob_entry_rdy_q[rob_head_addr] & ~rob_empty;
    assign rob_retire_en           = rob_lsu_retire_en & rob_entry_lsu_retired_q[rob_head_addr];
    assign rob_dispatch_en         = {(OPTN_ROB_DEPTH){rob_enq_en}} & rob_dispatch_select;
    assign rob_enq_op_not_ld_or_st = (i_rob_enq_op != `PCYN_ROB_OP_LD) & (i_rob_enq_op != `PCYN_ROB_OP_ST);

    // Stall if the ROB is full
    assign o_rob_stall             = rob_full;
    assign o_regmap_rename_tag     = rob_tail_addr;
    assign o_redirect              = redirect;

    // Assign outputs to LSU
    always_ff @(posedge clk) begin
        o_lsu_retire_tag <= rob_head_addr;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_lsu_retire_sq_en <= 1'b0;
        else        o_lsu_retire_sq_en <= ~redirect & ~i_lsu_retire_sq_ack & rob_retire_is_store & rob_lsu_retire_en;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_lsu_retire_lq_en <= 1'b0;
        else        o_lsu_retire_lq_en <= ~redirect & ~i_lsu_retire_lq_ack & rob_retire_is_load & rob_lsu_retire_en;
    end

    always_ff @(posedge clk) begin
        if (~n_rst | redirect) begin
            rob_full  <= 1'b0;
            rob_empty <= 1'b1;
        end else begin
            rob_full  <= ({~rob_tail_next[ROB_IDX_WIDTH], rob_tail_next[ROB_IDX_WIDTH-1:0]} == rob_head_next);
            rob_empty <= (rob_tail_next == rob_head_next);
        end
    end

    // If the instruction to be retired generated a branch and it is ready then assert the redirect signal
    always_ff @(posedge clk) begin
        if (~n_rst) redirect <= 1'b0;
        else        redirect <= ~redirect & rob_retire_en & rob_entry_redirect_q[rob_head_addr];
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_regmap_retire_en <= 1'b0;
        else        o_regmap_retire_en <= ~redirect & rob_retire_en;
    end

    always_ff @(posedge clk) begin
        o_regmap_retire_data  <= rob_entry_data_q[rob_head_addr];
        o_regmap_retire_rdest <= rob_entry_rdest_q[rob_head_addr];
        o_regmap_retire_tag   <= rob_head_addr;
        o_redirect_addr       <= (rob_entry_op_q[rob_head_addr] == `PCYN_ROB_OP_BR) ? rob_entry_addr_q[rob_head_addr] : rob_entry_pc_q[rob_head_addr];
    end

    always_ff @(posedge clk) begin
        if (rob_rename_en) rob_dispatch_select <= 1 << rob_tail_addr;
    end

    // Check if we need to bypass source data from the CDB when dispatching a new instruction
    always_comb begin
        for (int cdb_idx = 0; cdb_idx < OPTN_CDB_DEPTH; cdb_idx++) begin
            for (int src_idx = 0; src_idx < 2; src_idx++) begin
                cdb_lookup_bypass[cdb_idx][src_idx] = i_cdb_en[cdb_idx] & (i_cdb_tag[cdb_idx] == i_rob_lookup_tag[src_idx]);
            end
        end
    end

    // Getting the right source register tags/data is tricky. If the register map has ready data then that must be used
    // Otherwise the ROB entry corresponding to the tag in the register map for the source register is looked up and the data,
    // if available, is retrieved from that entry. If it's not available then the instruction must wait for the tag to be broadcast
    // on the CDB. Now if there is something available on the CDB in the same cycle and it matches the tag from the register map,
    // then that value must be used over the ROB data.
    // An instructions source ready bits can be overrided to 1 if that instruction has no use for that source which allows it to skip waiting for that source in RS
    always_comb begin
        for (int src_idx = 0; src_idx < 2; src_idx++) begin
            logic [ROB_IDX_WIDTH-1:0] rob_tag;

            rob_tag                 = i_rob_lookup_tag[src_idx];
            rob_lookup_rdy[src_idx] = i_rob_lookup_rdy[src_idx] | i_rob_lookup_rdy_ovrd[src_idx];
            rs_src_rdy[src_idx]     = rob_lookup_rdy[src_idx] | rob_entry_rdy_q[rob_tag];

            for (int cdb_idx = 0; cdb_idx < OPTN_CDB_DEPTH; cdb_idx++) begin
                rs_src_rdy[src_idx] = cdb_lookup_bypass[cdb_idx][src_idx] | rs_src_rdy[src_idx];
            end
        end
    end

    always_comb begin
        for (int src_idx = 0; src_idx < 2; src_idx++) begin
            logic [ROB_IDX_WIDTH-1:0] rob_tag;

            rob_tag              = i_rob_lookup_tag[src_idx];
            rs_src_data[src_idx] = rob_entry_data_q[rob_tag];
            rs_src_tag[src_idx]  = rob_tag;

            for (int cdb_idx = 0; cdb_idx < OPTN_CDB_DEPTH; cdb_idx++) begin
                if (cdb_lookup_bypass[cdb_idx][src_idx]) begin
                    rs_src_data[src_idx] = i_cdb_data[cdb_idx];
                    rs_src_tag[src_idx]  = i_cdb_tag[cdb_idx];
                end
            end

            rs_src_data[src_idx] = rob_lookup_rdy[src_idx] ? i_rob_lookup_data[src_idx] : rs_src_data[src_idx];
        end
    end

    always_ff @(posedge clk) begin
        if (~i_rs_stall) begin
            o_rs_src_data <= rs_src_data;
            o_rs_src_tag  <= rs_src_tag;
            o_rs_src_rdy  <= rs_src_rdy;
        end
    end

    // Check for ack signal from LSU after sending it signals indicating load/store waiting to be retired from the ROB
    always_comb begin
        rob_lsu_retired_ack                = {(OPTN_ROB_DEPTH){1'b0}};
        rob_lsu_retired_ack[rob_head_addr] = rob_lsu_retire_en & ((rob_retire_is_load & i_lsu_retire_lq_ack) | (rob_retire_is_store & i_lsu_retire_sq_ack));
    end

    // Generate enable bits for each CDB for each ROB entry when updating entry due to CDB broadcast
    always_comb begin
        for (int i = 0; i < OPTN_CDB_DEPTH; i++) begin
            cdb_tag_select[i] = {(OPTN_ROB_DEPTH){i_cdb_en[i]}} & (1 << i_cdb_tag[i]);
        end
    end

    // Check if we need to bypass source data from the CDB when dispatching a new instruction
    always_comb begin
        for (int rob_idx = 0; rob_idx < OPTN_ROB_DEPTH; rob_idx++) begin
            // Set redirect bit if LSU indicates a load/store op has been retired in the LSU and has also been mis-speculatively executed
            rob_entry_redirect[rob_idx] = rob_entry_redirect_q[rob_idx] | (rob_lsu_retired_ack[rob_idx] & i_lsu_retire_misspeculated);
            rob_entry_rdy[rob_idx]      = rob_entry_rdy_q[rob_idx];

            for (int cdb_idx = 0; cdb_idx < OPTN_CDB_DEPTH; cdb_idx++) begin
                rob_entry_redirect[rob_idx] = (cdb_tag_select[cdb_idx][rob_idx] & i_cdb_redirect[cdb_idx]) | rob_entry_redirect[rob_idx];
                rob_entry_rdy[rob_idx]      = cdb_tag_select[cdb_idx][rob_idx] | rob_entry_rdy[rob_idx];
            end
        end
    end

    // Priority mux the CDB address and data for each entry
    always_comb begin
        for (int rob_idx = 0; rob_idx < OPTN_ROB_DEPTH; rob_idx++) begin
            rob_entry_addr[rob_idx] = rob_entry_addr_q[rob_idx];
            rob_entry_data[rob_idx] = rob_entry_data_q[rob_idx];

            for (int cdb_idx = 0; cdb_idx < OPTN_CDB_DEPTH; cdb_idx++) begin
                if (cdb_tag_select[cdb_idx][rob_idx]) begin
                    rob_entry_addr[rob_idx] = i_cdb_addr[cdb_idx];
                    rob_entry_data[rob_idx] = i_cdb_data[cdb_idx];
                end
            end
        end
    end

    // Mux to determine whether to mark rob entry as retired in the LSU
    always_comb begin
        for (int i = 0; i < OPTN_ROB_DEPTH; i++) begin
            logic [1:0] rob_entry_lsu_retired_sel = {rob_lsu_retired_ack[i], rob_dispatch_en[i]};
            case (rob_entry_lsu_retired_sel)
                2'b00: rob_entry_lsu_retired_mux[i] = rob_entry_lsu_retired_q[i];
                2'b01: rob_entry_lsu_retired_mux[i] = rob_enq_op_not_ld_or_st;
                2'b10: rob_entry_lsu_retired_mux[i] = 1'b1;
                2'b11: rob_entry_lsu_retired_mux[i] = rob_enq_op_not_ld_or_st;
            endcase
        end
    end

    // Now update the ROB entry with the newly dispatched instruction Or with the data broadcast over the CDB
    always_ff @(posedge clk) begin
        for (int i = 0; i < OPTN_ROB_DEPTH; i++) begin
            rob_entry_redirect_q[i] <= ~rob_dispatch_en[i] & rob_entry_redirect[i];
            rob_entry_addr_q[i]     <= rob_entry_addr[i];
            rob_entry_data_q[i]     <= rob_entry_data[i];
            rob_entry_op_q[i]       <= rob_dispatch_en[i] ? i_rob_enq_op    : rob_entry_op_q[i];
            rob_entry_pc_q[i]       <= rob_dispatch_en[i] ? i_rob_enq_pc    : rob_entry_pc_q[i];
            rob_entry_rdest_q[i]    <= rob_dispatch_en[i] ? i_rob_enq_rdest : rob_entry_rdest_q[i];
        end
    end

    // Clear the ready bits on a flush or reset
    always_ff @(posedge clk) begin
        for (int i = 0; i < OPTN_ROB_DEPTH; i++) begin
            if (~n_rst) rob_entry_rdy_q[i] <= 1'b0;
            else        rob_entry_rdy_q[i] <= ~(redirect | rob_dispatch_en[i]) & rob_entry_rdy[i];
        end
    end

    // Clear the lsu_retired bits on a reset
    // lsu_retired is always asserted on enqueue if the op is not a load or store
    // Otherwise it is asserted when the LSU indicates the load/store op has been retired in the LSU
    always_ff @(posedge clk) begin
        for (int i = 0; i < OPTN_ROB_DEPTH; i++) begin
            if (~n_rst) rob_entry_lsu_retired_q[i] <= 1'b0;
            else        rob_entry_lsu_retired_q[i] <= rob_entry_lsu_retired_mux[i];
        end
    end

    // Increment the tail pointer to reserve an entry when the Dispatcher is in the renaming cycle
    // and the ROB is not full. On the next cycle the entry will be filled. Reset if redirect asserted.
    always_ff @(posedge clk) begin
        if (~n_rst) rob_tail <= {(ROB_IDX_WIDTH+1){1'b0}};
        else        rob_tail <= rob_tail_next;
    end

    // Increment the head pointer if the instruction to be retired is ready and the ROB is not
    // empty (of course this should never be the case). Reset if redirect asserted
    always_ff @(posedge clk) begin
        if (~n_rst) rob_head <= {(ROB_IDX_WIDTH+1){1'b0}};
        else        rob_head <= rob_head_next;
    end

endmodule
