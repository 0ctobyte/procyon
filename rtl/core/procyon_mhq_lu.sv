// MHQ lookup stage
// Lookup MHQ for address matches and generate byte select signals depending on store type

`include "procyon_constants.svh"

module procyon_mhq_lu #(
    parameter OPTN_DATA_WIDTH   = 32,
    parameter OPTN_ADDR_WIDTH   = 32,
    parameter OPTN_MHQ_DEPTH    = 4,
    parameter OPTN_DC_LINE_SIZE = 32,

    parameter MHQ_IDX_WIDTH     = $clog2(OPTN_MHQ_DEPTH),
    parameter DC_LINE_WIDTH     = OPTN_DC_LINE_SIZE * 8,
    parameter DC_OFFSET_WIDTH   = $clog2(OPTN_DC_LINE_SIZE),
    parameter WORD_SIZE         = OPTN_DATA_WIDTH / 8
)(
    input  logic                                     clk,
    input  logic                                     n_rst,

    // MHQ head and tail pointers (adusted for next cycle value) and MHQ entries
    input  logic [MHQ_IDX_WIDTH:0]                   i_mhq_tail_next,
    input  logic [MHQ_IDX_WIDTH:0]                   i_mhq_head_next,

    // Feedback from ex stage of MHQ entry array valid and address bits
    input  logic                                     i_mhq_entry_valid        [0:OPTN_MHQ_DEPTH-1],
    input  logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] i_mhq_entry_addr         [0:OPTN_MHQ_DEPTH-1],

    // Bypass lookup address from the mhq_ex stage
    input  logic                                     i_mhq_ex_bypass_en,
    input  logic                                     i_mhq_ex_bypass_we,
    input  logic                                     i_mhq_ex_bypass_match,
    input  logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] i_mhq_ex_bypass_addr,
    input  logic [MHQ_IDX_WIDTH-1:0]                 i_mhq_ex_bypass_tag,

    // Lookup lsu func
    input  logic                                     i_mhq_lookup_valid,
    input  logic                                     i_mhq_lookup_dc_hit,
    input  logic [OPTN_ADDR_WIDTH-1:0]               i_mhq_lookup_addr,
    input  logic [`PCYN_LSU_FUNC_WIDTH-1:0]          i_mhq_lookup_lsu_func,
    input  logic [OPTN_DATA_WIDTH-1:0]               i_mhq_lookup_data,
    input  logic                                     i_mhq_lookup_we,

    // Outputs to next stage
    output logic                                     o_mhq_lu_en,
    output logic                                     o_mhq_lu_we,
    output logic [DC_OFFSET_WIDTH-1:0]               o_mhq_lu_offset,
    output logic [OPTN_DATA_WIDTH-1:0]               o_mhq_lu_wr_data,
    output logic [WORD_SIZE-1:0]                     o_mhq_lu_byte_select,
    output logic                                     o_mhq_lu_match,
    output logic [MHQ_IDX_WIDTH-1:0]                 o_mhq_lu_tag,
    output logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] o_mhq_lu_addr,
    output logic                                     o_mhq_lu_retry,

    // CCU interface to check for fill conflicts
    input  logic                                     i_ccu_done,
    input  logic [OPTN_ADDR_WIDTH-1:0]               i_ccu_addr
);

    logic [MHQ_IDX_WIDTH-1:0]                 mhq_tail_addr;
    logic                                     mhq_full_next;
    logic                                     mhq_lookup_en;
    logic                                     mhq_lookup_is_fill;
    logic                                     mhq_lookup_retry;
    logic [OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH] mhq_lookup_addr;
    logic [DC_OFFSET_WIDTH-1:0]               mhq_lookup_offset;
    logic [WORD_SIZE-1:0]                     mhq_lookup_byte_select;
    logic                                     mhq_lookup_match;
    logic [MHQ_IDX_WIDTH-1:0]                 mhq_lookup_tag;
    logic [OPTN_MHQ_DEPTH-1:0]                mhq_lookup_tag_select;
    logic                                     mhq_ex_bypass_en;
    logic                                     bypass_en;

    // Calculate if the MHQ will be full on the next cycle
    assign mhq_tail_addr      = i_mhq_tail_next[MHQ_IDX_WIDTH-1:0];
    assign mhq_full_next      = ({~i_mhq_tail_next[MHQ_IDX_WIDTH], i_mhq_tail_next[MHQ_IDX_WIDTH-1:0]} == i_mhq_head_next);

    // Determine if MHQ request in EX stage is going to enqueue and bypass if the lookup address matches the address in the next stage
    assign mhq_ex_bypass_en   = i_mhq_ex_bypass_en | (i_mhq_ex_bypass_we & i_mhq_ex_bypass_match);
    assign bypass_en          = (mhq_ex_bypass_en & (i_mhq_ex_bypass_addr == mhq_lookup_addr));

    // mhq_lookup_retry is asserted if the MHQ is full and there was no match OR if the CCU signals a fill on the same cycle with the same address as the lookup
    // The same cycle fill case causes a fill conflict where the lookup will return an MHQ tag and enqueue on that entry when it will be invalidated by the current fill
    assign mhq_lookup_is_fill = (i_mhq_lookup_lsu_func == `PCYN_LSU_FUNC_FILL);
    assign mhq_lookup_addr    = i_mhq_lookup_addr[OPTN_ADDR_WIDTH-1:DC_OFFSET_WIDTH];
    assign mhq_lookup_offset  = i_mhq_lookup_addr[DC_OFFSET_WIDTH-1:0];
    assign mhq_lookup_retry   = (mhq_full_next & ~mhq_lookup_match) | (i_ccu_done & (i_ccu_addr == i_mhq_lookup_addr));
    assign mhq_lookup_en      = i_mhq_lookup_valid & ~i_mhq_lookup_dc_hit & ~mhq_lookup_is_fill & ~mhq_lookup_retry;

    always_comb begin
        logic [OPTN_MHQ_DEPTH-1:0] match_tag_select        = {(OPTN_MHQ_DEPTH){1'b0}};
        logic [OPTN_MHQ_DEPTH-1:0] tail_tag_select         = {(OPTN_MHQ_DEPTH){1'b0}};
        logic [OPTN_MHQ_DEPTH-1:0] bypass_tag_select       = {(OPTN_MHQ_DEPTH){1'b0}};
        logic                      lookup_match            = 1'b0;

        // Convert bypass tag into tag select
        for (int i = 0; i < OPTN_MHQ_DEPTH; i++) begin
            bypass_tag_select[i] = (MHQ_IDX_WIDTH'(i) == i_mhq_ex_bypass_tag);
        end

        // Convert tag pointer into tag select
        for (int i = 0; i < OPTN_MHQ_DEPTH; i++) begin
            tail_tag_select[i] = (MHQ_IDX_WIDTH'(i) == mhq_tail_addr);
        end

        // Check each valid entry for a matching lookup address
        for (int i = 0; i < OPTN_MHQ_DEPTH; i++) begin
            match_tag_select[i] = i_mhq_entry_valid[i] & (i_mhq_entry_addr[i] == mhq_lookup_addr);
        end

        // If match_tag_select is non-zero than we have found a match
        lookup_match            = (match_tag_select != {(OPTN_MHQ_DEPTH){1'b0}});

        // Bypass lookup address from mhq_ex stage if possible
        // If there was no match then the tag is at the tail pointer (i.e. new entry)
        mhq_lookup_tag_select   = bypass_en ? bypass_tag_select : (lookup_match ? match_tag_select : tail_tag_select);

        // If either lookup_match or bypass_en is true then we have found a match (either in the MHQ or from the bypass)
        mhq_lookup_match        = i_mhq_lookup_valid & (lookup_match | bypass_en);
    end

    // Convert one-hot mhq_lookup_tag_select vector into binary tag #
    always_comb begin
        mhq_lookup_tag = {(MHQ_IDX_WIDTH){1'b0}};
        for (int i = 0; i < OPTN_MHQ_DEPTH; i++) begin
            if (mhq_lookup_tag_select[i]) begin
                mhq_lookup_tag = MHQ_IDX_WIDTH'(i);
            end
        end
    end

    // Generate byte select signals based on store type
    always_comb begin
        case (i_mhq_lookup_lsu_func)
            `PCYN_LSU_FUNC_SB: mhq_lookup_byte_select = WORD_SIZE'(1);
            `PCYN_LSU_FUNC_SH: mhq_lookup_byte_select = WORD_SIZE'(3);
            `PCYN_LSU_FUNC_SW: mhq_lookup_byte_select = WORD_SIZE'(15);
            default:           mhq_lookup_byte_select = WORD_SIZE'(0);
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
