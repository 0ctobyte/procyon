// Map & Dispatch
// Just registers it's inputs taking care of stall and flush conditions
// Also the reorder buffer enqueues the instruction in this cycle as well as looking up source operands
// (i.e. mapping source operands) in the reorder buffer (bypassing from CDB if needed)

`include "procyon_constants.svh"

module procyon_dispatch_md #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_ROB_IDX_WIDTH = 5
)(
    input  logic                          clk,
    input  logic                          n_rst,

    input  logic                          i_flush,
    input  logic                          i_rob_stall,
    input  logic                          i_rs_stall,

    // Reservation station enqueue signals from Stage 0
    input  logic                          i_rs_en,
    input  logic [`PCYN_OPCODE_WIDTH-1:0] i_rs_opcode,
    input  logic [OPTN_ADDR_WIDTH-1:0]    i_rs_pc,
    input  logic [OPTN_DATA_WIDTH-1:0]    i_rs_insn,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0] i_rs_dst_tag,

    // Reservation Staion enqueue signals
    output logic                          o_rs_en,
    output logic [`PCYN_OPCODE_WIDTH-1:0] o_rs_opcode,
    output logic [OPTN_ADDR_WIDTH-1:0]    o_rs_pc,
    output logic [OPTN_DATA_WIDTH-1:0]    o_rs_insn,
    output logic [OPTN_ROB_IDX_WIDTH-1:0] o_rs_dst_tag
);

    always_ff @(posedge clk) begin
        if (~n_rst | i_flush) o_rs_en <= 1'b0;
        else if (~i_rs_stall) o_rs_en <= ~i_rob_stall & i_rs_en;
    end

    always_ff @(posedge clk) begin
        if (~i_rs_stall) begin
            o_rs_opcode  <= i_rs_opcode;
            o_rs_pc      <= i_rs_pc;
            o_rs_insn    <= i_rs_insn;
            o_rs_dst_tag <= i_rs_dst_tag;
        end
    end

endmodule
