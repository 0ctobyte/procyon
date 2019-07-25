// MHQ execute stage
// Enqueue entries and handle fills from the CCU

module mhq_ex #(
    parameter OPTN_DATA_WIDTH   = 32,
    parameter OPTN_ADDR_WIDTH   = 32,
    parameter OPTN_MHQ_DEPTH    = 4,
    parameter OPTN_DC_LINE_SIZE = 32,

    localparam MHQ_IDX_WIDTH    = $clog2(OPTN_MHQ_DEPTH),
    localparam DC_LINE_WIDTH    = OPTN_DC_LINE_SIZE * 8,
    localparam DC_OFFSET_WIDTH  = $clog2(OPTN_DC_LINE_SIZE),
    localparam WORD_SIZE        = OPTN_DATA_WIDTH / 8
)(
    input  logic                                     clk,
    input  logic                                     n_rst,

    // MHQ head, tail pointers and MHQ entries
    output logic [MHQ_IDX_WIDTH:0]                   o_mhq_head_next,
    output logic [MHQ_IDX_WIDTH:0]                   o_mhq_tail_next,

    // Interface to lookup stage for mhq entry array valid and address bits
    output logic                                     o_mhq_entry_valid [0:OPTN_MHQ_DEPTH-1],
    output logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] o_mhq_entry_addr  [0:OPTN_MHQ_DEPTH-1],

    // Input from lookup stage
    input  logic                                     i_mhq_lu_en,
    input  logic                                     i_mhq_lu_we,
    input  logic [DC_OFFSET_WIDTH-1:0]               i_mhq_lu_offset,
    input  logic [OPTN_DATA_WIDTH-1:0]               i_mhq_lu_wr_data,
    input  logic [WORD_SIZE-1:0]                     i_mhq_lu_byte_select,
    input  logic                                     i_mhq_lu_match,
    input  logic [MHQ_IDX_WIDTH-1:0]                 i_mhq_lu_tag,
    input  logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] i_mhq_lu_addr,

    // Fill interface
    output logic                                     o_mhq_fill_en,
    output logic [MHQ_IDX_WIDTH-1:0]                 o_mhq_fill_tag,
    output logic                                     o_mhq_fill_dirty,
    output logic [OPTN_ADDR_WIDTH-1:0]               o_mhq_fill_addr,
    output logic [DC_LINE_WIDTH-1:0]                 o_mhq_fill_data,

    // CCU interface
    input  logic                                     i_ccu_done,
    input  logic [DC_LINE_WIDTH-1:0]                 i_ccu_data,
    output logic                                     o_ccu_en,
    output logic [OPTN_ADDR_WIDTH-1:0]               o_ccu_addr
);

    logic                                     mhq_entry_valid_q        [0:OPTN_MHQ_DEPTH-1];
    logic                                     mhq_entry_dirty_q        [0:OPTN_MHQ_DEPTH-1];
    logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] mhq_entry_addr_q         [0:OPTN_MHQ_DEPTH-1];
    logic [DC_LINE_WIDTH-1:0]                 mhq_entry_data_q         [0:OPTN_MHQ_DEPTH-1];
    logic [OPTN_DC_LINE_SIZE-1:0]             mhq_entry_byte_updated_q [0:OPTN_MHQ_DEPTH-1];


    logic [MHQ_IDX_WIDTH:0]                   mhq_head;
    logic [MHQ_IDX_WIDTH:0]                   mhq_tail;
    logic [MHQ_IDX_WIDTH:0]                   mhq_head_next;
    logic [MHQ_IDX_WIDTH:0]                   mhq_tail_next;
    logic [MHQ_IDX_WIDTH-1:0]                 mhq_head_addr;
    logic [OPTN_MHQ_DEPTH-1:0]                mhq_valid_next;
    logic                                     mhq_ex_en;
    logic                                     mhq_ex_alloc;
    logic                                     mhq_ex_dirty;
    logic [DC_LINE_WIDTH-1:0]                 mhq_ex_data;
    logic [OPTN_DC_LINE_SIZE-1:0]             mhq_ex_byte_updated;
    logic [OPTN_ADDR_WIDTH-1:0]               mhq_fill_addr;
    logic [DC_LINE_WIDTH-1:0]                 mhq_fill_data;

    assign mhq_ex_en         = i_mhq_lu_en | (i_mhq_lu_we & i_mhq_lu_match);
    assign mhq_ex_alloc      = mhq_ex_en & ~i_mhq_lu_match;

    // Calculate next head, tail and full signals
    assign mhq_head_addr     = mhq_head[MHQ_IDX_WIDTH-1:0];
    assign mhq_head_next     = i_ccu_done ? mhq_head + 1'b1 : mhq_head;
    assign mhq_tail_next     = mhq_ex_alloc ? mhq_tail + 1'b1 : mhq_tail;

    // These should not be registered. Send these signals back to the MHQ_LU stage
    assign o_mhq_head_next   = mhq_head_next;
    assign o_mhq_tail_next   = mhq_tail_next;
    assign o_mhq_entry_valid = mhq_entry_valid_q;
    assign o_mhq_entry_addr  = mhq_entry_addr_q;

    // Signal to CCU to fetch data from memory
    // FIXME These should be registered
    assign o_ccu_addr        = mhq_fill_addr;
    assign o_ccu_en          = mhq_entry_valid_q[mhq_head_addr];

    always_comb begin
        // Generate valid bit depending on i_ccu_done and mhq_ex_en
        for (int i = 0; i < OPTN_MHQ_DEPTH; i++) begin
            mhq_valid_next[i] = ~(i_ccu_done & (MHQ_IDX_WIDTH'(i) == mhq_head_addr)) & (((MHQ_IDX_WIDTH'(i) == i_mhq_lu_tag) & mhq_ex_en) | mhq_entry_valid_q[i]);
        end
    end

    always_comb begin
        // Merge write data into miss queue entry and update the byte_updated field
        mhq_ex_dirty        = i_mhq_lu_we | (~mhq_ex_alloc & mhq_entry_dirty_q[i_mhq_lu_tag]);
        mhq_ex_data         = mhq_entry_data_q[i_mhq_lu_tag];
        mhq_ex_byte_updated = {(OPTN_DC_LINE_SIZE){~mhq_ex_alloc}} & mhq_entry_byte_updated_q[i_mhq_lu_tag];

        for (int i = 0; i < OPTN_DC_LINE_SIZE; i++) begin
            if (DC_OFFSET_WIDTH'(i) == i_mhq_lu_offset) begin
                for (int j = 0; j < (4 < (OPTN_DC_LINE_SIZE-i) ? 4 : (OPTN_DC_LINE_SIZE-i)); j++) begin
                    mhq_ex_data[(i+j)*8 +: 8] = (i_mhq_lu_we & i_mhq_lu_byte_select[j]) ? i_mhq_lu_wr_data[j*8 +: 8] : mhq_ex_data[(i+j)*8 +: 8];
                    mhq_ex_byte_updated[i+j]  = (i_mhq_lu_we & i_mhq_lu_byte_select[j]) | mhq_ex_byte_updated[i+j];
                end
            end
        end
    end

    // Merge fill data with updated bytes from MHQ and currently enqueuing store if necessary
    always_comb begin
        logic [1:0] mhq_fill_data_mux_sel [OPTN_DC_LINE_SIZE-1:0];
        logic       mhq_ex_fill_merge;

        mhq_fill_addr     = {mhq_entry_addr_q[mhq_head_addr], {(DC_OFFSET_WIDTH){1'b0}}};
        mhq_fill_data     = {(DC_LINE_WIDTH){1'b0}};
        mhq_ex_fill_merge = (mhq_ex_en & i_mhq_lu_we & (i_mhq_lu_addr == mhq_entry_addr_q[mhq_head_addr]));

        // Merge data from the CCU and updated data in the MHQ entry (based on the byte_updated field)
        // Also merge data from current enqueue request to the same entry as the fill if there is one (this one takes priority)
        for (int i = 0; i < OPTN_DC_LINE_SIZE; i++) begin
            // Generate mux select signals for the fill data
            mhq_fill_data_mux_sel[i] = {(mhq_ex_fill_merge & mhq_ex_byte_updated[i]), mhq_entry_byte_updated_q[mhq_head_addr][i]};

            case (mhq_fill_data_mux_sel[i])
                2'b00: mhq_fill_data[i*8 +: 8] = i_ccu_data[i*8 +: 8];
                2'b01: mhq_fill_data[i*8 +: 8] = mhq_entry_data_q[mhq_head_addr][i*8 +: 8];
                2'b10: mhq_fill_data[i*8 +: 8] = mhq_ex_data[i*8 +: 8];
                2'b11: mhq_fill_data[i*8 +: 8] = mhq_ex_data[i*8 +: 8];
            endcase
        end
    end

    // Enqueue new entry. This could be merged with an existing entry
    always_ff @(posedge clk) begin
        for (int i = 0; i < OPTN_MHQ_DEPTH; i++) begin
            if (~n_rst) mhq_entry_valid_q[i] <= 1'b0;
            else        mhq_entry_valid_q[i] <= mhq_valid_next[i];
        end
    end

    always_ff @(posedge clk) begin
        if (mhq_ex_en) begin
            mhq_entry_dirty_q[i_mhq_lu_tag]        <= mhq_ex_dirty;
            mhq_entry_addr_q[i_mhq_lu_tag]         <= i_mhq_lu_addr;
            mhq_entry_data_q[i_mhq_lu_tag]         <= mhq_ex_data;
            mhq_entry_byte_updated_q[i_mhq_lu_tag] <= mhq_ex_byte_updated;
        end
    end

    // Output for fill request
    always_ff @(posedge clk) begin
        o_mhq_fill_en    <= i_ccu_done;
        o_mhq_fill_tag   <= mhq_head_addr;
        o_mhq_fill_dirty <= mhq_entry_dirty_q[mhq_head_addr];
        o_mhq_fill_addr  <= mhq_fill_addr;
        o_mhq_fill_data  <= mhq_fill_data;
    end

    // Update mhq head and tail pointers
    always_ff @(posedge clk) begin
        if (~n_rst) mhq_head <= {(MHQ_IDX_WIDTH+1){1'b0}};
        else        mhq_head <= mhq_head_next;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) mhq_tail <= {(MHQ_IDX_WIDTH+1){1'b0}};
        else        mhq_tail <= mhq_tail_next;
    end

endmodule
