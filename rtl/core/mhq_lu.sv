// MHQ lookup stage
// Lookup miss queue for address matches and generate byte select signals depending on store type

`include "common.svh"
import procyon_types::*;

module mhq_lu (
    input  logic                                 clk,
    input  logic                                 n_rst,

    // MHQ full signal and tail pointer and MHQ entries
    input  procyon_mhq_entry_t [`MHQ_DEPTH-1:0]  i_mhq_entries,
    input  procyon_mhq_tag_t                     i_mhq_tail,
    input  logic                                 i_mhq_full,

    // Bypass lookup address from the mhq_ex stage
    input  logic                                 i_mhq_ex_bypass_en,
    input  logic                                 i_mhq_ex_bypass_we,
    input  logic                                 i_mhq_ex_bypass_match,
    input  procyon_mhq_addr_t                    i_mhq_ex_bypass_addr,
    input  procyon_mhq_tag_select_t              i_mhq_ex_bypass_tag_select,

    // Lookup lsu func
    input  logic                                 i_mhq_lookup_valid,
    input  logic                                 i_mhq_lookup_dc_hit,
    input  procyon_addr_t                        i_mhq_lookup_addr,
    input  procyon_lsu_func_t                    i_mhq_lookup_lsu_func,
    input  procyon_data_t                        i_mhq_lookup_data,
    input  logic                                 i_mhq_lookup_we,

    // Outputs to next stage
    output logic                                 o_mhq_lu_en,
    output logic                                 o_mhq_lu_we,
    output procyon_dc_offset_t                   o_mhq_lu_offset,
    output procyon_data_t                        o_mhq_lu_wr_data,
    output procyon_byte_select_t                 o_mhq_lu_byte_select,
    output logic                                 o_mhq_lu_match,
    output procyon_mhq_tag_t                     o_mhq_lu_tag,
    output procyon_mhq_tag_select_t              o_mhq_lu_tag_select,
    output logic                                 o_mhq_lu_valid,
    output logic                                 o_mhq_lu_dirty,
    output procyon_mhq_addr_t                    o_mhq_lu_addr,
    output procyon_cacheline_t                   o_mhq_lu_data,
    output procyon_dc_byte_select_t              o_mhq_lu_byte_updated
);

    logic                                        mhq_lookup_en;
    logic                                        mhq_lookup_is_fill;
    procyon_mhq_addr_t                           mhq_lookup_addr;
    procyon_dc_offset_t                          mhq_lookup_offset;
    procyon_byte_select_t                        mhq_lookup_byte_select;
    logic                                        mhq_lookup_match;
    procyon_mhq_tag_t                            mhq_lookup_tag;
    procyon_mhq_tag_select_t                     mhq_lookup_tag_select;
    logic                                        bypass_en;

    assign mhq_lookup_is_fill                    = (i_mhq_lookup_lsu_func == LSU_FUNC_FILL);
    assign mhq_lookup_en                         = i_mhq_lookup_valid && ~mhq_lookup_is_fill && ~i_mhq_lookup_dc_hit && ~i_mhq_full;
    assign mhq_lookup_addr                       = i_mhq_lookup_addr[`ADDR_WIDTH-1:`DC_OFFSET_WIDTH];
    assign mhq_lookup_offset                     = i_mhq_lookup_addr[`DC_OFFSET_WIDTH-1:0];

    always_comb begin
        procyon_mhq_tag_select_t match_tag_select      = {(`MHQ_DEPTH){1'b0}};
        procyon_mhq_tag_select_t tail_tag_select       = {(`MHQ_DEPTH){1'b0}};
        logic                    mhq_ex_bypass_en      = 1'b0;


        // Convert tag pointer into tag select
        for (int i = 0; i < `MHQ_DEPTH; i++) begin
            tail_tag_select[i] = (procyon_mhq_tag_t'(i) == i_mhq_tail);
        end

        // Check each valid entry for a matching lookup address
        for (int i = 0; i < `MHQ_DEPTH; i++) begin
            match_tag_select[i] = i_mhq_entries[i].valid && (i_mhq_entries[i].addr == mhq_lookup_addr);
        end

        // If match_tag_select is non-zero than we have found a match
        mhq_lookup_match = (match_tag_select != {(`MHQ_DEPTH){1'b0}});

        // Bypass lookup address from mhq_ex stage if possible
        // If there was no match then the tag is at the tail pointer (i.e. new entry)
        mhq_ex_bypass_en        = i_mhq_ex_bypass_en || (i_mhq_ex_bypass_we && i_mhq_ex_bypass_match);
        bypass_en               = (mhq_ex_bypass_en && (i_mhq_ex_bypass_addr == mhq_lookup_addr));
        mhq_lookup_tag_select   = bypass_en ? i_mhq_ex_bypass_tag_select : (mhq_lookup_match ? match_tag_select : tail_tag_select);
    end

    // Convert one-hot mhq_lookup_tag_select vector into binary tag #
    always_comb begin
        mhq_lookup_tag = {(`MHQ_TAG_WIDTH){1'b0}};

        for (int i = 0; i < `MHQ_DEPTH; i++) begin
            if (mhq_lookup_tag_select[i]) begin
                mhq_lookup_tag = procyon_mhq_tag_t'(i);
            end
        end
    end

    // Generate byte select signals based on store type
    always_comb begin
        case (i_mhq_lookup_lsu_func)
            LSU_FUNC_SB: mhq_lookup_byte_select = procyon_byte_select_t'(1);
            LSU_FUNC_SH: mhq_lookup_byte_select = procyon_byte_select_t'(3);
            LSU_FUNC_SW: mhq_lookup_byte_select = procyon_byte_select_t'(15);
            default:     mhq_lookup_byte_select = procyon_byte_select_t'(0);
        endcase
    end

    // Register outputs to next stage
    always_ff @(posedge clk) begin
        if (~n_rst) o_mhq_lu_en <= 1'b0;
        else        o_mhq_lu_en <= mhq_lookup_en;
    end

    always_ff @(posedge clk) begin
        o_mhq_lu_we           <= i_mhq_lookup_we;
        o_mhq_lu_offset       <= mhq_lookup_offset;
        o_mhq_lu_wr_data      <= i_mhq_lookup_data;
        o_mhq_lu_byte_select  <= mhq_lookup_byte_select;
        o_mhq_lu_match        <= mhq_lookup_match;
        o_mhq_lu_tag          <= mhq_lookup_tag;
        o_mhq_lu_tag_select   <= mhq_lookup_tag_select;
        o_mhq_lu_valid        <= i_mhq_entries[mhq_lookup_tag].valid;
        o_mhq_lu_dirty        <= i_mhq_entries[mhq_lookup_tag].dirty;
        o_mhq_lu_addr         <= mhq_lookup_addr;
        o_mhq_lu_data         <= i_mhq_entries[mhq_lookup_tag].data;
        o_mhq_lu_byte_updated <= i_mhq_entries[mhq_lookup_tag].byte_updated;
    end

endmodule