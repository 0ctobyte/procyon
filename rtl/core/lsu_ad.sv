// LSU op decode and and address generation unit

`include "common.svh"
import procyon_types::*;

module lsu_ad (
    input  logic                clk,
    input  logic                n_rst,

    input  logic                i_flush,

    // Full signal inputs from LQ/SQ
    input  logic                i_lq_full,
    input  logic                i_sq_full,

    // Inputs from reservation station
    input                       i_valid,
/* verilator lint_off UNUSED */
    input  procyon_data_t       i_insn,
/* verilator lint_on  UNUSED */
    input  procyon_opcode_t     i_opcode,
    input  procyon_data_t       i_src_a,
    input  procyon_data_t       i_src_b,
    input  procyon_tag_t        i_tag,
    output logic                o_stall,

    // Input from MHQ on a fill
    input  logic                i_mhq_fill_en,
    input  procyon_addr_t       i_mhq_fill_addr,
    input  procyon_cacheline_t  i_mhq_fill_data,
    input  logic                i_mhq_fill_dirty,

    // Input from SQ on a store-retire
    input  logic                i_sq_retire_en,
    input  procyon_tag_t        i_sq_retire_tag,
    input  procyon_data_t       i_sq_retire_data,
    input  procyon_addr_t       i_sq_retire_addr,
    input  procyon_lsu_func_t   i_sq_retire_lsu_func,
    input  procyon_sq_select_t  i_sq_retire_select,
    output logic                o_sq_retire_stall,

    // Input from LQ on a load-replay
    input  logic                i_lq_replay_en,
    input  procyon_tag_t        i_lq_replay_tag,
    input  procyon_addr_t       i_lq_replay_addr,
    input  procyon_lsu_func_t   i_lq_replay_lsu_func,
    input  procyon_lq_select_t  i_lq_replay_select,
    output logic                o_lq_replay_stall,

    // Outputs to next pipeline stage
    output procyon_lsu_func_t   o_lsu_func,
    output procyon_lq_select_t  o_lq_select,
    output procyon_sq_select_t  o_sq_select,
    output procyon_tag_t        o_tag,
    output procyon_addr_t       o_addr,
    output procyon_data_t       o_retire_data,
    output logic                o_retire,
    output logic                o_replay,
    output logic                o_valid,

    // Send read/write request to Dcache
    output logic                o_dc_wr_en,
    output procyon_addr_t       o_dc_addr,
    output procyon_data_t       o_dc_data,
    output logic                o_dc_valid,
    output logic                o_dc_dirty,
    output logic                o_dc_fill,
    output procyon_cacheline_t  o_dc_fill_data,

    // Enqueue newly issued load/store ops in the load/store queues
    output procyon_lsu_func_t   o_alloc_lsu_func,
    output procyon_tag_t        o_alloc_tag,
    output procyon_data_t       o_alloc_data,
    output procyon_addr_t       o_alloc_addr,
    output logic                o_alloc_sq_en,
    output logic                o_alloc_lq_en
);

    procyon_lsu_func_t          lsu_func;
    procyon_data_t              imm_i;
    procyon_data_t              imm_s;
    procyon_addr_t              addr;
    logic                       load_or_store;
    logic [1:0]                 lsu_ad_mux_sel;
    procyon_addr_t              lsu_ad_mux_addr;

    // Generate immediates
    assign imm_i                = {{(`DATA_WIDTH-11){i_insn[31]}}, i_insn[30:25], i_insn[24:20]};
    assign imm_s                = {{(`DATA_WIDTH-11){i_insn[31]}}, i_insn[30:25], i_insn[11:7]};

    // Determine if op is load or store
    assign load_or_store        = i_opcode == OPCODE_STORE;

    // Calculate address
    assign addr                 = i_src_a + (load_or_store ? imm_s : imm_i);

    // Mux AD outputs to next stage depending on replay_en/retire_en
    assign lsu_ad_mux_sel       = {i_lq_replay_en, i_sq_retire_en};
    assign lsu_ad_mux_addr      = i_mhq_fill_en ? i_mhq_fill_addr : mux4_addr(addr, i_sq_retire_addr, i_lq_replay_addr, i_sq_retire_addr, lsu_ad_mux_sel);

    // Stall the LSU RS if either of these conditions apply:
    // 1. There is a cache fill in progress
    // 2. Load queue is full
    // 3. Store queue is full
    // 4. A store needs to be retired
    // 5. A load needs to be replayed
    // FIXME: This should be registered
    assign o_stall              = i_lq_full | i_sq_full | i_lq_replay_en | i_sq_retire_en | i_mhq_fill_en;

    // FIXME: Can this be registered?
    assign o_sq_retire_stall    = i_flush | i_mhq_fill_en;
    assign o_lq_replay_stall    = i_sq_retire_en | i_mhq_fill_en;

    // Decode load/store type based on funct3 field
    always_comb begin
        case (i_insn[14:12])
            3'b000:  lsu_func = load_or_store ? LSU_FUNC_SB : LSU_FUNC_LB;
            3'b001:  lsu_func = load_or_store ? LSU_FUNC_SH : LSU_FUNC_LH;
            3'b010:  lsu_func = load_or_store ? LSU_FUNC_SW : LSU_FUNC_LW;
            3'b100:  lsu_func = LSU_FUNC_LBU;
            3'b101:  lsu_func = LSU_FUNC_LHU;
            default: lsu_func = load_or_store ? LSU_FUNC_SW : LSU_FUNC_LW;
        endcase
    end

    // Allocate op in load queue or store queue
    always_ff @(posedge clk) begin
        o_alloc_lsu_func <= lsu_func;
        o_alloc_tag      <= i_tag;
        o_alloc_data     <= i_src_b;
        o_alloc_addr     <= addr;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_alloc_sq_en <= 1'b0;
        else        o_alloc_sq_en <= ~i_flush & load_or_store & i_valid;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_alloc_lq_en <= 1'b0;
        else        o_alloc_lq_en <= ~i_flush & ~load_or_store & i_valid;
    end

    // Assign outputs to dcache interface
    always_ff @(posedge clk) begin
        o_dc_addr      <= lsu_ad_mux_addr;
        o_dc_data      <= i_sq_retire_data;
        o_dc_valid     <= 1'b1;
        o_dc_dirty     <= i_mhq_fill_en ? i_mhq_fill_dirty : i_sq_retire_en;
        o_dc_fill      <= i_mhq_fill_en;
        o_dc_fill_data <= i_mhq_fill_data;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_dc_wr_en <= 1'b0;
        else        o_dc_wr_en <= ~i_flush & (i_sq_retire_en | i_mhq_fill_en);
    end

    // Assign outputs to next stage in the pipeline
    always_ff @(posedge clk) begin
        o_lsu_func       <= i_mhq_fill_en ? LSU_FUNC_FILL : procyon_lsu_func_t'(mux4_4b(lsu_func, i_sq_retire_lsu_func, i_lq_replay_lsu_func, i_sq_retire_lsu_func, lsu_ad_mux_sel));
        o_lq_select      <= i_lq_replay_select;
        o_sq_select      <= i_sq_retire_select;
        o_tag            <= i_mhq_fill_en ? {{`TAG_WIDTH}{1'b0}} : mux4_tag(i_tag, i_sq_retire_tag, i_lq_replay_tag, i_sq_retire_tag, lsu_ad_mux_sel);
        o_addr           <= lsu_ad_mux_addr;
        o_retire_data    <= i_sq_retire_data;
        o_retire         <= ~i_mhq_fill_en & i_sq_retire_en;
        o_replay         <= ~i_mhq_fill_en & ~i_sq_retire_en & i_lq_replay_en;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_valid <= 1'b0;
        else        o_valid <= ~i_flush & (i_valid | i_lq_replay_en | i_sq_retire_en | i_mhq_fill_en);
    end

endmodule
