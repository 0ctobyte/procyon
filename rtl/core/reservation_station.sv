// Reservation Station with age-matrix based out of order issue
// The reservation station will pick the oldest instruction that has all
// it's source operands ready for issue. New instructions allocated in the
// reservation station will be assigned an age of 0 which will increment/decrement
// if other instructions are dispatched/issued.

`include "common.svh"
import procyon_types::*;

/* verilator lint_off MULTIDRIVEN */
module reservation_station #(
    parameter RS_DEPTH = `RS_DEPTH
) (
    input  logic              clk,
/* verilator lint_off UNUSED */
    input  logic              n_rst,

    input  logic              i_flush,

    // Common Data Bus networks
    input  logic              i_cdb_en       [0:`CDB_DEPTH-1],
    input  logic              i_cdb_redirect [0:`CDB_DEPTH-1],
    input  procyon_data_t     i_cdb_data     [0:`CDB_DEPTH-1],
    input  procyon_addr_t     i_cdb_addr     [0:`CDB_DEPTH-1],
    input  procyon_tag_t      i_cdb_tag      [0:`CDB_DEPTH-1],
/* verilator lint_on  UNUSED */

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
    typedef struct packed {
        logic            [$clog2(RS_DEPTH)-1:0] age;
        procyon_opcode_t                        opcode;
        procyon_addr_t                          iaddr;
        procyon_data_t                          insn;
        logic            [1:0]                  src_rdy;
        procyon_data_t   [1:0]                  src_data;
        procyon_tag_t    [1:0]                  src_tag;
        procyon_tag_t                           dst_tag;
        logic                                   empty;
    } rs_slot_t;

    typedef struct packed {
        logic                                   full;
        logic     [RS_DEPTH-1:0]                empty;
        logic     [RS_DEPTH-1:0]                issue_ready;
        logic     [RS_DEPTH-1:0]                issue_select;
        logic     [RS_DEPTH-1:0]                dispatch_select;
        logic     [RS_DEPTH-1:0] [RS_DEPTH-1:0] age_matrix;
    } rs_t;

    rs_slot_t [RS_DEPTH-1:0]         rs_slots;
/* verilator lint_off UNOPTFLAT */
    rs_t                             rs;
/* verilator lint_on  UNOPTFLAT */
    logic                            dispatching;
    logic                            issuing;
    logic     [$clog2(RS_DEPTH)-1:0] issue_slot;

    genvar gvar0, gvar1;
    generate
        // Generate the age matrix. A reservation station slot's age must be
        // greater than all other reservation station slots that are also ready to
        // issue
        for (gvar0 = 0; gvar0 < RS_DEPTH; gvar0++) begin : ASSIGN_AGE_MATRIX_OUTER
            for (gvar1 = 0; gvar1 < RS_DEPTH; gvar1++) begin : ASSIGN_AGE_MATRIX_INNER
                if (gvar0 == gvar1)
                    assign rs.age_matrix[gvar0][gvar1] = 'b1;
                else
                    assign rs.age_matrix[gvar0][gvar1] = rs_slots[gvar0].age > rs_slots[gvar1].age;
            end
        end

        for (gvar0 = 0; gvar0 < RS_DEPTH; gvar0++) begin : ASSIGN_RS_VECTORS
            assign rs.empty[gvar0]           = rs_slots[gvar0].empty;

            // An slot is ready to issue if it is not empty and has both it's
            // source operands
            assign rs.issue_ready[gvar0]     = ~rs_slots[gvar0].empty && rs_slots[gvar0].src_rdy[0] && rs_slots[gvar0].src_rdy[1];

            // Select the oldest slot that is ready to issue. The OR with the
            // complement of the issue_ready vector is to discard age comparisons
            // with slots that aren't ready to issue
            assign rs.issue_select[gvar0]    = &(rs.age_matrix[gvar0] | ~rs.issue_ready) & rs.issue_ready[gvar0];
        end
    endgenerate

    // This will produce a one-hot vector of the slot that will be used
    // to store the dispatched instruction
    assign rs.dispatch_select = rs.empty & ~(rs.empty - 1'b1);

    // The reservation station is full if there are no empty slots
    // Assert the stall signal in this situation
    assign rs.full            = ~|(rs.empty);
    assign o_rs_stall         = rs.full;

    assign dispatching        = ~rs.full && i_rs_en;
    assign issuing            = ^(rs.issue_select) && ~i_fu_stall;

    // Assign functional unit output
    assign o_fu_opcode        = rs_slots[issue_slot].opcode;
    assign o_fu_iaddr         = rs_slots[issue_slot].iaddr;
    assign o_fu_insn          = rs_slots[issue_slot].insn;
    assign o_fu_src_a         = rs_slots[issue_slot].src_data[0];
    assign o_fu_src_b         = rs_slots[issue_slot].src_data[1];
    assign o_fu_tag           = rs_slots[issue_slot].dst_tag;
    assign o_fu_valid         = issuing;

    // Convert one-hot issue_select vector to binary RS slot #
    always_comb begin
        int r;
        r = 0;
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (rs.issue_select[i]) begin
                r = r | i;
            end
        end
        issue_slot = r[$clog2(RS_DEPTH)-1:0];
    end

    // The empty bit is only cleared if the slot is used to hold the next
    // dispatched instruction. Set it if the slot is issuing or on a pipeline
    // flush
    always_ff @(posedge clk, negedge n_rst) begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (~n_rst) begin
                rs_slots[i].empty <= 'b1;
            end else if (i_flush) begin
                rs_slots[i].empty <= 'b1;
            end else if (issuing && rs.issue_select[i]) begin
                rs_slots[i].empty <= 'b1;
            end else if (dispatching && rs.dispatch_select[i]) begin
                rs_slots[i].empty <= 'b0;
            end
        end
    end

    // A slot's age needs to be adjusted each time an instruction is
    // issued or dispatched. If a new instruction is dispatched only, it
    // starts off with an age of 0 and all other slots' age are incremented.
    // If an instruction is only issued then only the slots that have an age
    // greater than the issuing slot's age will be decremented. If an
    // instruction is being dispatched and another instruction is being
    // issued in the same cycle, then we only increment those slots that
    // have an age less than the issuing slot's age.
    always_ff @(posedge clk) begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            case ({dispatching, issuing})
                2'b00: rs_slots[i].age <= rs_slots[i].age;
                2'b01: rs_slots[i].age <= (rs_slots[i].age > rs_slots[issue_slot].age) ? rs_slots[i].age - 1'b1 : rs_slots[i].age;
                2'b10: rs_slots[i].age <= (rs.dispatch_select[i]) ? {{($clog2(RS_DEPTH)){1'b0}}} : rs_slots[i].age + 1'b1;
                2'b11: rs_slots[i].age <= (rs.dispatch_select[i]) ? {{($clog2(RS_DEPTH)){1'b0}}} : ((rs_slots[i].age < rs_slots[issue_slot].age) ? rs_slots[i].age + 1'b1 : rs_slots[i].age);
            endcase
        end
    end

    // Update slot for newly dispatched instruction
    always_ff @(posedge clk) begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (dispatching && rs.dispatch_select[i]) begin
                rs_slots[i].opcode     <= i_rs_opcode;
                rs_slots[i].iaddr      <= i_rs_iaddr;
                rs_slots[i].insn       <= i_rs_insn;
                rs_slots[i].src_tag[0] <= i_rs_src_tag[0];
                rs_slots[i].src_tag[1] <= i_rs_src_tag[1];
                rs_slots[i].dst_tag    <= i_rs_dst_tag;
            end
        end
    end

    // Grab data from the CDB for the source operands and set the ready bits to true
    // Don't mess with the src data if it's already "ready", regardless of what is being broadcast on the CDB!
    // This really only applies to ops that use X0 register since the src tag for the X0 register is always 0
    // which could possibly be a valid tag
    always_ff @(posedge clk) begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            for (int k = 0; k < 2; k++) begin
                if (dispatching && rs.dispatch_select[i]) begin
                    {rs_slots[i].src_rdy[k], rs_slots[i].src_data[k]} <= {i_rs_src_rdy[k], i_rs_src_data[k]};
                end else begin
                    for (int j = 0; j < `CDB_DEPTH; j++) begin
                        if (~rs_slots[i].src_rdy[k] && i_cdb_en[j] && (i_cdb_tag[j] == rs_slots[i].src_tag[k])) begin
                            {rs_slots[i].src_rdy[k], rs_slots[i].src_data[k]} <= {1'b1, i_cdb_data[j]};
                        end
                    end
                end
            end
        end
    end

endmodule
/* verilator lint_on  MULTIDRIVEN */
