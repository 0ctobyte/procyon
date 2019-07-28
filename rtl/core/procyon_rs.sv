// Reservation Station with age-matrix based out of order issue
// The reservation station will pick the oldest instruction that has all
// it's source operands ready for issue. New instructions allocated in the
// reservation station will be assigned an age of 0 which will increment/decrement
// if other instructions are dispatched/issued. The reservation station will also
// listen in on all CDB busses and pick up source data for both sources if the CDBs
// broadcast matching tags that the source is waiting on

`include "procyon_constants.svh"

module procyon_rs #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_ROB_IDX_WIDTH = 5,
    parameter OPTN_CDB_DEPTH     = 2,
    parameter OPTN_RS_DEPTH      = 16
) (
    input  logic                          clk,
    input  logic                          n_rst,

    input  logic                          i_flush,

    // Common Data Bus networks
    input  logic                          i_cdb_en      [0:OPTN_CDB_DEPTH-1],
    input  logic [OPTN_DATA_WIDTH-1:0]    i_cdb_data    [0:OPTN_CDB_DEPTH-1],
    input  logic [OPTN_ROB_IDX_WIDTH-1:0] i_cdb_tag     [0:OPTN_CDB_DEPTH-1],

    // Dispatch interface
    input  logic                          i_rs_en,
    input  logic [`PCYN_OPCODE_WIDTH-1:0] i_rs_opcode,
    input  logic [OPTN_ADDR_WIDTH-1:0]    i_rs_iaddr,
    input  logic [OPTN_DATA_WIDTH-1:0]    i_rs_insn,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0] i_rs_src_tag  [0:1],
    input  logic [OPTN_DATA_WIDTH-1:0]    i_rs_src_data [0:1],
    input  logic                          i_rs_src_rdy  [0:1],
    input  logic [OPTN_ROB_IDX_WIDTH-1:0] i_rs_dst_tag,
    output logic                          o_rs_stall,

    // Functional Unit interface
    input  logic                          i_fu_stall,
    output logic                          o_fu_valid,
    output logic [`PCYN_OPCODE_WIDTH-1:0] o_fu_opcode,
    output logic [OPTN_ADDR_WIDTH-1:0]    o_fu_iaddr,
    output logic [OPTN_DATA_WIDTH-1:0]    o_fu_insn,
    output logic [OPTN_DATA_WIDTH-1:0]    o_fu_src_a,
    output logic [OPTN_DATA_WIDTH-1:0]    o_fu_src_b,
    output logic [OPTN_ROB_IDX_WIDTH-1:0] o_fu_tag
);

    localparam RS_IDX_WIDTH = $clog2(OPTN_RS_DEPTH);

    // Reservations station registers
    logic [RS_IDX_WIDTH-1:0]       rs_slot_age_q      [0:OPTN_RS_DEPTH-1];
    logic [`PCYN_OPCODE_WIDTH-1:0] rs_slot_opcode_q   [0:OPTN_RS_DEPTH-1];
    logic [OPTN_ADDR_WIDTH-1:0]    rs_slot_iaddr_q    [0:OPTN_RS_DEPTH-1];
    logic [OPTN_DATA_WIDTH-1:0]    rs_slot_insn_q     [0:OPTN_RS_DEPTH-1];
    logic                          rs_slot_src_rdy_q  [0:OPTN_RS_DEPTH-1] [0:1];
    logic [OPTN_DATA_WIDTH-1:0]    rs_slot_src_data_q [0:OPTN_RS_DEPTH-1] [0:1];
    logic [OPTN_ROB_IDX_WIDTH-1:0] rs_slot_src_tag_q  [0:OPTN_RS_DEPTH-1] [0:1];
    logic [OPTN_ROB_IDX_WIDTH-1:0] rs_slot_dst_tag_q  [0:OPTN_RS_DEPTH-1];
    logic                          rs_slot_empty_q    [0:OPTN_RS_DEPTH-1];

    logic                          rs_full;
    logic [OPTN_RS_DEPTH-1:0]      rs_empty;
    logic [OPTN_RS_DEPTH-1:0]      rs_issue_ready;
    logic [OPTN_RS_DEPTH-1:0]      rs_issue_select;
    logic [OPTN_RS_DEPTH-1:0]      rs_dispatch_select;
    logic [OPTN_RS_DEPTH-1:0]      rs_age_matrix      [0:OPTN_RS_DEPTH-1];
    logic [RS_IDX_WIDTH-1:0]       rs_slot_age_m      [0:OPTN_RS_DEPTH-1];
    logic [OPTN_DATA_WIDTH-1:0]    rs_slot_src_data   [0:OPTN_RS_DEPTH-1] [0:1];
    logic                          rs_slot_src_rdy    [0:OPTN_RS_DEPTH-1] [0:1];
    logic                          cdb_select         [0:OPTN_RS_DEPTH-1] [0:1] [0:OPTN_CDB_DEPTH-1];
    logic                          dispatching;
    logic                          issuing;
    logic [RS_IDX_WIDTH-1:0]       issue_slot;
    logic [OPTN_RS_DEPTH-1:0]      rs_slot_empty_mux;

    // This will produce a one-hot vector of the slot that will be used
    // to store the dispatched instruction
    assign rs_dispatch_select = {(OPTN_RS_DEPTH){i_rs_en}} & (rs_empty & ~(rs_empty - 1'b1));
    assign rs_full            = rs_empty == {(OPTN_RS_DEPTH){1'b0}};

    assign dispatching        = ~rs_full & i_rs_en;
    assign issuing            = (rs_issue_select != {(OPTN_RS_DEPTH){1'b0}});

    // The reservation station is full if there are no empty slots
    // Assert the stall signal in this situation
    // FIXME: Should be registered
    assign o_rs_stall         = rs_full;

    // Assign functional unit output
    always_ff @(posedge clk) begin
        if (~n_rst) o_fu_valid <= 1'b0;
        else        o_fu_valid <= i_fu_stall ? o_fu_valid : ~i_flush & issuing;
    end

    always_ff @(posedge clk) begin
        if (~i_fu_stall) begin
            o_fu_opcode <= rs_slot_opcode_q[issue_slot];
            o_fu_iaddr  <= rs_slot_iaddr_q[issue_slot];
            o_fu_insn   <= rs_slot_insn_q[issue_slot];
            o_fu_src_a  <= rs_slot_src_data_q[issue_slot][0];
            o_fu_src_b  <= rs_slot_src_data_q[issue_slot][1];
            o_fu_tag    <= rs_slot_dst_tag_q[issue_slot];
        end
    end

    // Generate the age matrix. A reservation station slot's age must be
    // greater than all other reservation station slots that are also ready to issue
    always_comb begin
        for (int i = 0; i < OPTN_RS_DEPTH; i++) begin
            for (int j = 0; j < OPTN_RS_DEPTH; j++) begin
                if (i == j) rs_age_matrix[i][j] = 1'b1;
                else        rs_age_matrix[i][j] = rs_slot_age_q[i] > rs_slot_age_q[j];
            end
        end
    end

    always_comb begin
        for (int i = 0; i < OPTN_RS_DEPTH; i++) begin
            rs_empty[i]        = rs_slot_empty_q[i];

            // A slot is ready to issue if it is not empty and has both it's source operands
            rs_issue_ready[i]  = ~rs_slot_empty_q[i] & rs_slot_src_rdy_q[i][0] & rs_slot_src_rdy_q[i][1];
        end

        for (int i = 0; i < OPTN_RS_DEPTH; i++) begin
            // Select the oldest slot that is ready to issue. The OR with the
            // complement of the issue_ready vector is to discard age comparisons
            // with slots that aren't ready to issue
            rs_issue_select[i] = ~i_fu_stall & &(rs_age_matrix[i] | ~rs_issue_ready) & rs_issue_ready[i];
        end
    end

    // Priority encoder to convert one-hot issue_select vector to binary RS slot #
    always_comb begin
        issue_slot = {(RS_IDX_WIDTH){1'b0}};

        for (int i = 0; i < OPTN_RS_DEPTH; i++) begin
            if (rs_issue_select[i]) begin
                issue_slot = RS_IDX_WIDTH'(i);
            end
        end
    end

    always_comb begin
        for (int i = 0; i < OPTN_RS_DEPTH; i++) begin
            logic [1:0] rs_slot_empty_sel;

            rs_slot_empty_sel = {rs_issue_select[i], rs_dispatch_select[i]};
            case (rs_slot_empty_sel)
                2'b00: rs_slot_empty_mux[i] = rs_slot_empty_q[i];
                2'b01: rs_slot_empty_mux[i] = 1'b0;
                2'b10: rs_slot_empty_mux[i] = 1'b1;
                2'b11: rs_slot_empty_mux[i] = 1'b1;
            endcase
        end
    end

    // The empty bit is only cleared if the slot will be used to hold the next
    // dispatched instruction. Set it if the slot is issuing or on a pipeline flush
    always_ff @(posedge clk) begin
        for (int i = 0; i < OPTN_RS_DEPTH; i++) begin
            if (~n_rst) rs_slot_empty_q[i] <= 1'b1;
            else        rs_slot_empty_q[i] <= i_flush | rs_slot_empty_mux[i];
        end
    end

    // A slot's age needs to be adjusted each time an instruction is issued or dispatched. If a new instruction is dispatched only, it
    // starts off with an age of 0 and all other slots' age are incremented. If an instruction is only issued then only the slots that have an age
    // greater than the issuing slot's age will be decremented. If an instruction is being dispatched and another instruction is being
    // issued in the same cycle, then we only increment those slots that have an age less than the issuing slot's age.
    always_comb begin
        for (int i = 0; i < OPTN_RS_DEPTH; i++) begin
            case ({dispatching, issuing})
                2'b00: rs_slot_age_m[i] = rs_slot_age_q[i];
                2'b01: rs_slot_age_m[i] = rs_slot_age_q[i] - RS_IDX_WIDTH'(rs_slot_age_q[i] > rs_slot_age_q[issue_slot]);
                2'b10: rs_slot_age_m[i] = {(RS_IDX_WIDTH){~rs_dispatch_select[i]}} & (rs_slot_age_q[i] + 1'b1);
                2'b11: rs_slot_age_m[i] = {(RS_IDX_WIDTH){~rs_dispatch_select[i]}} & (rs_slot_age_q[i] + RS_IDX_WIDTH'(rs_slot_age_q[i] < rs_slot_age_q[issue_slot]));
            endcase
        end
    end

    always_ff @(posedge clk) begin
        for (int i = 0; i < OPTN_RS_DEPTH; i++) begin
            rs_slot_age_q[i] <= rs_slot_age_m[i];
        end
    end

    // Update slot for newly dispatched instruction
    always_ff @(posedge clk) begin
        for (int i = 0; i < OPTN_RS_DEPTH; i++) begin
            if (rs_dispatch_select[i]) begin
                rs_slot_opcode_q[i]  <= i_rs_opcode;
                rs_slot_iaddr_q[i]   <= i_rs_iaddr;
                rs_slot_insn_q[i]    <= i_rs_insn;
                rs_slot_src_tag_q[i] <= '{i_rs_src_tag[0], i_rs_src_tag[1]};
                rs_slot_dst_tag_q[i] <= i_rs_dst_tag;
            end
        end
    end

    // Check both source tags for each RS slot to see if a CDB is broadcasting a matching tag
    always_comb begin
        for (int rs_idx = 0; rs_idx < OPTN_RS_DEPTH; rs_idx++) begin
            for (int src_idx = 0; src_idx < 2; src_idx++) begin
                for (int cdb_idx = 0; cdb_idx < OPTN_CDB_DEPTH; cdb_idx++) begin
                    cdb_select[rs_idx][src_idx][cdb_idx] = i_cdb_en[cdb_idx] & (i_cdb_tag[cdb_idx] == rs_slot_src_tag_q[rs_idx][src_idx]);
                end
            end
        end
    end

    // Grab data from the CDB for the source operands and set the ready bits to true
    // Don't mess with the src data if it's already "ready", regardless of what is being broadcast on the CDB!
    // This really only applies to ops that use X0 register since the src tag for the X0 register is always 0
    // which could possibly be a valid tag
    always_comb begin
        for (int rs_idx = 0; rs_idx < OPTN_RS_DEPTH; rs_idx++) begin
            for (int src_idx = 0; src_idx < 2; src_idx++) begin
                // Priority mux to select input from the CDB busses, where the higher "numbered" CDB bus gets priority
                // Of course, this shouldn't matter since the CDBs should never broadcast the same tag on the same cycle
                rs_slot_src_data[rs_idx][src_idx] = rs_slot_src_data_q[rs_idx][src_idx];

                for (int cdb_idx = 0; cdb_idx < OPTN_CDB_DEPTH; cdb_idx++) begin
                    if (~rs_slot_src_rdy_q[rs_idx][src_idx] & cdb_select[rs_idx][src_idx][cdb_idx]) begin
                        rs_slot_src_data[rs_idx][src_idx] = i_cdb_data[cdb_idx];
                    end
                end
            end
         end
    end

    // A slot's sources are ready if it's been previously marked ready or if any of the CDB busses broadcast a matching tag that the source is waiting on.
    always_comb begin
        for (int rs_idx = 0; rs_idx < OPTN_RS_DEPTH; rs_idx++) begin
            for (int src_idx = 0; src_idx < 2; src_idx++) begin
                rs_slot_src_rdy[rs_idx][src_idx] = rs_slot_src_rdy_q[rs_idx][src_idx];

                for (int cdb_idx = 0; cdb_idx < OPTN_CDB_DEPTH; cdb_idx++) begin
                    rs_slot_src_rdy[rs_idx][src_idx] = cdb_select[rs_idx][src_idx][cdb_idx] | rs_slot_src_rdy[rs_idx][src_idx];
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        for (int rs_idx = 0; rs_idx < OPTN_RS_DEPTH; rs_idx++) begin
            for (int src_idx = 0; src_idx < 2; src_idx++) begin
                rs_slot_src_rdy_q[rs_idx][src_idx]  <= rs_dispatch_select[rs_idx] ? i_rs_src_rdy[src_idx]  : rs_slot_src_rdy[rs_idx][src_idx];
                rs_slot_src_data_q[rs_idx][src_idx] <= rs_dispatch_select[rs_idx] ? i_rs_src_data[src_idx] : rs_slot_src_data[rs_idx][src_idx];
            end
        end
    end

endmodule
