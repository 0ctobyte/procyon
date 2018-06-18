// LSU execute stage
// Grab data from D$ for loads and sign extend or zero extend if necessary

`include "common.svh"
import procyon_types::*;

module lsu_ex (
    // Inputs from last stage in the LSU pipeline
    input  procyon_lsu_func_t     i_lsu_func,
    input  procyon_addr_t         i_addr,
    input  procyon_cacheline_t    i_data,
    input  procyon_tag_t          i_tag,
    input  logic                  i_valid,
    input  logic                  i_retire,
    input  logic                  i_dirty,

    // Output to writeback stage
    output procyon_data_t         o_data,
    output procyon_addr_t         o_addr,
    output procyon_tag_t          o_tag,
    output logic                  o_valid,

    // Update LQ entries for loads that miss in the cache
    output logic                  o_update_lq_en,
    output procyon_mhq_tag_t      o_update_lq_mhq_tag,

    // Update SQ entry for retired stores to indicate success/failure
    output logic                  o_update_sq_en,

    // Access D$ data memory for load data and tag hit
    input  logic                  i_dc_hit,
    input  procyon_data_t         i_dc_data,
    output logic                  o_dc_we,
    output logic                  o_dc_fe,
    output procyon_addr_t         o_dc_addr,
    output procyon_cacheline_t    o_dc_data,
    output procyon_byte_select_t  o_dc_byte_select,
    output logic                  o_dc_fill_dirty,

    // Enqueue into MHQ on cache misses
    input  procyon_mhq_tag_t      i_mhq_enq_tag,
    output logic                  o_mhq_enq_en,
    output logic                  o_mhq_enq_we,
    output procyon_addr_t         o_mhq_enq_addr,
    output procyon_data_t         o_mhq_enq_data,
    output procyon_byte_select_t  o_mhq_enq_byte_select
);

    logic                 cache_miss;
    logic                 load_or_store;
    logic                 not_fill;
    procyon_byte_select_t byte_select;

    // Determine if op is load or store
    assign load_or_store         = (i_lsu_func == LSU_FUNC_SB) || (i_lsu_func == LSU_FUNC_SH) || (i_lsu_func == LSU_FUNC_SW);
    assign not_fill              = i_lsu_func != LSU_FUNC_FILL;
    assign cache_miss            = i_valid && ~i_dc_hit && not_fill;

    // Access D$
    assign o_dc_we               = i_valid && not_fill && i_retire;
    assign o_dc_addr             = i_addr;
    assign o_dc_data             = i_data;
    assign o_dc_byte_select      = byte_select;

    // Output to WB stage
    // Loads are "valid" if they hit in the cache and the cache isn't busy
    // Stores are "valid" if they aren't being retired (i.e. on the first pass through here)
    assign o_addr                = i_addr;
    assign o_tag                 = i_tag;
    assign o_valid               = i_valid && (load_or_store ? ~i_retire : i_dc_hit && not_fill);

    // Output to dcache on a cache fill
    assign o_dc_fe               = ~not_fill;
    assign o_dc_fill_dirty       = i_dirty;

    // Output to LQ
    assign o_update_lq_en        = cache_miss && ~load_or_store;
    assign o_update_lq_mhq_tag   = i_mhq_enq_tag;

    // Output to SQ
    assign o_update_sq_en        = i_retire && i_valid;

    // Output to MHQ
    // Only output retired stores to MHQ on a cache miss
    assign o_mhq_enq_en          = cache_miss && (~load_or_store || i_retire);
    assign o_mhq_enq_we          = i_retire;
    assign o_mhq_enq_addr        = i_addr;
    assign o_mhq_enq_data        = i_data[`DATA_WIDTH-1:0];
    assign o_mhq_enq_byte_select = byte_select;

    // SW writes to all 4 bytes, SH writes to 2 bytes and SB writes to 1 byte
    always_comb begin
        case (i_lsu_func)
            LSU_FUNC_SB: byte_select = 4'b0001;
            LSU_FUNC_SH: byte_select = 4'b0011;
            LSU_FUNC_SW: byte_select = 4'b1111;
            default:     byte_select = 4'b1111;
        endcase
    end

    // LB and LH loads 8 bits or 16 bits respectively and sign extends to
    // 32-bits. LBU and LHU loads 8 bits or 16 bits respectively and zero
    // extends to 32 bits.
    always_comb begin
        case (i_lsu_func)
            LSU_FUNC_LB:  o_data = {{(`DATA_WIDTH-8){i_dc_data[7]}}, i_dc_data[7:0]};
            LSU_FUNC_LH:  o_data = {{(`DATA_WIDTH-16){i_dc_data[15]}}, i_dc_data[15:0]};
            LSU_FUNC_LW:  o_data = i_dc_data;
            LSU_FUNC_LBU: o_data = {{(`DATA_WIDTH-8){1'b0}}, i_dc_data[7:0]};
            LSU_FUNC_LHU: o_data = {{(`DATA_WIDTH-16){1'b0}}, i_dc_data[15:0]};
            default:      o_data = i_dc_data;
        endcase
    end

endmodule
