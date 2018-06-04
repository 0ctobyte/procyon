// Miss Status Handling Queue

`include "common.svh"
import procyon_types::*;

module mhq (
    input  logic                                     clk,
    input  logic                                     n_rst,

    // LSU enqueue request
    input  logic                                     i_mhq_enq_en,
    input  logic                                     i_mhq_enq_we,
    input  procyon_addr_t                            i_mhq_enq_addr,
    input  procyon_byte_select_t                     i_mhq_enq_byte_select,
    input  procyon_data_t                            i_mhq_enq_data,
    output procyon_mhq_tag_t                         o_mhq_enq_tag,
    output logic                                     o_mhq_full,

    // LSU fill broadcast
    output logic                                     o_mhq_fill,
    output procyon_mhq_tag_t                         o_mhq_fill_tag,

    // Cache fill interface
    output logic                                     o_dc_fe,
    output logic                                     o_dc_valid,
    output logic                                     o_dc_dirty,
    output procyon_addr_t                            o_dc_addr,
    output procyon_dc_data_t                         o_dc_fdata,

    // BIU interface
    input  logic                                     i_biu_done,
    input  procyon_dc_data_t                         i_biu_data,
    output procyon_addr_t                            o_biu_addr,
    output logic                                     o_biu_req_en
);

    typedef struct {
        logic                     valid;
        logic                     dirty;
        logic [`DC_LINE_SIZE-1:0] byte_updated;
        procyon_dc_addr_t         addr;
        procyon_dc_data_t         data;
    } mhq_entry_t;

    typedef struct {
        procyon_mhq_tagp_t        phead;
        procyon_mhq_tagp_t        ptail;
        procyon_mhq_tag_t         head;
        procyon_mhq_tag_t         tail;
        logic                     full;
        mhq_entry_t               entries [`MHQ_DEPTH-1:0];
    } mhq_t;

    mhq_t                         mhq;
    logic [`MHQ_DEPTH-1:0]        mhq_enq_match;
    procyon_mhq_tag_t             mhq_enq_tag;
    logic                         mhq_enq_alloc_en;
    logic                         mhq_enq_we;
    procyon_dc_addr_t             mhq_enq_addr;
    procyon_dc_offset_t           mhq_enq_offset;
    procyon_dc_data_t             mhq_enq_data;
    logic [`DC_LINE_SIZE-1:0]     mhq_enq_byte_en;

    assign mhq.head          = mhq.phead[`MHQ_TAG_WIDTH-1:0];
    assign mhq.tail          = mhq.ptail[`MHQ_TAG_WIDTH-1:0];
    assign mhq.full          = ({~mhq.tail[`MHQ_TAG_WIDTH], mhq.tail[`MHQ_TAG_WIDTH-1:0]} == mhq.head);

    // Enqueue miss request only if the miss address doesn't match an existing entry in the MHQ
    assign mhq_enq_alloc_en  = i_mhq_enq_en && ~|(mhq_enq_match);
    assign mhq_enq_we        = i_mhq_enq_en && i_mhq_enq_we;
    assign mhq_enq_addr      = i_mhq_enq_addr[`ADDR_WIDTH-1:`DC_OFFSET_WIDTH];
    assign mhq_enq_offset    = i_mhq_enq_addr[`DC_OFFSET_WIDTH-1:0];
    assign mhq_enq_byte_en   = i_mhq_enq_byte_select << mhq_enq_offset;
    assign mhq_enq_data      = i_mhq_enq_data << mhq_enq_offset;

    // Send mhq enqueue tag and full status to LSU
    assing o_mhq_enq_tag     = mhq_enq_tag;
    assign o_mhq_full        = mhq.full;

    // Broadcast to LSU to mark waiting loads as ready when data comes back from BIU
    assign o_mhq_fill        = i_biu_done;
    assign o_mhq_fill_tag    = mhq.head;

    // Assign cache fill signals
    assign o_dc_fe           = i_biu_done;
    assign o_dc_valid        = mhq.entries[mhq.head].valid;
    assign o_dc_dirty        = mhq.entries[mhq.head].dirty;
    assign o_dc_addr         = {mhq.entries[mhq.head].addr, {{(`DC_OFFSET_WIDTH){1'b0}}}};

    // Send request ot BIU
    assign o_biu_addr        = {mhq.entries[mhq.head].addr, {(`DC_OFFSET_WIDTH){1'b0}}};
    assign o_biu_req_en      = mhq.entries[mhq.head].valid;

    // When the BIU sends data back for a miss request, select updated data
    // from the MHQ entry or from the data returning from the BIU
    always_comb begin
        for (int i = 0; i < `DC_LINE_SIZE; i++) begin
            o_dc_fdata[i*8 +: 8] = mhq.entries[mhq.head].byte_updated[i] ? mhq.entries[mhq.head].data[i*8 +: 8] : i_biu_data[i*8 +: 8];
        end
    end

    // Check if miss request address matches an address in existing valid entry
    always_comb begin
        for (int i = 0; i < MHQ_DEPTH; i++) begin
            mhq_enq_match[i] = (mhq_enq_addr == mhq.entries[i].addr) && mhq.entries[i].valid;
        end
    end

    always_comb begin
        logic [$clog2(MHQ_DEPTH)-1:0] r;
        r = 0;
        for (int i = 0; i < MHQ_DEPTH; i++) begin
            if (mhq_enq_match[i]) begin
                r = r | i;
            end
        end
        mhq_enq_tag = mhq_enq_alloc_en ? mhq.tail : r;
    end

    // Enqueue a new entry if a new miss request does not match an existing entry
    // Clear the valid bit when data is returned by the BIU
    // On a flush, make sure to not flush valid, dirty entries
    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            for (int i = 0; i < `MHQ_DEPTH; i++) begin
                mhq.entries[i].valid <= 1'b0;
            end
        end else if (mhq_enq_alloc_en) begin
            mhq.entries[mhq_enq_tag].valid <= 1'b1;
        end else if (i_biu_done) begin
            mhq.entries[mhq.head].valid <= 1'b0;
        end
    end

    // Clear the dirty bit when entry is dequeued otherwise set the bit for writes
    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            for (int i = 0; i < `MHQ_DEPTH; i++) begin
                mhq.entries[i].dirty <= 1'b0;
            end
        end else if (mhq_enq_we) begin
            mhq.entries[mhq_enq_tag].dirty <= 1'b1;
        end else if (i_biu_done) begin
            mhq.entries[mhq.head].dirty <= 1'b0;
        end
    end

    // Update the byte_updated field on a write. Clear it when the entry is dequeued
    always_ff @(posedge clki negedge n_rst) begin
        if (~n_rst) begin
            for (int i = 0; i < `MHQ_DEPTH; i++) begin
                mhq.entries[i].byte_updated <= {{(`DC_LINE_SIZE){1'b0}}};
            end
        end else if (mhq_enq_we) begin
            mhq.entries[mhq_enq_tag].byte_updated <= mhq.entries[mhq_enq_tag].byte_updated | mhq_enq_byte_en;
        end else if (i_biu_done) begin
            mhq.entries[mhq.head].byte_updated <= {{(`DC_LINE_SIZE){1'b0}}};
        end
    end

    // Update the entry's address when allocating a new entry
    always_ff @(posedge clk) begin
        if (mhq_enq_alloc_en) begin
            mhq.entries[mhq_enq_tag].addr <= i_mhq_enq_addr;
        end
    end

    // Update the entry's data field on a write
    always_ff @(posedge clk) begin
        for (int i = 0; i < `DC_LINE_SIZE; i++) begin
            if (mhq_enq_we && mhq_enq_byte_en[i]) begin
                mhq.entries[mhq_enq_tag].data[i*8 +: 8] <= mhq_enq_data[i*8 +: 8];
            end
        end
    end

    // Increment tail whenever a new miss request is enqueued (and doesn't match an existing entry in the MHQ)
    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            mhq.ptail <= {{(`MHQ_TAG_WIDTH+1){1'b0}}};
        end else if (mhq_enq_alloc_en) begin
            mhq.ptail <= mhq.ptail + 1'b1;
        end
    end

    // Increment head when we receive ack from the BIU
    // Or, skip entries if they have been invalidated
    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            mhq.phead <= {{(`MHQ_TAG_WIDTH+1){1'b0}}};
        end else if (i_biu_done) begin
            mhq.phead <= mhq.phead + 1'b1;
        end
    end

endmodule;
