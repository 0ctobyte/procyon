// MHQ execute stage
// Enqueue entries and handle fills from the CCU

`include "common.svh"
import procyon_types::*;

module mhq_ex (
    input  logic                                 clk,
    input  logic                                 n_rst,

    // MHQ head, tail pointers and MHQ entries
    input  procyon_mhq_entry_t [`MHQ_DEPTH-1:0]  i_mhq_entries,
    output procyon_mhq_entry_t [`MHQ_DEPTH-1:0]  o_mhq_entries,
    output procyon_mhq_tagp_t                    o_mhq_head_next,
    output procyon_mhq_tagp_t                    o_mhq_tail_next,

    // Input from lookup stage
    input  logic                                 i_mhq_lu_en,
    input  logic                                 i_mhq_lu_we,
    input  procyon_dc_offset_t                   i_mhq_lu_offset,
    input  procyon_data_t                        i_mhq_lu_wr_data,
    input  procyon_byte_select_t                 i_mhq_lu_byte_select,
    input  logic                                 i_mhq_lu_match,
    input  procyon_mhq_tag_t                     i_mhq_lu_tag,
    input  procyon_mhq_addr_t                    i_mhq_lu_addr,

    // Fill interface
    output logic                                 o_mhq_fill_en,
    output procyon_mhq_tag_t                     o_mhq_fill_tag,
    output logic                                 o_mhq_fill_dirty,
    output procyon_addr_t                        o_mhq_fill_addr,
    output procyon_cacheline_t                   o_mhq_fill_data,

    // CCU interface
    input  logic                                 i_ccu_done,
    input  procyon_cacheline_t                   i_ccu_data,
    output logic                                 o_ccu_en,
    output procyon_addr_t                        o_ccu_addr
);

    typedef logic [`MHQ_DEPTH-1:0]               mhq_tag_select_t;

    procyon_mhq_tagp_t                           mhq_head;
    procyon_mhq_tagp_t                           mhq_tail;
    procyon_mhq_tagp_t                           mhq_head_next;
    procyon_mhq_tagp_t                           mhq_tail_next;
    procyon_mhq_tag_t                            mhq_head_addr;
    mhq_tag_select_t                             mhq_valid_next;
    logic                                        mhq_ex_en;
    logic                                        mhq_ex_alloc;
    logic                                        mhq_ex_dirty;
    procyon_cacheline_t                          mhq_ex_data;
    procyon_dc_byte_select_t                     mhq_ex_byte_updated;
    procyon_addr_t                               mhq_fill_addr;
    procyon_cacheline_t                          mhq_fill_data;

    assign mhq_ex_en                             = i_mhq_lu_en | (i_mhq_lu_we & i_mhq_lu_match);
    assign mhq_ex_alloc                          = mhq_ex_en & ~i_mhq_lu_match;

    // Calculate next head, tail and full signals
    assign mhq_head_addr                         = mhq_head[`MHQ_TAG_WIDTH-1:0];
    assign mhq_head_next                         = i_ccu_done ? mhq_head + 1'b1 : mhq_head;
    assign mhq_tail_next                         = mhq_ex_alloc ? mhq_tail + 1'b1 : mhq_tail;

    // These should not be registered. Send these signals back to the MHQ_LU stage
    assign o_mhq_head_next                       = mhq_head_next;
    assign o_mhq_tail_next                       = mhq_tail_next;

    // Signal to CCU to fetch data from memory
    // FIXME These should be registered
    assign o_ccu_addr                            = mhq_fill_addr;
    assign o_ccu_en                              = i_mhq_entries[mhq_head_addr].valid;

    always_comb begin
        // Generate valid bit depending on i_ccu_done and mhq_ex_en
        for (int i = 0; i < `MHQ_DEPTH; i++) begin
            mhq_valid_next[i] = ~(i_ccu_done & (procyon_mhq_tag_t'(i) == mhq_head_addr)) & (((procyon_mhq_tag_t'(i) == i_mhq_lu_tag) & mhq_ex_en) | i_mhq_entries[i].valid);
        end
    end

    always_comb begin
        // Merge write data into miss queue entry and update the byte_updated field
        mhq_ex_dirty        = i_mhq_lu_we | (~mhq_ex_alloc & i_mhq_entries[i_mhq_lu_tag].dirty);
        mhq_ex_data         = i_mhq_entries[i_mhq_lu_tag].data;
        mhq_ex_byte_updated = {(`DC_LINE_SIZE){~mhq_ex_alloc}} & i_mhq_entries[i_mhq_lu_tag].byte_updated;
        for (int i = 0; i < `DC_LINE_SIZE; i++) begin
            if (procyon_dc_offset_t'(i) == i_mhq_lu_offset) begin
                for (int j = 0; j < (4 < (`DC_LINE_SIZE-i) ? 4 : (`DC_LINE_SIZE-i)); j++) begin
                    mhq_ex_data[(i+j)*8 +: 8] = (i_mhq_lu_we & i_mhq_lu_byte_select[j]) ? i_mhq_lu_wr_data[j*8 +: 8] : mhq_ex_data[(i+j)*8 +: 8];
                    mhq_ex_byte_updated[i+j]  = (i_mhq_lu_we & i_mhq_lu_byte_select[j]) | mhq_ex_byte_updated[i+j];
                end
            end
        end
    end

    // Merge fill data with updated bytes from MHQ and currently enqueuing store if necessary
    always_comb begin
        logic [1:0] mhq_fill_data_mux_sel [`DC_LINE_SIZE-1:0];
        logic mhq_ex_fill_merge;

        mhq_fill_addr     = {i_mhq_entries[mhq_head_addr].addr, {(`DC_OFFSET_WIDTH){1'b0}}};
        mhq_fill_data     = {(`DC_LINE_WIDTH){1'b0}};
        mhq_ex_fill_merge = (mhq_ex_en & i_mhq_lu_we & (i_mhq_lu_addr == i_mhq_entries[mhq_head_addr].addr));

        // Merge data from the CCU and updated data in the MHQ entry (based on the byte_updated field)
        // Also merge data from current enqueue request to the same entry as the fill if there is one (this one takes priority)
        for (int i = 0; i < `DC_LINE_SIZE; i++) begin
            // Generate mux select signals for the fill data
            mhq_fill_data_mux_sel[i] = {(mhq_ex_fill_merge & mhq_ex_byte_updated[i]), i_mhq_entries[mhq_head_addr].byte_updated[i]};
            mhq_fill_data[i*8 +: 8]  = mux4_8b(i_ccu_data[i*8 +: 8], i_mhq_entries[mhq_head_addr].data[i*8 +: 8], mhq_ex_data[i*8 +: 8], mhq_ex_data[i*8 +: 8], mhq_fill_data_mux_sel[i]);
        end
    end

    // Enqueue new entry. This could be merged with an existing entry
    always_ff @(posedge clk) begin
        for (int i = 0; i < `MHQ_DEPTH; i++) begin
            if (~n_rst) o_mhq_entries[i].valid <= 1'b0;
            else        o_mhq_entries[i].valid <= mhq_valid_next[i];
        end
    end

    always_ff @(posedge clk) begin
        if (mhq_ex_en) begin
            o_mhq_entries[i_mhq_lu_tag].dirty        <= mhq_ex_dirty;
            o_mhq_entries[i_mhq_lu_tag].addr         <= i_mhq_lu_addr;
            o_mhq_entries[i_mhq_lu_tag].data         <= mhq_ex_data;
            o_mhq_entries[i_mhq_lu_tag].byte_updated <= mhq_ex_byte_updated;
        end
    end

    // Output for fill request
    always_ff @(posedge clk) begin
        o_mhq_fill_en    <= i_ccu_done;
        o_mhq_fill_tag   <= mhq_head_addr;
        o_mhq_fill_dirty <= i_mhq_entries[mhq_head_addr].dirty;
        o_mhq_fill_addr  <= mhq_fill_addr;
        o_mhq_fill_data  <= mhq_fill_data;
    end

    // Update mhq head and tail pointers
    always_ff @(posedge clk) begin
        if (~n_rst) mhq_head <= {(`MHQ_TAG_WIDTH+1){1'b0}};
        else        mhq_head <= mhq_head_next;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) mhq_tail <= {(`MHQ_TAG_WIDTH+1){1'b0}};
        else        mhq_tail <= mhq_tail_next;
    end

endmodule
