// MHQ lookup stage
// Lookup MHQ for address matches and generate byte select signals depending on store type

`include "common.svh"
import procyon_types::*;

module mhq_lu (
    input  logic                                 clk,
    input  logic                                 n_rst,

    // MHQ head and tail pointers (adusted for next cycle value) and MHQ entries
    input  procyon_mhq_entry_t [`MHQ_DEPTH-1:0]  i_mhq_entries,
    input  procyon_mhq_tagp_t                    i_mhq_tail_next,
    input  procyon_mhq_tagp_t                    i_mhq_head_next,

    // Bypass lookup address from the mhq_ex stage
    input  logic                                 i_mhq_ex_bypass_en,
    input  logic                                 i_mhq_ex_bypass_we,
    input  logic                                 i_mhq_ex_bypass_match,
    input  procyon_mhq_addr_t                    i_mhq_ex_bypass_addr,
    input  procyon_mhq_tag_t                     i_mhq_ex_bypass_tag,

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
    output procyon_mhq_addr_t                    o_mhq_lu_addr,
    output logic                                 o_mhq_lu_retry,

    // CCU interface to check for fill conflicts
    input  logic                                 i_ccu_done,
    input  procyon_addr_t                        i_ccu_addr
);

    typedef logic [`MHQ_DEPTH-1:0]               mhq_tag_select_t;

    procyon_mhq_tag_t                            mhq_tail_addr;
    logic                                        mhq_full_next;
    logic                                        mhq_lookup_en;
    logic                                        mhq_lookup_is_fill;
    logic                                        mhq_lookup_retry;
    procyon_mhq_addr_t                           mhq_lookup_addr;
    procyon_dc_offset_t                          mhq_lookup_offset;
    procyon_byte_select_t                        mhq_lookup_byte_select;
    logic                                        mhq_lookup_match;
    procyon_mhq_tag_t                            mhq_lookup_tag;
    mhq_tag_select_t                             mhq_lookup_tag_select;
    logic                                        mhq_ex_bypass_en;
    logic                                        bypass_en;

    // Calculate if the MHQ will be full on the next cycle
    assign mhq_tail_addr                         = i_mhq_tail_next[`MHQ_TAG_WIDTH-1:0];
    assign mhq_full_next                         = ({~i_mhq_tail_next[`MHQ_TAG_WIDTH], i_mhq_tail_next[`MHQ_TAG_WIDTH-1:0]} == i_mhq_head_next);

    // Determine if MHQ request in EX stage is going to enqueue and bypass if the lookup address matches the address in the next stage
    assign mhq_ex_bypass_en                      = i_mhq_ex_bypass_en | (i_mhq_ex_bypass_we & i_mhq_ex_bypass_match);
    assign bypass_en                             = (mhq_ex_bypass_en & (i_mhq_ex_bypass_addr == mhq_lookup_addr));

    // mhq_lookup_retry is asserted if the MHQ is full and there was no match OR if the CCU signals a fill on the same cycle with the same address as the lookup
    // The same cycle fill case causes a fill conflict where the lookup will return an MHQ tag and enqueue on that entry when it will be invalidated by the current fill
    assign mhq_lookup_is_fill                    = (i_mhq_lookup_lsu_func == LSU_FUNC_FILL);
    assign mhq_lookup_en                         = i_mhq_lookup_valid & ~mhq_lookup_is_fill & ~i_mhq_lookup_dc_hit & ~mhq_full_next;
    assign mhq_lookup_addr                       = i_mhq_lookup_addr[`ADDR_WIDTH-1:`DC_OFFSET_WIDTH];
    assign mhq_lookup_offset                     = i_mhq_lookup_addr[`DC_OFFSET_WIDTH-1:0];
    assign mhq_lookup_retry                      = (mhq_full_next & ~mhq_lookup_match) | (i_ccu_done & (i_ccu_addr == i_mhq_lookup_addr));

    always_comb begin
        mhq_tag_select_t match_tag_select        = {(`MHQ_DEPTH){1'b0}};
        mhq_tag_select_t tail_tag_select         = {(`MHQ_DEPTH){1'b0}};
        mhq_tag_select_t bypass_tag_select       = {(`MHQ_DEPTH){1'b0}};
        logic            lookup_match            = 1'b0;

        // Convert bypass tag into tag select
        for (int i = 0; i < `MHQ_DEPTH; i++) begin
            bypass_tag_select[i] = (procyon_mhq_tag_t'(i) == i_mhq_ex_bypass_tag);
        end

        // Convert tag pointer into tag select
        for (int i = 0; i < `MHQ_DEPTH; i++) begin
            tail_tag_select[i] = (procyon_mhq_tag_t'(i) == mhq_tail_addr);
        end

        // Check each valid entry for a matching lookup address
        for (int i = 0; i < `MHQ_DEPTH; i++) begin
            match_tag_select[i] = i_mhq_entries[i].valid & (i_mhq_entries[i].addr == mhq_lookup_addr);
        end

        // If match_tag_select is non-zero than we have found a match
        lookup_match            = (match_tag_select != {(`MHQ_DEPTH){1'b0}});

        // Bypass lookup address from mhq_ex stage if possible
        // If there was no match then the tag is at the tail pointer (i.e. new entry)
        mhq_lookup_tag_select   = bypass_en ? bypass_tag_select : (lookup_match ? match_tag_select : tail_tag_select);

        // If either lookup_match or bypass_en is true then we have found a match (either in the MHQ or from the bypass)
        mhq_lookup_match        = i_mhq_lookup_valid & (lookup_match | bypass_en);
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
        o_mhq_lu_addr         <= mhq_lookup_addr;
        o_mhq_lu_retry        <= mhq_lookup_retry;
    end

endmodule
