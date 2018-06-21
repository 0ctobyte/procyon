// Reservation Station with age-matrix based out of order issue
// The reservation station will pick the oldest instruction that has all
// it's source operands ready for issue. New instructions allocated in the
// reservation station will be assigned an age of 0 which will increment/decrement
// if other instructions are dispatched/issued. The reservation station will also
// listen in on all CDB busses and pick up source data for both sources if the CDBs
// broadcast matching tags that the source is waiting on

`include "common.svh"
import procyon_types::*;

module reservation_station #(
    parameter RS_DEPTH = RS_DEPTH
) (
    input  logic              clk,
    input  logic              n_rst,

    input  logic              i_flush,

    // Common Data Bus networks
    input  logic              i_cdb_en       [0:`CDB_DEPTH-1],
    input  procyon_data_t     i_cdb_data     [0:`CDB_DEPTH-1],
    input  procyon_tag_t      i_cdb_tag      [0:`CDB_DEPTH-1],

    // Dispatch interface
    input  logic              i_rs_en,
    input  procyon_opcode_t   i_rs_opcode,
    input  procyon_addr_t     i_rs_iaddr,
    input  procyon_data_t     i_rs_insn,
    input  procyon_tag_t      i_rs_src_tag  [0:1],
    input  procyon_data_t     i_rs_src_data [0:1],
    input  logic              i_rs_src_rdy  [0:1],
    input  procyon_tag_t      i_rs_dst_tag,
    output logic              o_rs_stall,

    // Functional Unit interface
    input  logic              i_fu_stall,
    output logic              o_fu_valid,
    output procyon_opcode_t   o_fu_opcode,
    output procyon_addr_t     o_fu_iaddr,
    output procyon_data_t     o_fu_insn,
    output procyon_data_t     o_fu_src_a,
    output procyon_data_t     o_fu_src_b,
    output procyon_tag_t      o_fu_tag
);

    typedef logic [$clog2(RS_DEPTH)-1:0] rs_age_t;
    typedef rs_age_t                     rs_idx_t;
    typedef logic [RS_DEPTH-1:0]         rs_vec_t;

    typedef struct packed {
        rs_age_t                                 age;
        procyon_opcode_t                         opcode;
        procyon_addr_t                           iaddr;
        procyon_data_t                           insn;
        logic            [1:0]                   src_rdy;
        procyon_data_t   [1:0]                   src_data;
        procyon_tag_t    [1:0]                   src_tag;
        procyon_tag_t                            dst_tag;
        logic                                    empty;
    } rs_slot_t;

/* verilator lint_off MULTIDRIVEN */
    rs_slot_t      [RS_DEPTH-1:0]                         rs_slots;
/* verilator lint_on  MULTIDRIVEN */
    logic                                                 rs_full;
    rs_vec_t                                              rs_empty;
    rs_vec_t                                              rs_issue_ready;
    rs_vec_t                                              rs_issue_select;
    rs_vec_t                                              rs_dispatch_select;
    rs_vec_t       [RS_DEPTH-1:0]                         rs_age_matrix;
    rs_vec_t                                              rs_slots_empty_m;
    rs_age_t       [RS_DEPTH-1:0]                         rs_slots_age_m;
    procyon_data_t [RS_DEPTH-1:0] [1:0]                   rs_slots_src_data;
    logic          [RS_DEPTH-1:0] [1:0]                   rs_slots_src_rdy;
    logic          [RS_DEPTH-1:0] [1:0] [`CDB_DEPTH-1:0]  cdb_select;
    logic                                                 dispatching;
    rs_vec_t                                              dispatch_en;
    logic                                                 issuing;
    rs_idx_t                                              issue_slot;
    genvar                                                gvar0;
    genvar                                                gvar1;

    // This will produce a one-hot vector of the slot that will be used
    // to store the dispatched instruction
    assign rs_dispatch_select                             = rs_empty & ~(rs_empty - 1'b1);
    assign rs_full                                        = ~|(rs_empty);

    assign dispatching                                    = ~rs_full & i_rs_en;
    assign issuing                                        = ^(rs_issue_select) & ~i_fu_stall;
    assign dispatch_en                                    = {(RS_DEPTH){dispatching}} & rs_dispatch_select;

    // The reservation station is full if there are no empty slots
    // Assert the stall signal in this situation
    assign o_rs_stall                                     = rs_full;

    // Assign functional unit output
    assign o_fu_opcode                                    = rs_slots[issue_slot].opcode;
    assign o_fu_iaddr                                     = rs_slots[issue_slot].iaddr;
    assign o_fu_insn                                      = rs_slots[issue_slot].insn;
    assign o_fu_src_a                                     = rs_slots[issue_slot].src_data[0];
    assign o_fu_src_b                                     = rs_slots[issue_slot].src_data[1];
    assign o_fu_tag                                       = rs_slots[issue_slot].dst_tag;
    assign o_fu_valid                                     = issuing;

    // Generate the age matrix. A reservation station slot's age must be
    // greater than all other reservation station slots that are also ready to issue
    generate
        for (gvar0 = 0; gvar0 < RS_DEPTH; gvar0++) begin : ASSIGN_AGE_MATRIX_OUTER
            for (gvar1 = 0; gvar1 < RS_DEPTH; gvar1++) begin : ASSIGN_AGE_MATRIX_INNER
                if (gvar0 == gvar1)
                    assign rs_age_matrix[gvar0][gvar1] = 1'b1;
                else
                    assign rs_age_matrix[gvar0][gvar1] = rs_slots[gvar0].age > rs_slots[gvar1].age;
            end
        end

        for (gvar0 = 0; gvar0 < RS_DEPTH; gvar0++) begin : ASSIGN_RS_VECTORS
            assign rs_empty[gvar0]           = rs_slots[gvar0].empty;

            // A slot is ready to issue if it is not empty and has both it's source operands
            assign rs_issue_ready[gvar0]     = ~rs_slots[gvar0].empty & rs_slots[gvar0].src_rdy[0] & rs_slots[gvar0].src_rdy[1];

            // Select the oldest slot that is ready to issue. The OR with the
            // complement of the issue_ready vector is to discard age comparisons
            // with slots that aren't ready to issue
            assign rs_issue_select[gvar0]    = &(rs_age_matrix[gvar0] | ~rs_issue_ready) & rs_issue_ready[gvar0];
        end
    endgenerate

    // Priority encoder to convert one-hot issue_select vector to binary RS slot #
    always_comb begin
        issue_slot = {($clog2(RS_DEPTH)){1'b0}};

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (rs_issue_select[i]) begin
                issue_slot = i[$clog2(RS_DEPTH)-1:0];
            end
        end
    end

    // The empty bit is only cleared if the slot will be used to hold the next
    // dispatched instruction. Set it if the slot is issuing or on a pipeline flush
    always_comb begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            logic [1:0] rs_slot_empty_sel;
            rs_slot_empty_sel   = {i_flush | rs_issue_select[i], rs_dispatch_select[i]};
            rs_slots_empty_m[i] = mux4_1b(rs_slots[i].empty, ~dispatching, issuing | i_flush, i_flush, rs_slot_empty_sel);
        end
    end

    always_ff @(posedge clk) begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (~n_rst) rs_slots[i].empty <= 'b1;
            else        rs_slots[i].empty <= rs_slots_empty_m[i];
        end
    end

    // A slot's age needs to be adjusted each time an instruction is issued or dispatched. If a new instruction is dispatched only, it
    // starts off with an age of 0 and all other slots' age are incremented. If an instruction is only issued then only the slots that have an age
    // greater than the issuing slot's age will be decremented. If an instruction is being dispatched and another instruction is being
    // issued in the same cycle, then we only increment those slots that have an age less than the issuing slot's age.
    always_comb begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            case ({dispatching, issuing})
                2'b00: rs_slots_age_m[i] = rs_slots[i].age;
                2'b01: rs_slots_age_m[i] = rs_slots[i].age - rs_age_t'(rs_slots[i].age > rs_slots[issue_slot].age);
                2'b10: rs_slots_age_m[i] = {($clog2(RS_DEPTH)){~rs_dispatch_select[i]}} & (rs_slots[i].age + 1'b1);
                2'b11: rs_slots_age_m[i] = {($clog2(RS_DEPTH)){~rs_dispatch_select[i]}} & (rs_slots[i].age + rs_age_t'(rs_slots[i].age < rs_slots[issue_slot].age));
            endcase
        end
    end

    always_ff @(posedge clk) begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            rs_slots[i].age <= rs_slots_age_m[i];
        end
    end

    // Update slot for newly dispatched instruction
    always_ff @(posedge clk) begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (dispatch_en[i]) begin
                rs_slots[i].opcode     <= i_rs_opcode;
                rs_slots[i].iaddr      <= i_rs_iaddr;
                rs_slots[i].insn       <= i_rs_insn;
                rs_slots[i].src_tag    <= {i_rs_src_tag[1], i_rs_src_tag[0]};
                rs_slots[i].dst_tag    <= i_rs_dst_tag;
            end
        end
    end

    // Check both source tags for each RS slot to see if a CDB is broadcasting a matching tag
    always_comb begin
        for (int rs_idx = 0; rs_idx < RS_DEPTH; rs_idx++) begin
            for (int src_idx = 0; src_idx < 2; src_idx++) begin
                for (int cdb_idx = 0; cdb_idx < `CDB_DEPTH; cdb_idx++) begin
                    cdb_select[rs_idx][src_idx][cdb_idx] = i_cdb_en[cdb_idx] & (i_cdb_tag[cdb_idx] == rs_slots[rs_idx].src_tag[src_idx]);
                end
            end
        end
    end

    // Grab data from the CDB for the source operands and set the ready bits to true
    // Don't mess with the src data if it's already "ready", regardless of what is being broadcast on the CDB!
    // This really only applies to ops that use X0 register since the src tag for the X0 register is always 0
    // which could possibly be a valid tag
    always_comb begin
        for (int rs_idx = 0; rs_idx < RS_DEPTH; rs_idx++) begin
            for (int src_idx = 0; src_idx < 2; src_idx++) begin
                // Priority mux to select input from the CDB busses, where the higher "numbered" CDB bus gets priority
                // Of course, this shouldn't matter since the CDBs should never broadcast the same tag on the same cycle
                rs_slots_src_data[rs_idx][src_idx] = rs_slots[rs_idx].src_data[src_idx];

                for (int cdb_idx = 0; cdb_idx < `CDB_DEPTH; cdb_idx++) begin
                    if (~rs_slots[rs_idx].src_rdy[src_idx] & cdb_select[rs_idx][src_idx][cdb_idx]) begin
                        rs_slots_src_data[rs_idx][src_idx] = i_cdb_data[cdb_idx];
                    end
                end
            end
         end
    end

    // A slot's sources are ready if it's been previously marked ready or if any of the CDB busses broadcast a matching tag that the source is waiting on.
    always_comb begin
        for (int rs_idx = 0; rs_idx < RS_DEPTH; rs_idx++) begin
            for (int src_idx = 0; src_idx < 2; src_idx++) begin
                rs_slots_src_rdy[rs_idx][src_idx] = rs_slots[rs_idx].src_rdy[src_idx];

                for (int cdb_idx = 0; cdb_idx < `CDB_DEPTH; cdb_idx++) begin
                    rs_slots_src_rdy[rs_idx][src_idx] = cdb_select[rs_idx][src_idx][cdb_idx] | rs_slots_src_rdy[rs_idx][src_idx];
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        for (int rs_idx = 0; rs_idx < RS_DEPTH; rs_idx++) begin
            for (int src_idx = 0; src_idx < 2; src_idx++) begin
                rs_slots[rs_idx].src_rdy[src_idx]  <= dispatch_en[rs_idx] ? i_rs_src_rdy[src_idx]  : rs_slots_src_rdy[rs_idx][src_idx];
                rs_slots[rs_idx].src_data[src_idx] <= dispatch_en[rs_idx] ? i_rs_src_data[src_idx] : rs_slots_src_data[rs_idx][src_idx];
            end
        end
    end

endmodule
