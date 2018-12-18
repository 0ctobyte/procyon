// Miss Handling Queue
// Queue for loads or stores that miss in the cache
// Merges missed loads if the load address already exists in the queue
// Stores will be merged with existing entries as well
// The data read from memory will be merged with updated bytes in the entry
// due to stores

`include "common.svh"
import procyon_types::*;

module mhq (
    input  logic                   clk,
    input  logic                   n_rst,

    // Match lookup address to valid entries to find enqueue tag
/* verilator lint_off UNUSED */
    input  procyon_addr_t          i_mhq_lookup_addr,
/* verilator lint_on  UNUSED */
    output logic                   o_mhq_lookup_full,
    output logic                   o_mhq_lookup_match,
    output procyon_mhq_tag_t       o_mhq_lookup_tag,

    // Fill cacheline
    output logic                   o_mhq_fill_en,
    output procyon_mhq_tag_t       o_mhq_fill_tag,
    output logic                   o_mhq_fill_dirty,
    output procyon_addr_t          o_mhq_fill_addr,
    output procyon_cacheline_t     o_mhq_fill_data,

    // MHQ enqueue interface
    input  logic                   i_mhq_enq_en,
    input  logic                   i_mhq_enq_we,
    input  logic                   i_mhq_enq_match,
    input  procyon_mhq_tag_t       i_mhq_enq_tag,
    input  procyon_addr_t          i_mhq_enq_addr,
    input  procyon_data_t          i_mhq_enq_data,
    input  procyon_byte_select_t   i_mhq_enq_byte_select,

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
    mhq_addr_t           mhq_enq_addr;
    dc_offset_t          mhq_enq_offset;
    dc_vec_t             mhq_enq_byte_updated;
    dc_vec_t             mhq_enq_byte_select;
    dc_vec_t             mhq_byte_offset_select [0:`WORD_SIZE-1];
    procyon_cacheline_t  mhq_fill_data;
    procyon_addr_t       mhq_fill_addr;
    procyon_mhq_tag_t    merge_tag;
    logic                filling;
    logic                allocating;
    logic                enqueuing;
    logic                lookup_match;
    mhq_vec_t            merge_select;
    mhq_addr_t           mhq_lookup_addr;

    assign mhq.head_addr           = mhq_head[`MHQ_TAG_WIDTH-1:0];
    assign mhq.tail_addr           = mhq_tail[`MHQ_TAG_WIDTH-1:0];
    assign mhq.full                = ({~mhq_tail[`MHQ_TAG_WIDTH], mhq_tail[`MHQ_TAG_WIDTH-1:0]} == mhq_head);

    assign lookup_match            = merge_select != {(`MHQ_DEPTH){1'b0}};
    assign mhq_lookup_addr         = i_mhq_lookup_addr[`ADDR_WIDTH-1:`DC_OFFSET_WIDTH];

    assign enqueuing               = i_mhq_enq_en;
    assign allocating              = enqueuing & ~i_mhq_enq_match;

    assign mhq.enqueue_select      = 1 << i_mhq_enq_tag;
    assign mhq_enq_addr            = i_mhq_enq_addr[`ADDR_WIDTH-1:`DC_OFFSET_WIDTH];
    assign mhq_enq_offset          = i_mhq_enq_addr[`DC_OFFSET_WIDTH-1:0];
    assign mhq_enq_byte_select     = {{(`DC_LINE_SIZE-`WORD_SIZE){1'b0}}, i_mhq_enq_byte_select};
    assign mhq_enq_byte_updated    = mhq_enq_byte_select << mhq_enq_offset;

    assign mhq_fill_addr           = {mhq_entries[mhq.head_addr].addr, {(`DC_OFFSET_WIDTH){1'b0}}};
    assign mhq.fill_select         = 1 << mhq.head_addr;
    assign filling                 = i_ccu_done;

    // Output to data cache for cache fill
    // FIXME: These should be registered
    assign o_mhq_fill_en           = filling;
    assign o_mhq_fill_tag          = mhq.head_addr;
    assign o_mhq_fill_dirty        = mhq_entries[mhq.head_addr].dirty;
    assign o_mhq_fill_addr         = mhq_fill_addr;
    assign o_mhq_fill_data         = mhq_fill_data;

    // Signal to CCU to fetch data from memory
    assign o_ccu_addr              = mhq_fill_addr;
    assign o_ccu_en                = mhq_entries[mhq.head_addr].valid;

    genvar gvar;
    generate
        // Check each valid entry for a matching address for lookup requests
        for (gvar = 0; gvar < `MHQ_DEPTH; gvar++) begin : ASSIGN_MERGE_SELECT_VECTOR
            // Bypass address lookup check when enqueuing an MHQ entry on the same cycle as the lookup
            assign merge_select[gvar] = (enqueuing & mhq.enqueue_select[gvar] & (mhq_enq_addr == mhq_lookup_addr)) | (mhq_entries[gvar].valid && (mhq_entries[gvar].addr == mhq_lookup_addr));
        end

        // Need to determine which bytes in the mhq entry data field are to be written
        for (gvar = 0; gvar < `WORD_SIZE; gvar++) begin : GENERATE_OFFSET_SELECT
            assign mhq_byte_offset_select[gvar] = 1 << (mhq_enq_offset + gvar);
        end
    endgenerate

    // Priority encoder to convert one-hot merge_select vector to binary slot #
    always_comb begin
        merge_tag = {($clog2(`MHQ_DEPTH)){1'b0}};

        for (int i = 0; i < `MHQ_DEPTH; i++) begin
            if (merge_select[i]) begin
                merge_tag = procyon_mhq_tag_t'(i);
            end
        end
    end

    // Combine data from memory and updated data in MHQ entry depending on the
    // byte_updated field
    always_comb begin
        for (int i = 0; i < `DC_LINE_SIZE; i++) begin
            mhq_fill_data[i*8 +: 8] = mhq_entries[mhq.head_addr].byte_updated[i] ? mhq_entries[mhq.head_addr].data[i*8 +: 8] : i_ccu_data[i*8 +: 8];
        end
    end

    always_ff @(posedge clk) begin
        o_mhq_lookup_tag   <= lookup_match ? merge_tag : mhq.tail_addr;
        o_mhq_lookup_match <= lookup_match;
        o_mhq_lookup_full  <= lookup_match ? 1'b0 : mhq.full;
    end

    // Update the MHQ entry on a new enqueue request
    // We need to clear the valid bit on a fill
    always_ff @(posedge clk) begin
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
                mhq_entries[i].dirty <= mhq_entries[i].dirty | i_mhq_enq_we;
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
    always_ff @(posedge clk) begin
        if (~n_rst) begin
            mhq_tail <= {{(`MHQ_TAG_WIDTH+1){1'b0}}};
        end else if (allocating) begin
            mhq_tail <= mhq_tail + 1'b1;
        end
    end

    // Increment the head pointer when BIU is done getting the data and the
    // data cache is being filled with the data
    always_ff @(posedge clk) begin
        if (~n_rst) begin
            mhq_head <= {{(`MHQ_TAG_WIDTH+1){1'b0}}};
        end else if (filling) begin
            mhq_head <= mhq_head + 1'b1;
        end
    end

endmodule
