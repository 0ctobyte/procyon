// Reservation Station with age-matrix based out of order issue 
// The reservation station will pick the oldest instruction that has all 
// it's source operands ready for issue. New instructions allocated in the 
// reservation station will be assigned an age of 0 which will increment/decrement
// if other instructions are dispatched/issued.

`include "common.svh"
import types::*;

module reservation_station #(
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter TAG_WIDTH  = `TAG_WIDTH,
    parameter CDB_DEPTH  = `CDB_DEPTH,
    parameter RS_DEPTH   = `RS_DEPTH
) (
    input  logic                           clk,
    input  logic                           n_rst,

    input  logic                           i_flush,

    // Common Data Bus networks
    input  logic                           i_cdb_en       [0:CDB_DEPTH-1],
    input  logic                           i_cdb_redirect [0:CDB_DEPTH-1],
    input  logic [DATA_WIDTH-1:0]          i_cdb_data     [0:CDB_DEPTH-1],
    input  logic [ADDR_WIDTH-1:0]          i_cdb_addr     [0:CDB_DEPTH-1],
    input  logic [TAG_WIDTH-1:0]           i_cdb_tag      [0:CDB_DEPTH-1],

    // Dispatch interface
    input  logic                           i_rs_en,
    input  opcode_t                        i_rs_opcode,
    input  logic [ADDR_WIDTH-1:0]          i_rs_iaddr,
    input  logic [DATA_WIDTH-1:0]          i_rs_insn,
    input  logic [TAG_WIDTH-1:0]           i_rs_src_tag  [0:1],
    input  logic [DATA_WIDTH-1:0]          i_rs_src_data [0:1],
    input  logic                           i_rs_src_rdy  [0:1],
    input  logic [TAG_WIDTH-1:0]           i_rs_dst_tag,
    output logic                           o_rs_stall,
    
    // Functional Unit interface
    input  logic                           i_fu_stall,
    output logic                           o_fu_valid,
    output opcode_t                        o_fu_opcode,
    output logic [ADDR_WIDTH-1:0]          o_fu_iaddr,
    output logic [DATA_WIDTH-1:0]          o_fu_insn,
    output logic [DATA_WIDTH-1:0]          o_fu_src_a,
    output logic [DATA_WIDTH-1:0]          o_fu_src_b,
    output logic [TAG_WIDTH-1:0]           o_fu_tag
);
    typedef struct {
        logic [$clog2(RS_DEPTH)-1:0] age;
        opcode_t                     opcode;
        logic [ADDR_WIDTH-1:0]       iaddr;
        logic [DATA_WIDTH-1:0]       insn;
        logic                        src_rdy  [0:1];
        logic [DATA_WIDTH-1:0]       src_data [0:1];
        logic [TAG_WIDTH-1:0]        src_tag  [0:1];
        logic [TAG_WIDTH-1:0]        dst_tag;
        logic                        empty;
    } rs_slot_t;

    typedef struct {
        logic                full;
        logic [RS_DEPTH-1:0] empty;
        logic [RS_DEPTH-1:0] issue_ready;
        logic [RS_DEPTH-1:0] issue_select;
        logic [RS_DEPTH-1:0] dispatch_select;
        logic [RS_DEPTH-1:0] age_matrix [0:RS_DEPTH-1];
        rs_slot_t            slots      [0:RS_DEPTH-1];
    } rs_t;
    rs_t rs;

    logic                        dispatching;
    logic                        issuing;

    logic [$clog2(RS_DEPTH)-1:0] issue_slot;

    genvar i, j;
    generate
    // Generate the age matrix. A reservation station slot's age must be
    // greater than all other reservation station slots that are also ready to
    // issue
    for (i = 0; i < RS_DEPTH; i++) begin : ASSIGN_AGE_MATRIX_OUTER
        for (j = 0; j < RS_DEPTH; j++) begin : ASSIGN_AGE_MATRIX_INNER
            if (i == j)
                assign rs.age_matrix[i][j] = 'b1;
            else
                assign rs.age_matrix[i][j] = rs.slots[i].age > rs.slots[j].age;
        end
    end

    for (i = 0; i < RS_DEPTH; i++) begin : ASSIGN_RS_VECTORS
        assign rs.empty[i]           = rs.slots[i].empty;

        // An slot is ready to issue if it is not empty and has both it's
        // source operands
        assign rs.issue_ready[i]     = ~rs.slots[i].empty && rs.slots[i].src_rdy[0] && rs.slots[i].src_rdy[1];

        // Select the oldest slot that is ready to issue. The OR with the
        // complement of the issue_ready vector is to discard age comparisons
        // with slots that aren't ready to issue
        assign rs.issue_select[i]    = &(rs.age_matrix[i] | ~rs.issue_ready) & rs.issue_ready[i];
    end
    endgenerate
    
    // This will produce a one-hot vector of the slot that will be used
    // to store the dispatched instruction
    assign rs.dispatch_select = rs.empty & ~(rs.empty - 1'b1);

    // The reservation station is full if there are no empty slots
    // Assert the stall signal in this situation
    assign rs.full            = ~|(rs.empty);
    assign o_rs_stall         = rs.full;

    assign dispatching        = ^(rs.dispatch_select) && i_rs_en;
    assign issuing            = ^(rs.issue_select) && ~i_fu_stall;

    // Assign functional unit output
    assign o_fu_opcode        = rs.slots[issue_slot].opcode;
    assign o_fu_iaddr         = rs.slots[issue_slot].iaddr;
    assign o_fu_insn          = rs.slots[issue_slot].insn;
    assign o_fu_src_a         = rs.slots[issue_slot].src_data[0];
    assign o_fu_src_b         = rs.slots[issue_slot].src_data[1];
    assign o_fu_tag           = rs.slots[issue_slot].dst_tag;
    assign o_fu_valid         = issuing;

    // Convert one-hot issue_select vector to binary RS slot #
    always_comb begin
        logic [$clog2(RS_DEPTH)-1:0] r;
        r = 0;
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (rs.issue_select[i]) begin
                r = r | i;
            end
        end

        issue_slot = r;
    end

    // The empty bit is only cleared if the slot is used to hold the next
    // dispatched instruction. Set it if the slot is issuing or on a pipeline
    // flush
    always_ff @(posedge clk, negedge n_rst) begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (~n_rst) begin
                rs.slots[i].empty <= 'b1;
            end else if (i_flush) begin
                rs.slots[i].empty <= 'b1;
            end else if (issuing && rs.issue_select[i]) begin
                rs.slots[i].empty <= 'b1;
            end else if (dispatching && rs.dispatch_select[i]) begin
                rs.slots[i].empty <= 'b0;
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
                2'b00: rs.slots[i].age <= rs.slots[i].age;
                2'b01: rs.slots[i].age <= (rs.slots[i].age > rs.slots[issue_slot].age) ? rs.slots[i].age - 1'b1 : rs.slots[i].age;
                2'b10: rs.slots[i].age <= (rs.dispatch_select[i]) ? 'b0 : rs.slots[i].age + 1'b1;
                2'b11: rs.slots[i].age <= (rs.dispatch_select[i]) ? 'b0 : ((rs.slots[i].age < rs.slots[issue_slot].age) ? rs.slots[i].age + 1'b1 : rs.slots[i].age);
            endcase
        end
    end

    // Update slot for newly dispatched instruction
    always_ff @(posedge clk) begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (dispatching && rs.dispatch_select[i]) begin
                rs.slots[i].opcode     <= i_rs_opcode;
                rs.slots[i].iaddr      <= i_rs_iaddr;
                rs.slots[i].insn       <= i_rs_insn;
                rs.slots[i].src_tag[0] <= i_rs_src_tag[0];
                rs.slots[i].src_tag[1] <= i_rs_src_tag[1];
                rs.slots[i].dst_tag    <= i_rs_dst_tag;
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
                    {rs.slots[i].src_rdy[k], rs.slots[i].src_data[k]} <= {i_rs_src_rdy[k], i_rs_src_data[k]};
                end else begin
                    for (int j = 0; j < CDB_DEPTH; j++) begin
                        if (~rs.slots[i].src_rdy[k] && i_cdb_en[j] && (i_cdb_tag[j] == rs.slots[i].src_tag[k])) begin
                            {rs.slots[i].src_rdy[k], rs.slots[i].src_data[k]} <= {1'b1, i_cdb_data[j]};
                        end
                    end
                end
            end
        end
    end

endmodule
