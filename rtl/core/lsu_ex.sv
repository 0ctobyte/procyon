// LSU execute stage
// Grab data from D$ for loads and sign extend or zero extend if necessary

`include "common.svh"
import procyon_types::*;

module lsu_ex (
    // Inputs from last stage in the LSU pipeline
    input  procyon_lsu_func_t     i_lsu_func,
    input  procyon_addr_t         i_addr,
    input  procyon_tag_t          i_tag,
    input  logic                  i_valid,

    // Output to writeback stage
    output procyon_data_t         o_data,
    output procyon_addr_t         o_addr,
    output procyon_tag_t          o_tag,
    output logic                  o_valid,

    // Access D$ data memory for load data and tag hit
/* verilator lint_off UNUSED */
    input  logic                  i_dc_hit,
/* verilator lint_on  UNUSED */
    input  procyon_data_t         i_dc_rdata,
    output procyon_addr_t         o_dc_raddr,
    output logic                  o_dc_re
);

    // Access D$ data
    assign o_dc_raddr = i_addr;
    assign o_dc_re    = i_valid;

    // Output to WB stage
    assign o_addr     = i_addr;
    assign o_tag      = i_tag;

    // LB and LH loads 8 bits or 16 bits respectively and sign extends to
    // 32-bits. LBU and LHU loads 8 bits or 16 bits respectively and zero
    // extends to 32 bits.
    always_comb begin
        case (i_lsu_func)
            LSU_FUNC_LB:  o_data = {{(`DATA_WIDTH-8){i_dc_rdata[7]}}, i_dc_rdata[7:0]};
            LSU_FUNC_LH:  o_data = {{(`DATA_WIDTH-16){i_dc_rdata[15]}}, i_dc_rdata[15:0]};
            LSU_FUNC_LW:  o_data = i_dc_rdata;
            LSU_FUNC_LBU: o_data = {{(`DATA_WIDTH-8){1'b0}}, i_dc_rdata[7:0]};
            LSU_FUNC_LHU: o_data = {{(`DATA_WIDTH-16){1'b0}}, i_dc_rdata[15:0]};
            default:      o_data = i_dc_rdata;
        endcase
    end

    // o_valid = i_valid if the op is a store since stores "complete" here
    // For load ops, o_valid is only true if it hits in the D$
    // Only send to MSHQ if op is a load that misses in the D$
    always_comb begin
        case (i_lsu_func)
            LSU_FUNC_SB: o_valid = i_valid;
            LSU_FUNC_SH: o_valid = i_valid;
            LSU_FUNC_SW: o_valid = i_valid;
            default:     o_valid = i_valid;
        endcase
    end

endmodule
