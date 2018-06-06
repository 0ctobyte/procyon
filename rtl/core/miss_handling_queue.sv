// Miss Handling Queue
// Queue for loads or stores that miss in the cache
// Merges missed loads if the load address already exists in the queue
// Stores will be merged with existing entries as well
// The data read from memory will be merged with updated bytes in the entry
// due to stores

`include "common.svh"
import procyon_types::*;

module miss_handling_queue (
    input  logic                   clk,
    input  logic                   n_rst,

    // Indicate if MHQ is full
    output logic                   o_mhq_full,

    // Fill cacheline
    output logic                   o_mhq_fill,
    output procyon_mhq_tag_t       o_mhq_fill_tag,
    output logic                   o_mhq_fill_dirty,
    output procyon_addr_t          o_mhq_fill_addr,
    output procyon_cacheline_t     o_mhq_fill_data,

    // MHQ enqueue interface
    input  logic                   i_mhq_enq_en,
    input  logic                   i_mhq_enq_we,
    input  procyon_addr_t          i_mhq_enq_addr,
    input  procyon_data_t          i_mhq_enq_data,
    input  procyon_byte_select_t   i_mhq_enq_byte_select,
    output procyon_mhq_tag_t       o_mhq_enq_tag,

    // CCU interface
    input  logic                   i_ccu_done,
    input  procyon_cacheline_t     i_ccu_data,
    output procyon_addr_t          o_ccu_addr,
    output logic                   o_ccu_en
);

    typedef logic [`ADDR_WIDTH-`DC_OFFSET_WIDTH-1:0] mhq_addr_t;
    typedef logic [`MHQ_DEPTH-1:0]                   mhq_vec_t;
    typedef logic [`MHQ_TAG_WIDTH:0]                 mhq_tagp_t;
    typedef logic [`DC_LINE_SIZE-1:0]                dc_vec_t;
    typedef logic [`DC_OFFSET_WIDTH-1:0]             dc_offset_t;

    typedef struct packed {
        logic                valid;
        logic                dirty;
        mhq_addr_t           addr;
        procyon_cacheline_t  data;
        dc_vec_t             byte_updated;
    } mhq_entry_t;

    typedef struct packed {
        procyon_mhq_tag_t    head_addr;
        procyon_mhq_tag_t    tail_addr;
        logic                full;
        mhq_vec_t            merge_select;
        mhq_vec_t            enqueue_select;
        mhq_vec_t            fill_select;
    } mhq_t;

/* verilator lint_off MULTIDRIVEN */
    mhq_entry_t [`MHQ_DEPTH-1:0]   mhq_entries;
/* verilator lint_on  MULTIDRIVEN */
/* verilator lint_off UNOPTFLAT */
    mhq_t                          mhq;
/* verilator lint_on  UNOPTFLAT */

    mhq_tagp_t           mhq_head;
    mhq_tagp_t           mhq_tail;
    procyon_mhq_tag_t    mhq_enq_tag;
    mhq_addr_t           mhq_enq_addr;
    dc_offset_t          mhq_enq_offset;
    dc_vec_t             mhq_enq_byte_updated;
    dc_vec_t             mhq_enq_byte_select;
    dc_vec_t             mhq_byte_offset_select [0:`WORD_SIZE-1];
    procyon_cacheline_t  mhq_fill_data;
    procyon_addr_t       mhq_fill_addr;
    logic                filling;
    logic                merging;
    logic                allocating;
    logic                enqueuing;
    logic                enqueue_match;

    assign mhq.head_addr           = mhq_head[`MHQ_TAG_WIDTH-1:0];
    assign mhq.tail_addr           = mhq_tail[`MHQ_TAG_WIDTH-1:0];
    assign mhq.full                = ({~mhq_tail[`MHQ_TAG_WIDTH], mhq_tail[`MHQ_TAG_WIDTH-1:0]} == mhq_head);

    assign enqueue_match           = |(mhq.merge_select);
    assign mhq.enqueue_select      = enqueue_match ? mhq.merge_select : (1 << mhq.tail_addr);
    assign merging                 = i_mhq_enq_en && enqueue_match;
    assign allocating              = i_mhq_enq_en && ~mhq.full && ~enqueue_match;
    assign enqueuing               = merging || allocating;

    assign mhq_enq_addr            = i_mhq_enq_addr[`ADDR_WIDTH-1:`DC_OFFSET_WIDTH];
    assign mhq_enq_offset          = i_mhq_enq_addr[`DC_OFFSET_WIDTH-1:0];
    assign mhq_enq_byte_select     = {{(`DC_LINE_SIZE-`WORD_SIZE){1'b0}}, i_mhq_enq_byte_select};
    assign mhq_enq_byte_updated    = mhq_enq_byte_select << mhq_enq_offset;

    assign mhq_fill_addr           = {mhq_entries[mhq.head_addr].addr, {{(`DC_OFFSET_WIDTH){1'b0}}}};
    assign mhq.fill_select         = 1 << mhq.head_addr;
    assign filling                 = i_ccu_done;

    // Assign full signal
    assign o_mhq_full              = mhq.full;

    // Output mhq enqueue tag
    assign o_mhq_enq_tag           = mhq_enq_tag;

    // Output to data cache for cache fill
    assign o_mhq_fill              = filling;
    assign o_mhq_fill_tag          = mhq.head_addr;
    assign o_mhq_fill_dirty        = mhq_entries[mhq.head_addr].dirty;
    assign o_mhq_fill_addr         = mhq_fill_addr;
    assign o_mhq_fill_data         = mhq_fill_data;

    // Signal to CCU to fetch data from memory
    assign o_ccu_addr              = mhq_fill_addr;
    assign o_ccu_en                = mhq_entries[mhq.head_addr].valid;

    genvar gvar;
    generate
        // Check each valid entry for a matching address in order to merge new
        // enqueue requests instead of allocating a new entry
        for (gvar = 0; gvar < `MHQ_DEPTH; gvar++) begin : ASSIGN_MERGE_SELECT_VECTOR
            assign mhq.merge_select[gvar] = mhq_entries[gvar].valid && (mhq_entries[gvar].addr == mhq_enq_addr);
        end

        // Need to determine which bytes in the mhq entry data field are to be written
        for (gvar = 0; gvar < `WORD_SIZE; gvar++) begin : GENERATE_OFFSET_SELECT
            assign mhq_byte_offset_select[gvar] = 1 << (mhq_enq_offset + gvar);
        end
    endgenerate

    // Combine data from memory and updated data in MHQ entry depending on the
    // byte_updated field
    always_comb begin
        for (int i = 0; i < `DC_LINE_SIZE; i++) begin
            mhq_fill_data[i*8 +: 8] = mhq_entries[mhq.head_addr].byte_updated[i] ? mhq_entries[mhq.head_addr].data[i*8 +: 8] : i_ccu_data[i*8 +: 8];
        end
    end

    // Convert one-hot enqueue_select vector to binary MHQ tag
    always_comb begin
        int r;
        r = 0;
        for (int i = 0; i < `MHQ_DEPTH; i++) begin
            if (mhq.enqueue_select[i]) begin
                r = r | i;
            end
        end
        mhq_enq_tag = r[`MHQ_TAG_WIDTH-1:0];
    end

    // Update the MHQ entry on a new enqueue request
    // We need to clear the valid bit on a fill
    always_ff @(posedge clk, negedge n_rst) begin
        for (int i = 0; i < `MHQ_DEPTH; i++) begin
            if (~n_rst) begin
                mhq_entries[i].valid <= 1'b0;
            end else if (filling && mhq.fill_select[i]) begin
                mhq_entries[i].valid <= 1'b0;
            end else if (enqueuing && mhq.enqueue_select[i]) begin
                mhq_entries[i].valid <= 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        for (int i = 0; i < `MHQ_DEPTH; i++) begin
            if (enqueuing && mhq.enqueue_select[i]) begin
                mhq_entries[i].dirty <= i_mhq_enq_we;
                mhq_entries[i].addr  <= mhq_enq_addr;
            end
        end
    end

    // We need to clear the byte updated field after we are done with the entry
    always_ff @(posedge clk) begin
        for (int i = 0; i < `MHQ_DEPTH; i++) begin
            if (filling && mhq.fill_select[i]) begin
                mhq_entries[i].byte_updated <= {{(`DC_LINE_SIZE){1'b0}}};
            end else if (enqueuing && mhq.enqueue_select[i] && i_mhq_enq_we) begin
                mhq_entries[i].byte_updated <= mhq_entries[i].byte_updated | mhq_enq_byte_updated;
            end
        end
    end

    // Update the data field for enqueuing stores
    always_ff @(posedge clk) begin
        for (int i = 0; i < `MHQ_DEPTH; i++) begin
            if (enqueuing && mhq.enqueue_select[i] && i_mhq_enq_we) begin
                for (int j = 0; j < `DC_LINE_SIZE; j++) begin
                    for (int k = 0; k < `WORD_SIZE; k++) begin
                        if (mhq_byte_offset_select[k][j] && i_mhq_enq_byte_select[k]) begin
                            mhq_entries[i].data[j*8 +: 8] <= i_mhq_enq_data[k*8 +: 8];
                        end
                    end
                end
            end
        end
    end

    // Increment the tail pointer if a new request is being enqueued but there
    // was no entry that the request can be merged with
    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            mhq_tail <= {{(`MHQ_TAG_WIDTH+1){1'b0}}};
        end else if (allocating) begin
            mhq_tail <= mhq_tail + 1'b1;
        end
    end

    // Increment the head pointer when BIU is done getting the data and the
    // data cache is being filled with the data
    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            mhq_head <= {{(`MHQ_TAG_WIDTH+1){1'b0}}};
        end else if (filling) begin
            mhq_head <= mhq_head + 1'b1;
        end
    end

endmodule
