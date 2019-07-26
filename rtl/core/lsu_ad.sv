// LSU op decode and and address generation unit

`include "procyon_constants.svh"

module lsu_ad #(
    parameter OPTN_DATA_WIDTH    = 32,
    parameter OPTN_ADDR_WIDTH    = 32,
    parameter OPTN_LQ_DEPTH      = 8,
    parameter OPTN_SQ_DEPTH      = 8,
    parameter OPTN_DC_LINE_SIZE  = 32,
    parameter OPTN_ROB_IDX_WIDTH = 5,

    parameter DC_LINE_WIDTH      = OPTN_DC_LINE_SIZE * 8
)(
    input  logic                            clk,
    input  logic                            n_rst,

    input  logic                            i_flush,

    // Full signal inputs from LQ/SQ
    input  logic                            i_lq_full,
    input  logic                            i_sq_full,

    // Inputs from reservation station
    input                                   i_valid,
/* verilator lint_off UNUSED */
    input  logic [OPTN_DATA_WIDTH-1:0]      i_insn,
/* verilator lint_on  UNUSED */
    input  logic [`PCYN_OPCODE_WIDTH-1:0]   i_opcode,
    input  logic [OPTN_DATA_WIDTH-1:0]      i_src_a,
    input  logic [OPTN_DATA_WIDTH-1:0]      i_src_b,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]   i_tag,
    output logic                            o_stall,

    // Input from MHQ on a fill
    input  logic                            i_mhq_fill_en,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_mhq_fill_addr,
    input  logic [DC_LINE_WIDTH-1:0]        i_mhq_fill_data,
    input  logic                            i_mhq_fill_dirty,

    // Input from SQ on a store-retire
    input  logic                            i_sq_retire_en,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]   i_sq_retire_tag,
    input  logic [OPTN_DATA_WIDTH-1:0]      i_sq_retire_data,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_sq_retire_addr,
    input  logic [`PCYN_LSU_FUNC_WIDTH-1:0] i_sq_retire_lsu_func,
    input  logic [OPTN_SQ_DEPTH-1:0]        i_sq_retire_select,
    output logic                            o_sq_retire_stall,

    // Input from LQ on a load-replay
    input  logic                            i_lq_replay_en,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]   i_lq_replay_tag,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_lq_replay_addr,
    input  logic [`PCYN_LSU_FUNC_WIDTH-1:0] i_lq_replay_lsu_func,
    input  logic [OPTN_LQ_DEPTH-1:0]        i_lq_replay_select,
    output logic                            o_lq_replay_stall,

    // Outputs to next pipeline stage
    output logic [`PCYN_LSU_FUNC_WIDTH-1:0] o_lsu_func,
    output logic [OPTN_LQ_DEPTH-1:0]        o_lq_select,
    output logic [OPTN_SQ_DEPTH-1:0]        o_sq_select,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]   o_tag,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_addr,
    output logic [OPTN_DATA_WIDTH-1:0]      o_retire_data,
    output logic                            o_retire,
    output logic                            o_replay,
    output logic                            o_valid,

    // Send read/write request to Dcache
    output logic                            o_dc_wr_en,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_dc_addr,
    output logic [OPTN_DATA_WIDTH-1:0]      o_dc_data,
    output logic [`PCYN_LSU_FUNC_WIDTH-1:0] o_dc_lsu_func,
    output logic                            o_dc_valid,
    output logic                            o_dc_dirty,
    output logic                            o_dc_fill,
    output logic [DC_LINE_WIDTH-1:0]        o_dc_fill_data,

    // Enqueue newly issued load/store ops in the load/store queues
    output logic [`PCYN_LSU_FUNC_WIDTH-1:0] o_alloc_lsu_func,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]   o_alloc_tag,
    output logic [OPTN_DATA_WIDTH-1:0]      o_alloc_data,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_alloc_addr,
    output logic                            o_alloc_sq_en,
    output logic                            o_alloc_lq_en
);

    logic [`PCYN_LSU_FUNC_WIDTH-1:0] lsu_func;
    logic [OPTN_DATA_WIDTH-1:0]      imm_i;
    logic [OPTN_DATA_WIDTH-1:0]      imm_s;
    logic [OPTN_ADDR_WIDTH-1:0]      addr;
    logic                            load_or_store;
    logic                            rs_stall;
    logic [1:0]                      lsu_ad_mux_sel;
    logic [OPTN_ADDR_WIDTH-1:0]      lsu_ad_mux_addr;
    logic [`PCYN_LSU_FUNC_WIDTH-1:0] lsu_ad_mux_lsu_func;
    logic [OPTN_ROB_IDX_WIDTH-1:0]   lsu_ad_mux_tag;

    // Generate immediates
    assign imm_i               = {{(OPTN_DATA_WIDTH-11){i_insn[31]}}, i_insn[30:25], i_insn[24:20]};
    assign imm_s               = {{(OPTN_DATA_WIDTH-11){i_insn[31]}}, i_insn[30:25], i_insn[11:7]};

    // Determine if op is load or store
    assign load_or_store       = i_opcode == `PCYN_OPCODE_STORE;

    // Calculate address
    assign addr                = i_src_a + (load_or_store ? imm_s : imm_i);

    // Stall the LSU RS if either of these conditions apply:
    // 1. There is a cache fill in progress
    // 2. Load queue is full
    // 3. Store queue is full
    // 4. A store needs to be retired
    // 5. A load needs to be replayed
    // FIXME: This should be registered
    assign rs_stall            = i_lq_full | i_sq_full | i_lq_replay_en | i_sq_retire_en | i_mhq_fill_en;
    assign o_stall             = rs_stall;

    // FIXME: Can this be registered?
    assign o_sq_retire_stall   = i_flush | i_mhq_fill_en;
    assign o_lq_replay_stall   = i_sq_retire_en | i_mhq_fill_en;

    // Mux AD outputs to next stage depending on replay_en/retire_en
    always_comb begin
        logic [OPTN_ADDR_WIDTH-1:0] addr_mux;

        lsu_ad_mux_sel = {i_lq_replay_en, i_sq_retire_en};

        case (lsu_ad_mux_sel)
            2'b00: lsu_ad_mux_tag = i_tag;
            2'b01: lsu_ad_mux_tag = i_sq_retire_tag;
            2'b10: lsu_ad_mux_tag = i_lq_replay_tag;
            2'b11: lsu_ad_mux_tag = i_sq_retire_tag;
        endcase

        case (lsu_ad_mux_sel)
            2'b00: lsu_ad_mux_lsu_func = lsu_func;
            2'b01: lsu_ad_mux_lsu_func = i_sq_retire_lsu_func;
            2'b10: lsu_ad_mux_lsu_func = i_lq_replay_lsu_func;
            2'b11: lsu_ad_mux_lsu_func = i_sq_retire_lsu_func;
        endcase

        case (lsu_ad_mux_sel)
            2'b00: addr_mux = addr;
            2'b01: addr_mux = i_sq_retire_addr;
            2'b10: addr_mux = i_lq_replay_addr;
            2'b11: addr_mux = i_sq_retire_addr;
        endcase

        lsu_ad_mux_addr = i_mhq_fill_en ? i_mhq_fill_addr : addr_mux;
    end

    // Decode load/store type based on funct3 field
    always_comb begin
        case (i_insn[14:12])
            3'b000:  lsu_func = load_or_store ? `PCYN_LSU_FUNC_SB : `PCYN_LSU_FUNC_LB;
            3'b001:  lsu_func = load_or_store ? `PCYN_LSU_FUNC_SH : `PCYN_LSU_FUNC_LH;
            3'b010:  lsu_func = load_or_store ? `PCYN_LSU_FUNC_SW : `PCYN_LSU_FUNC_LW;
            3'b100:  lsu_func = `PCYN_LSU_FUNC_LBU;
            3'b101:  lsu_func = `PCYN_LSU_FUNC_LHU;
            default: lsu_func = load_or_store ? `PCYN_LSU_FUNC_SW : `PCYN_LSU_FUNC_LW;
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
        else        o_alloc_sq_en <= ~i_flush & load_or_store & i_valid & ~rs_stall;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_alloc_lq_en <= 1'b0;
        else        o_alloc_lq_en <= ~i_flush & ~load_or_store & i_valid &  ~rs_stall;
    end

    // Assign outputs to dcache interface
    always_ff @(posedge clk) begin
        o_dc_addr      <= lsu_ad_mux_addr;
        o_dc_data      <= i_sq_retire_data;
        o_dc_lsu_func  <= lsu_ad_mux_lsu_func;
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
        o_lsu_func       <= i_mhq_fill_en ? `PCYN_LSU_FUNC_FILL : lsu_ad_mux_lsu_func;
        o_lq_select      <= i_lq_replay_select;
        o_sq_select      <= i_sq_retire_select;
        o_tag            <= i_mhq_fill_en ? {{OPTN_ROB_IDX_WIDTH}{1'b0}} : lsu_ad_mux_tag;
        o_addr           <= lsu_ad_mux_addr;
        o_retire_data    <= i_sq_retire_data;
        o_retire         <= ~i_mhq_fill_en & i_sq_retire_en;
        o_replay         <= ~i_mhq_fill_en & ~i_sq_retire_en & i_lq_replay_en;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_valid <= 1'b0;
        else        o_valid <= ~i_flush & ((i_valid & ~i_lq_full & ~i_sq_full) | i_lq_replay_en | i_sq_retire_en | i_mhq_fill_en);
    end

endmodule
