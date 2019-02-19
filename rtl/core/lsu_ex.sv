// LSU execute pipeline stage

`include "common.svh"
import procyon_types::*;

module lsu_ex (
    input  logic                     clk,
    input  logic                     n_rst,

    input  logic                     i_flush,

    // Inputs from previous pipeline stage
    input  logic                     i_valid,
    input  procyon_lsu_func_t        i_lsu_func,
    input  procyon_lq_select_t       i_lq_select,
    input  procyon_sq_select_t       i_sq_select,
    input  procyon_tag_t             i_tag,
    input  procyon_addr_t            i_addr,
    input  procyon_data_t            i_retire_data,
    input  logic                     i_retire,

    // Inputs from dcache
    input  logic                     i_dc_hit,
    input  procyon_data_t            i_dc_data,
    input  logic                     i_dc_victim_valid,
    input  logic                     i_dc_victim_dirty,
    input  procyon_addr_t            i_dc_victim_addr,
    input  procyon_cacheline_t       i_dc_victim_data,

    // Inputs from MHQ
    input  logic                     i_mhq_lookup_match,
    input  logic                     i_mhq_lookup_full,
    input  procyon_mhq_tag_t         i_mhq_lookup_tag,

    // Broadcast CDB results
    output logic                     o_valid,
    output procyon_data_t            o_data,
    output procyon_addr_t            o_addr,
    output procyon_tag_t             o_tag,

    // Update LQ/SQ
    output logic                     o_update_lq_en,
    output procyon_lq_select_t       o_update_lq_select,
    output logic                     o_update_lq_retry,
    output procyon_mhq_tag_t         o_update_lq_mhq_tag,
    output logic                     o_update_lq_mhq_full,
    output logic                     o_update_sq_en,
    output procyon_sq_select_t       o_update_sq_select,
    output logic                     o_update_sq_retry,

    // Enqueue signals to MHQ
    output logic                     o_mhq_enq_en,
    output logic                     o_mhq_enq_we,
    output logic                     o_mhq_enq_match,
    output procyon_mhq_tag_t         o_mhq_enq_tag,
    output procyon_addr_t            o_mhq_enq_addr,
    output procyon_data_t            o_mhq_enq_data,
    output procyon_byte_select_t     o_mhq_enq_byte_select,

    // Enqueue victim data
    output logic                     o_victim_en,
    output procyon_addr_t            o_victim_addr,
    output procyon_cacheline_t       o_victim_data
);

    logic                            is_fill;
    logic                            is_store;
    logic                            is_load;
    procyon_data_t                   load_data;
    procyon_byte_select_t            mhq_enq_byte_select;

    assign is_fill                   = i_lsu_func == LSU_FUNC_FILL;
    assign is_store                  = (i_lsu_func == LSU_FUNC_SB) | (i_lsu_func == LSU_FUNC_SH) | (i_lsu_func == LSU_FUNC_SW);
    assign is_load                   = ~is_fill & ~is_store;

    // LB and LH loads 8 bits or 16 bits respectively and sign extends to 32-bits.
    // LBU and LHU loads 8 bits or 16 bits respectively and zero extends to 32 bits.
    always_comb begin
        case (i_lsu_func)
            LSU_FUNC_LB:  load_data = {{(`DATA_WIDTH-8){i_dc_data[7]}}, i_dc_data[7:0]};
            LSU_FUNC_LH:  load_data = {{(`DATA_WIDTH-16){i_dc_data[15]}}, i_dc_data[15:0]};
            LSU_FUNC_LW:  load_data = i_dc_data;
            LSU_FUNC_LBU: load_data = {{(`DATA_WIDTH-8){1'b0}}, i_dc_data[7:0]};
            LSU_FUNC_LHU: load_data = {{(`DATA_WIDTH-16){1'b0}}, i_dc_data[15:0]};
            default:      load_data = i_dc_data;
        endcase
    end

    always_comb begin
        case (i_lsu_func)
            LSU_FUNC_SB: mhq_enq_byte_select = procyon_byte_select_t'(1);
            LSU_FUNC_SH: mhq_enq_byte_select = procyon_byte_select_t'(3);
            LSU_FUNC_SW: mhq_enq_byte_select = procyon_byte_select_t'(15);
            default:     mhq_enq_byte_select = procyon_byte_select_t'(15);
        endcase
    end

    always_ff @(posedge clk) begin
        o_data <= load_data;
        o_addr <= i_addr;
        o_tag  <= i_tag;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_valid <= 1'b0;
        else        o_valid <= ~i_flush & i_valid & ~is_fill & (i_dc_hit | is_store);
    end

    always_ff @(posedge clk) begin
        o_update_lq_select   <= i_lq_select;
        o_update_lq_retry    <= ~i_dc_hit;
        o_update_lq_mhq_tag  <= i_mhq_lookup_tag;
        o_update_lq_mhq_full <= i_mhq_lookup_full;
        o_update_sq_select   <= i_sq_select;
        o_update_sq_retry    <= ~i_dc_hit & i_mhq_lookup_full;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_update_lq_en <= 1'b0;
        else        o_update_lq_en <= ~i_flush & i_valid & is_load;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_update_sq_en <= 1'b0;
        else        o_update_sq_en <= ~i_flush & i_valid & i_retire;
    end

    always_ff @(posedge clk) begin
        o_mhq_enq_we          <= i_retire;
        o_mhq_enq_match       <= i_mhq_lookup_match;
        o_mhq_enq_tag         <= i_mhq_lookup_tag;
        o_mhq_enq_addr        <= i_addr;
        o_mhq_enq_data        <= i_retire_data;
        o_mhq_enq_byte_select <= mhq_enq_byte_select;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_mhq_enq_en <= 1'b0;
        else        o_mhq_enq_en <= i_valid & (~i_dc_hit | i_mhq_lookup_match) & ~is_fill & (~i_mhq_lookup_full | i_mhq_lookup_match);
    end

    always_ff @(posedge clk) begin
        o_victim_addr <= i_dc_victim_addr;
        o_victim_data <= i_dc_victim_data;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_victim_en <= 1'b0;
        else        o_victim_en <= i_valid & is_fill & i_dc_victim_valid & i_dc_victim_dirty;
    end

endmodule
