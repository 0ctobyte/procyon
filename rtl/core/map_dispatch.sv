// Map & Dispatch
// Just registers it's inputs taking care of stall and flush conditions
// Also the reorder buffer enqueues the instruction in this cycle as well as looking up source operands 
// (i.e. mapping source operands) in the reorder buffer (bypassing from CDB if needed)

`include "common.svh"
import procyon_types::*;

module map_dispatch (
    input  logic             clk,
    input  logic             n_rst,

    input  logic             i_flush,
    input  logic             i_rob_stall,
    input  logic             i_rs_stall,

    // Reservation station enqueue signals from Stage 0
    input  logic             i_rs_en,
    input  procyon_opcode_t  i_rs_opcode,
    input  procyon_addr_t    i_rs_pc,
    input  procyon_data_t    i_rs_insn,
    input  procyon_tag_t     i_rs_dst_tag,

    // Reservation Staion enqueue signals
    output logic             o_rs_en,
    output procyon_opcode_t  o_rs_opcode,
    output procyon_addr_t    o_rs_pc,
    output procyon_data_t    o_rs_insn,
    output procyon_tag_t     o_rs_dst_tag
);

    always_ff @(posedge clk) begin
        if (~n_rst | i_flush)   o_rs_en <= 1'b0;
        else if (~i_rs_stall)   o_rs_en <= ~i_rob_stall & i_rs_en;
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
