/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// LSU op decode and and address generation unit

`include "procyon_constants.svh"

module procyon_lsu_ad #(
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

    // Stall the LSU RS if either of these conditions apply:
    // 1. There is a cache fill in progress
    // 2. Load queue is full
    // 3. Store queue is full
    // 4. A store needs to be retired
    // 5. A load needs to be replayed
    logic rs_stall;
    assign rs_stall = i_lq_full | i_sq_full | i_lq_replay_en | i_sq_retire_en | i_mhq_fill_en;
    assign o_stall = rs_stall;

    logic n_rs_stall;
    assign n_rs_stall = ~rs_stall;

    // Determine if op is load or store
    logic load_or_store;
    assign load_or_store = i_opcode == `PCYN_OPCODE_STORE;

    logic n_flush;
    assign n_flush = ~i_flush;

    // Allocate op in load queue or store queue
    logic alloc_sq_en;
    assign alloc_sq_en = n_flush & load_or_store & i_valid & n_rs_stall;
    procyon_srff #(1) o_alloc_sq_en_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(alloc_sq_en), .i_reset(1'b0), .o_q(o_alloc_sq_en));

    logic alloc_lq_en;
    assign alloc_lq_en = n_flush & ~load_or_store & i_valid & n_rs_stall;
    procyon_srff #(1) o_alloc_lq_en_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(alloc_lq_en), .i_reset(1'b0), .o_q(o_alloc_lq_en));

    // Decode load/store type based on funct3 field
    logic [`PCYN_LSU_FUNC_WIDTH-1:0] lsu_func;

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

    procyon_ff #(`PCYN_LSU_FUNC_WIDTH) o_alloc_lsu_func_ff (.clk(clk), .i_en(1'b1), .i_d(lsu_func), .o_q(o_alloc_lsu_func));

    // Generate immediates
    logic [OPTN_DATA_WIDTH-1:0] imm_i;
    logic [OPTN_DATA_WIDTH-1:0] imm_s;

    assign imm_i = {{(OPTN_DATA_WIDTH-11){i_insn[31]}}, i_insn[30:25], i_insn[24:20]};
    assign imm_s = {{(OPTN_DATA_WIDTH-11){i_insn[31]}}, i_insn[30:25], i_insn[11:7]};

    // Calculate address
    logic [OPTN_ADDR_WIDTH-1:0] addr;
    assign addr = i_src_a + (load_or_store ? imm_s : imm_i);
    procyon_ff #(OPTN_ADDR_WIDTH) o_alloc_addr_ff (.clk(clk), .i_en(1'b1), .i_d(addr), .o_q(o_alloc_addr));

    procyon_ff #(OPTN_ROB_IDX_WIDTH) o_alloc_tag_ff (.clk(clk), .i_en(1'b1), .i_d(i_tag), .o_q(o_alloc_tag));
    procyon_ff #(OPTN_DATA_WIDTH) o_alloc_data_ff (.clk(clk), .i_en(1'b1), .i_d(i_src_b), .o_q(o_alloc_data));

    // Assign outputs to next stage in the pipeline
    // Fill requests get priority over pipeline flushes
    logic valid;
    assign valid = i_mhq_fill_en | (n_flush & ((i_valid & ~i_lq_full & ~i_sq_full) | i_lq_replay_en | i_sq_retire_en));
    procyon_srff #(1) o_valid_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(valid), .i_reset(1'b0), .o_q(o_valid));

    logic n_mhq_fill_en;
    assign n_mhq_fill_en = ~i_mhq_fill_en;

    logic retire;
    assign retire = n_mhq_fill_en & i_sq_retire_en;
    procyon_ff #(1) o_retire_ff (.clk(clk), .i_en(1'b1), .i_d(retire), .o_q(o_retire));

    logic replay;
    assign replay = n_mhq_fill_en & ~i_sq_retire_en & i_lq_replay_en;
    procyon_ff #(1) o_replay_ff (.clk(clk), .i_en(1'b1), .i_d(replay), .o_q(o_replay));

    procyon_ff #(OPTN_LQ_DEPTH) o_lq_select_ff (.clk(clk), .i_en(1'b1), .i_d(i_lq_replay_select), .o_q(o_lq_select));
    procyon_ff #(OPTN_SQ_DEPTH) o_sq_select_ff (.clk(clk), .i_en(1'b1), .i_d(i_sq_retire_select), .o_q(o_sq_select));
    procyon_ff #(OPTN_DATA_WIDTH) o_retire_data_ff (.clk(clk), .i_en(1'b1), .i_d(i_sq_retire_data), .o_q(o_retire_data));

    // Assign outputs to dcache interface
    logic dc_wr_en;
    assign dc_wr_en = n_flush & (i_sq_retire_en | i_mhq_fill_en);
    procyon_srff #(1) o_dc_wr_en_srff (.clk(clk), .n_rst(n_rst), .i_en(1'b1), .i_set(dc_wr_en), .i_reset(1'b0), .o_q(o_dc_wr_en));

    logic dc_dirty;
    assign dc_dirty = i_mhq_fill_en ? i_mhq_fill_dirty : i_sq_retire_en;
    procyon_ff #(1) o_dc_dirty_ff (.clk(clk), .i_en(1'b1), .i_d(dc_dirty), .o_q(o_dc_dirty));

    procyon_ff #(OPTN_DATA_WIDTH) o_dc_data_ff (.clk(clk), .i_en(1'b1), .i_d(i_sq_retire_data), .o_q(o_dc_data));
    procyon_ff #(1) o_dc_valid_ff (.clk(clk), .i_en(1'b1), .i_d(1'b1), .o_q(o_dc_valid));
    procyon_ff #(1) o_dc_fill_ff (.clk(clk), .i_en(1'b1), .i_d(i_mhq_fill_en), .o_q(o_dc_fill));
    procyon_ff #(DC_LINE_WIDTH) o_dc_fill_data_ff (.clk(clk), .i_en(1'b1), .i_d(i_mhq_fill_data), .o_q(o_dc_fill_data));

    // Mux AD outputs to next stage depending on replay_en/retire_en
    logic [1:0] lsu_ad_mux_sel;
    assign lsu_ad_mux_sel = {i_lq_replay_en, i_sq_retire_en};

    logic [OPTN_ADDR_WIDTH-1:0] lsu_ad_addr_mux;

    always_comb begin
        case (lsu_ad_mux_sel)
            2'b00: lsu_ad_addr_mux = addr;
            2'b01: lsu_ad_addr_mux = i_sq_retire_addr;
            2'b10: lsu_ad_addr_mux = i_lq_replay_addr;
            2'b11: lsu_ad_addr_mux = i_sq_retire_addr;
        endcase

        lsu_ad_addr_mux = i_mhq_fill_en ? i_mhq_fill_addr : lsu_ad_addr_mux;
    end

    procyon_ff #(OPTN_ADDR_WIDTH) o_addr_ff (.clk(clk), .i_en(1'b1), .i_d(lsu_ad_addr_mux), .o_q(o_addr));
    procyon_ff #(OPTN_ADDR_WIDTH) o_dc_addr_ff (.clk(clk), .i_en(1'b1), .i_d(lsu_ad_addr_mux), .o_q(o_dc_addr));

    logic [`PCYN_LSU_FUNC_WIDTH-1:0] lsu_ad_lsu_func_mux;

    always_comb begin
        case (lsu_ad_mux_sel)
            2'b00: lsu_ad_lsu_func_mux = lsu_func;
            2'b01: lsu_ad_lsu_func_mux = i_sq_retire_lsu_func;
            2'b10: lsu_ad_lsu_func_mux = i_lq_replay_lsu_func;
            2'b11: lsu_ad_lsu_func_mux = i_sq_retire_lsu_func;
        endcase

        lsu_ad_lsu_func_mux = i_mhq_fill_en ? `PCYN_LSU_FUNC_FILL : lsu_ad_lsu_func_mux;
    end

    procyon_ff #(`PCYN_LSU_FUNC_WIDTH) o_lsu_func_ff (.clk(clk), .i_en(1'b1), .i_d(lsu_ad_lsu_func_mux), .o_q(o_lsu_func));
    procyon_ff #(`PCYN_LSU_FUNC_WIDTH) o_dc_lsu_func_ff (.clk(clk), .i_en(1'b1), .i_d(lsu_ad_lsu_func_mux), .o_q(o_dc_lsu_func));

    logic [OPTN_ROB_IDX_WIDTH-1:0] lsu_ad_tag_mux;

    always_comb begin
        case (lsu_ad_mux_sel)
            2'b00: lsu_ad_tag_mux = i_tag;
            2'b01: lsu_ad_tag_mux = i_sq_retire_tag;
            2'b10: lsu_ad_tag_mux = i_lq_replay_tag;
            2'b11: lsu_ad_tag_mux = i_sq_retire_tag;
        endcase

        lsu_ad_tag_mux = i_mhq_fill_en ? '0 : lsu_ad_tag_mux;
    end

    procyon_ff #(OPTN_ROB_IDX_WIDTH) o_tag_ff (.clk(clk), .i_en(1'b1), .i_d(lsu_ad_tag_mux), .o_q(o_tag));

    assign o_sq_retire_stall = i_flush | i_mhq_fill_en;
    assign o_lq_replay_stall = i_sq_retire_en | i_mhq_fill_en;

endmodule
