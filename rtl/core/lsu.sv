// Load/Store Unit
// Encapsulates the ID & EX stage and
// the Load Queue and Store Queue

`include "common.svh"
import procyon_types::*;

module lsu (
    input  logic                    clk,
    input  logic                    n_rst,

    input  logic                    i_flush,

    // Common Data Bus
    output logic                    o_cdb_en,
    output logic                    o_cdb_redirect,
    output procyon_data_t           o_cdb_data,
    output procyon_addr_t           o_cdb_addr,
    output procyon_tag_t            o_cdb_tag,

    input  logic                    i_fu_valid,
    input  procyon_opcode_t         i_fu_opcode,
/* verilator lint_off UNUSED */
    input  procyon_addr_t           i_fu_iaddr,
/* verilator lint_on  UNUSED */
    input  procyon_data_t           i_fu_insn,
    input  procyon_data_t           i_fu_src_a,
    input  procyon_data_t           i_fu_src_b,
    input  procyon_tag_t            i_fu_tag,
    output logic                    o_fu_stall,

    // ROB retirement interface
    input  procyon_tag_t            i_rob_retire_tag,
    input  logic                    i_rob_retire_lq_en,
    input  logic                    i_rob_retire_sq_en,
    output logic                    o_rob_retire_stall,
    output logic                    o_rob_retire_mis_speculated,

    // FIXME: Temporary MHQ interface
    input  logic                    i_mhq_full,
    input  logic                    i_mhq_fill,
    input  procyon_mhq_tag_t        i_mhq_fill_tag,
    input  logic                    i_mhq_fill_dirty,
    input  procyon_addr_t           i_mhq_fill_addr,
    input  procyon_cacheline_t      i_mhq_fill_data,
    input  procyon_mhq_tag_t        i_mhq_enq_tag,
    output logic                    o_mhq_enq_en,
    output logic                    o_mhq_enq_we,
    output procyon_addr_t           o_mhq_enq_addr,
    output procyon_data_t           o_mhq_enq_data,
    output procyon_byte_select_t    o_mhq_enq_byte_select
);

    typedef struct packed {
        procyon_lsu_func_t   lsu_func;
        procyon_addr_t       addr;
        procyon_cacheline_t  data;
        procyon_tag_t        tag;
        logic                valid;
        logic                retire;
        logic                dirty;
    } lsu_id_t;

    typedef struct packed {
        procyon_data_t       data;
        procyon_addr_t       addr;
        procyon_tag_t        tag;
        logic                valid;
    } lsu_ex_t;

    lsu_ex_t                 lsu_ex;
/* verilator lint_off MULTIDRIVEN */
    lsu_id_t                 lsu_id_q;
    lsu_ex_t                 lsu_ex_q;
/* verilator lint_on  MULTIDRIVEN */
    lsu_id_t                 lsu_id_mux;
    //logic                    lsu_ex_stall;
    //logic                    st_miss_stall;
    procyon_lsu_func_t       lsu_id_lsu_func;
    procyon_addr_t           lsu_id_addr;
    procyon_tag_t            lsu_id_tag;
    logic                    lsu_id_valid;
    procyon_lsu_func_t       alloc_lsu_func;
    procyon_tag_t            alloc_tag;
    procyon_data_t           alloc_data;
    procyon_addr_t           alloc_addr;
    logic                    alloc_sq_en;
    logic                    alloc_lq_en;
    logic                    lq_replay_stall;
    procyon_lsu_func_t       lq_replay_lsu_func;
    procyon_tag_t            lq_replay_tag;
    procyon_addr_t           lq_replay_addr;
    logic                    lq_replay_en;
    logic                    sq_retire_stall;
    procyon_data_t           sq_retire_data;
    procyon_addr_t           sq_retire_addr;
    procyon_tag_t            sq_retire_tag;
    procyon_lsu_func_t       sq_retire_lsu_func;
    logic                    sq_retire_en;
    logic                    update_lq_en;
    logic                    update_lq_retry;
    procyon_mhq_tag_t        update_lq_mhq_tag;
    logic                    dc_we;
    logic                    dc_fe;
    procyon_addr_t           dc_addr;
    procyon_data_t           dc_data_r;
    procyon_byte_select_t    dc_byte_select;
    logic                    dc_fill_dirty;
    logic                    dc_hit;
    procyon_cacheline_t      dc_data_w;
    logic                    lq_full;
    logic                    sq_full;

    // Stall the LSU pipeline if either of these conditions apply:
    // 1. There is a cache fill in progress
    // 2. LSU_EX is trying to retire a store that misses in the cache and the MHQ is full
    // Stall the reservation station from issuing if the any of the following conditions apply:
    // 1. Load queue is full
    // 2. Store queue is full
    // 3. A store needs to be retired
    // 4. A load needs to be replayed
    // 5. The cache is being filled
    // 6. A store is attempting to be written out but misses in the cache when
    // the MHQ is full
    //assign st_miss_stall    = (lsu_id_q.retire && ~dc_hit && i_mhq_full);
    //assign lsu_ex_stall     = st_miss_stall || i_mhq_fill;
    assign o_fu_stall       = lq_full || sq_full || lq_replay_en || sq_retire_en || i_mhq_fill;

    // Stall retiring stores if there is a pipeline stall
    // Stall replaying loads if a store is retiring or if there is a pipeline stall
    assign sq_retire_stall  = i_mhq_fill;
    assign lq_replay_stall  = sq_retire_en || i_mhq_fill;

    // Retry loads when MHQ is no longer full
    assign update_lq_retry  = i_mhq_full;

    assign o_cdb_data       = lsu_ex_q.data;
    assign o_cdb_addr       = lsu_ex_q.addr;
    assign o_cdb_tag        = lsu_ex_q.tag;
    assign o_cdb_redirect   = 1'b0;
    assign o_cdb_en         = lsu_ex_q.valid;

    // Mux to ID -> EX pipeline register depending on lq_replay_en and/or sq_replay_en
    always_comb begin
        lsu_id_mux.data   = i_mhq_fill ? i_mhq_fill_data : {{(`DC_LINE_WIDTH-`DATA_WIDTH){1'b0}}, sq_retire_data};
        lsu_id_mux.retire = sq_retire_en;
        lsu_id_mux.valid  = lsu_id_valid || lq_replay_en || sq_retire_en || i_mhq_fill;
        lsu_id_mux.dirty  = i_mhq_fill_dirty;
        if (i_mhq_fill) begin
            lsu_id_mux.lsu_func = LSU_FUNC_FILL;
            lsu_id_mux.addr     = i_mhq_fill_addr;
            lsu_id_mux.tag      = {{(`TAG_WIDTH){1'b0}}};
        end else if (sq_retire_en) begin
            lsu_id_mux.lsu_func = sq_retire_lsu_func;
            lsu_id_mux.addr     = sq_retire_addr;
            lsu_id_mux.tag      = sq_retire_tag;
        end else if (lq_replay_en) begin
            lsu_id_mux.lsu_func = lq_replay_lsu_func;
            lsu_id_mux.addr     = lq_replay_addr;
            lsu_id_mux.tag      = lq_replay_tag;
        end else begin
            lsu_id_mux.lsu_func = lsu_id_lsu_func;
            lsu_id_mux.addr     = lsu_id_addr;
            lsu_id_mux.tag      = lsu_id_tag;
        end
    end

    // ID -> EX pipeline
    always_ff @(posedge clk) begin
        lsu_id_q.lsu_func <= lsu_id_mux.lsu_func;
        lsu_id_q.addr     <= lsu_id_mux.addr;
        lsu_id_q.data     <= lsu_id_mux.data;
        lsu_id_q.tag      <= lsu_id_mux.tag;
        lsu_id_q.retire   <= lsu_id_mux.retire;
        lsu_id_q.dirty    <= lsu_id_mux.dirty;
    end

    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            lsu_id_q.valid <= 1'b0;
        end else if (i_flush) begin
            lsu_id_q.valid <= 1'b0;
        end else begin
            lsu_id_q.valid <= lsu_id_mux.valid;
        end
    end

    // EX -> WB pipeline
    always_ff @(posedge clk) begin
        lsu_ex_q.data <= lsu_ex.data;
        lsu_ex_q.addr <= lsu_ex.addr;
        lsu_ex_q.tag  <= lsu_ex.tag;
    end

    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            lsu_ex_q.valid <= 1'b0;
        end else if (i_flush) begin
            lsu_ex_q.valid <= 1'b0;
        end else begin
            lsu_ex_q.valid <= lsu_ex.valid;
        end
    end

    lsu_id lsu_id_inst (
        .i_opcode(i_fu_opcode),
        .i_insn(i_fu_insn),
        .i_src_a(i_fu_src_a),
        .i_src_b(i_fu_src_b),
        .i_tag(i_fu_tag),
        .i_valid(i_fu_valid),
        .o_lsu_func(lsu_id_lsu_func),
        .o_addr(lsu_id_addr),
        .o_tag(lsu_id_tag),
        .o_valid(lsu_id_valid),
        .o_alloc_lsu_func(alloc_lsu_func),
        .o_alloc_tag(alloc_tag),
        .o_alloc_data(alloc_data),
        .o_alloc_addr(alloc_addr),
        .o_alloc_sq_en(alloc_sq_en),
        .o_alloc_lq_en(alloc_lq_en)
    );

    lsu_ex lsu_ex_inst (
        .i_lsu_func(lsu_id_q.lsu_func),
        .i_addr(lsu_id_q.addr),
        .i_data(lsu_id_q.data),
        .i_tag(lsu_id_q.tag),
        .i_valid(lsu_id_q.valid),
        .i_retire(lsu_id_q.retire),
        .i_dirty(lsu_id_q.dirty),
        .o_data(lsu_ex.data),
        .o_addr(lsu_ex.addr),
        .o_tag(lsu_ex.tag),
        .o_valid(lsu_ex.valid),
        .o_update_lq_en(update_lq_en),
        .o_update_lq_mhq_tag(update_lq_mhq_tag),
        .i_dc_hit(dc_hit),
        .i_dc_data(dc_data_r),
        .o_dc_we(dc_we),
        .o_dc_fe(dc_fe),
        .o_dc_addr(dc_addr),
        .o_dc_data(dc_data_w),
        .o_dc_byte_select(dc_byte_select),
        .o_dc_fill_dirty(dc_fill_dirty),
        .i_mhq_enq_tag(i_mhq_enq_tag),
        .o_mhq_enq_en(o_mhq_enq_en),
        .o_mhq_enq_we(o_mhq_enq_we),
        .o_mhq_enq_addr(o_mhq_enq_addr),
        .o_mhq_enq_data(o_mhq_enq_data),
        .o_mhq_enq_byte_select(o_mhq_enq_byte_select)
    );

    lsu_lq lsu_lq_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .o_full(lq_full),
        .i_alloc_tag(alloc_tag),
        .i_alloc_addr(alloc_addr),
        .i_alloc_lsu_func(alloc_lsu_func),
        .i_alloc_en(alloc_lq_en),
        .i_replay_stall(lq_replay_stall),
        .o_replay_en(lq_replay_en),
        .o_replay_lsu_func(lq_replay_lsu_func),
        .o_replay_addr(lq_replay_addr),
        .o_replay_tag(lq_replay_tag),
        .i_update_lq_en(update_lq_en),
        .i_update_lq_retry(update_lq_retry),
        .i_update_lq_mhq_tag(update_lq_mhq_tag),
        .i_mhq_fill(i_mhq_fill),
        .i_mhq_fill_tag(i_mhq_fill_tag),
        .i_sq_retire_addr(sq_retire_addr),
        .i_sq_retire_lsu_func(sq_retire_lsu_func),
        .i_sq_retire_en(sq_retire_en),
        .i_rob_retire_tag(i_rob_retire_tag),
        .i_rob_retire_en(i_rob_retire_lq_en),
        .o_rob_retire_mis_speculated(o_rob_retire_mis_speculated)
    );

    lsu_sq lsu_sq_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .o_full(sq_full),
        .i_alloc_data(alloc_data),
        .i_alloc_tag(alloc_tag),
        .i_alloc_addr(alloc_addr),
        .i_alloc_lsu_func(alloc_lsu_func),
        .i_alloc_en(alloc_sq_en),
        .i_sq_retire_stall(sq_retire_stall),
        .o_sq_retire_data(sq_retire_data),
        .o_sq_retire_addr(sq_retire_addr),
        .o_sq_retire_tag(sq_retire_tag),
        .o_sq_retire_lsu_func(sq_retire_lsu_func),
        .o_sq_retire_en(sq_retire_en),
        .i_rob_retire_tag(i_rob_retire_tag),
        .i_rob_retire_en(i_rob_retire_sq_en),
        .o_rob_retire_stall(o_rob_retire_stall)
    );

    dcache dcache_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_dc_we(dc_we),
        .i_dc_fe(dc_fe),
        .i_dc_addr(dc_addr),
        .i_dc_data(dc_data_w),
        .i_dc_byte_select(dc_byte_select),
        .i_dc_fill_dirty(dc_fill_dirty),
        .o_dc_hit(dc_hit),
        .o_dc_data(dc_data_r)
    );

endmodule
