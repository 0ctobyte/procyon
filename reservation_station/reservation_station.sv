// Generic linear shifting reservation station

import types::*;

module reservation_station #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter TAG_WIDTH  = 6,
    parameter RS_DEPTH   = 8
) (
    input  logic        clk,
    input  logic        n_rst,

    input  logic        i_flush,

    // Dispatch interface
    rs_dispatch_if.sink rs_dispatch,

    // Functional Unit interface
    rs_funit_if.source  rs_funit
);

    typedef struct packed {
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

    typedef struct packed {
        logic                full;
        logic [RS_DEPTH-1:0] empty;
        logic [RS_DEPTH-1:0] issue_ready;
        logic [RS_DEPTH-1:0] issue_select;
        logic [RS_DEPTH-1:0] dispatch_select;
        logic [RS_DEPTH-1:0] age_matrix [0:RS_DEPTH-1];
        rs_slot_t            slots [RS_DEPTH-1:0];
    } rs_t;

    rs_t rs;

    genvar i, j;

    logic dispatching;
    logic issuing;

    logic [$clog2(RS_DEPTH)-1:0] issue_slot;

    generate
    // Generate the age matrix. A reservation station slot's age must be
    // greater than all other reservation station slots that are also ready to
    // issue
    for (i = 0; i < RS_DEPTH; i++) begin
        for (j = 0; j < RS_DEPTH; j++) begin
            if (i == j)
                assign age_matrix[i][j] = 'b1;
            else
                assign age_matrix[i][j] = rs.slots[i].age > rs.slots[j].age;
        end
    end

    for (i = 0; i < RS_DEPTH; i++) begin
        assign rs.empty[i]           = rs.slots[i].empty;

        // An slot is ready to issue if it is not empty and has both it's
        // source operands
        assign rs.issue_ready[i]     = ~rs.slots[i].empty && rs.slots[i].src_rdy[0] && rs.slots[i].src_rdy[1];

        // Select the oldest slot that is ready to issue. The OR with the
        // complement of the issue_ready vector is to discard age comparisons
        // with slots that aren't ready to issue
        assign rs.issue_select[i]    = &(rs.age_matrix[i] | ~rs.issue_ready) & rs.issue_ready[i];

        // This will produce a one-hot vector of the slot that will be used
        // to store the dispatched instruction
        assign rs.dispatch_select[i] = rs.empty & ~(rs.empty - 'b1);
    end
    endgenerate
    
    // The reservation station is full if there are no empty slots
    // Assert the stall signal in this situation
    assign rs.full           = ~|(rs.empty);
    assign rs_dispatch.stall = rs.full;

    assign dispatching = ^(rs.dispatch_select) && rs_dispatch.en;
    assign issuing     = ^(rs.issue_select);

    // Assign functional unit output
    assign rs_funit.opcode = issuing ? rs.slots[issue_slot].opcode      : OPCODE_OPIMM;
    assign rs_funit.iaddr  = issuing ? rs.slots[issue_slot].iaddr       : 'b0;
    assign rs_funit.insn   = issuing ? rs.slots[issue_slot].insn        : 32'h00000013;
    assign rs_funit.src_a  = issuing ? rs.slots[issue_slot].src_data[0] : 'b0;
    assign rs_funit.src_b  = issuing ? rs.slots[issue_slot].src_data[1] : 'b0;
    assign rs_funit.tag    = issuing ? rs.slots[issue_slot].dst_tag     : 'b0;

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
            end else if (rs.issue_select[i]) begin
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
                rs.slots[i].opcode     <= rs_dispatch.opcode;
                rs.slots[i].iaddr      <= rs_dispatch.iaddr;
                rs.slots[i].insn       <= rs_dispatch.insn;
                rs.slots[i].src_tag[0] <= rs_dispatch.src_tag[0];
                rs.slots[i].src_tag[1] <= rs_dispatch.src_tag[1];
                rs.slots[i].dst_tag    <= rs_dispatch.dst_tag;
            end
        end
    end

    // Grab data from the CDB for the source operands and set the ready bits
    // to true
    always_ff @(posedge clk) begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            for (int k = 0; k < 2; k++) begin
                if (dispatching && rs.dispatch_select[i]) begin
                    rs.slots[i].src_rdy[k]  <= rs_dispatch.src_rdy[k];
                    rs.slots[i].src_data[k] <= rs_dispatch.src_data[k];
                end else if (cdb.en && cdb.tag == rs.slots[i].src_tag[k]) begin
                    rs.slots[i].src_rdy[k]  <= 'b1;
                    rs.slots[i].src_data[k] <= cdb.data;
                end
            end
        end
    end

endmodule
