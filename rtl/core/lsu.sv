// Load/Store Unit
// Encapsulates the ID & EX stage and
// the Load Queue and Store Queue

`include "common.svh"
import procyon_types::*;

/* verilator lint_off MULTIDRIVEN */
module lsu #(
    parameter  LQ_DEPTH = `LQ_DEPTH,
    parameter  SQ_DEPTH = `SQ_DEPTH
) (
    input  logic             clk,
    input  logic             n_rst,

    input  logic             i_flush,

    // Common Data Bus
    output logic             o_cdb_en,
    output logic             o_cdb_redirect,
    output procyon_data_t    o_cdb_data,
    output procyon_addr_t    o_cdb_addr,
    output procyon_tag_t     o_cdb_tag,

    input  logic             i_fu_valid,
    input  procyon_opcode_t  i_fu_opcode,
/* verilator lint_off UNUSED */
    input  procyon_addr_t    i_fu_iaddr,
/* verilator lint_on  UNUSED */
    input  procyon_data_t    i_fu_insn,
    input  procyon_data_t    i_fu_src_a,
    input  procyon_data_t    i_fu_src_b,
    input  procyon_tag_t     i_fu_tag,
    output logic             o_fu_stall,

    // ROB retirement interface
    input  procyon_tag_t     i_rob_retire_tag,
    input  logic             i_rob_retire_lq_en,
    input  logic             i_rob_retire_sq_en,
    output logic             o_rob_retire_stall,
    output logic             o_rob_retire_mis_speculated,

    // FIXME: Temporary data cache interface
    input  logic             i_dc_hit,
    input  procyon_data_t    i_dc_data,
    output logic             o_dc_re,
    output procyon_addr_t    o_dc_addr,

    // FIXME: Store retire to cache interface
    input  logic             i_sq_retire_dc_hit,
    input  logic             i_sq_retire_msq_full,
    output logic             o_sq_retire_en,
    output procyon_word_t    o_sq_retire_byte_en,
    output procyon_addr_t    o_sq_retire_addr,
    output procyon_data_t    o_sq_retire_data
);

    typedef struct packed {
        procyon_lsu_func_t   lsu_func;
        procyon_addr_t       addr;
        procyon_tag_t        tag;
        logic                valid;
    } lsu_id_t;

    typedef struct packed {
        procyon_data_t       data;
        procyon_addr_t       addr;
        procyon_tag_t        tag;
        logic                valid;
    } lsu_ex_t;

    lsu_id_t                 lsu_id;
    lsu_id_t                 lsu_id_q;
    lsu_ex_t                 lsu_ex;
    lsu_ex_t                 lsu_ex_q;
    procyon_lsu_func_t       alloc_lsu_func;
    procyon_tag_t            alloc_tag;
    procyon_data_t           alloc_data;
    procyon_addr_t           alloc_addr;
    logic                    alloc_sq_en;
    logic                    alloc_lq_en;
    logic                    sq_retire_en;
    procyon_addr_t           sq_retire_addr;
    procyon_lsu_func_t       sq_retire_lsu_func;
    logic                    lq_full;
    logic                    sq_full;

    assign o_sq_retire_en   = sq_retire_en;
    assign o_sq_retire_addr = sq_retire_addr;

    assign o_fu_stall       = lq_full || sq_full;

    assign o_cdb_data       = lsu_ex_q.data;
    assign o_cdb_addr       = lsu_ex_q.addr;
    assign o_cdb_tag        = lsu_ex_q.tag;
    assign o_cdb_redirect   = 1'b0;
    assign o_cdb_en         = lsu_ex_q.valid;

    always_comb begin
        case (sq_retire_lsu_func)
            LSU_FUNC_SB: o_sq_retire_byte_en = 4'b0001;
            LSU_FUNC_SH: o_sq_retire_byte_en = 4'b0011;
            default:     o_sq_retire_byte_en = 4'b1111;
        endcase
    end

    // ID -> EX pipeline
    always_ff @(posedge clk) begin
        lsu_id_q.lsu_func <= lsu_id.lsu_func;
        lsu_id_q.addr     <= lsu_id.addr;
        lsu_id_q.tag      <= lsu_id.tag;
    end

    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            lsu_id_q.valid <= 1'b0;
        end else if (i_flush) begin
            lsu_id_q.valid <= 1'b0;
        end else begin
            lsu_id_q.valid <= lsu_id.valid;
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
        .o_lsu_func(lsu_id.lsu_func),
        .o_addr(lsu_id.addr),
        .o_tag(lsu_id.tag),
        .o_valid(lsu_id.valid),
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
        .i_tag(lsu_id_q.tag),
        .i_valid(lsu_id_q.valid),
        .o_data(lsu_ex.data),
        .o_addr(lsu_ex.addr),
        .o_tag(lsu_ex.tag),
        .o_valid(lsu_ex.valid),
        .i_dc_hit(i_dc_hit),
        .i_dc_data(i_dc_data),
        .o_dc_addr(o_dc_addr),
        .o_dc_re(o_dc_re)
    );

    lsu_lq #(
        .LQ_DEPTH(LQ_DEPTH)
    ) lsu_lq_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .o_full(lq_full),
        .i_alloc_tag(alloc_tag),
        .i_alloc_addr(alloc_addr),
        .i_alloc_en(alloc_lq_en),
        .i_sq_retire_addr(sq_retire_addr),
        .i_sq_retire_lsu_func(sq_retire_lsu_func),
        .i_sq_retire_en(sq_retire_en),
        .i_rob_retire_tag(i_rob_retire_tag),
        .i_rob_retire_en(i_rob_retire_lq_en),
        .o_rob_retire_mis_speculated(o_rob_retire_mis_speculated)
    );

    lsu_sq #(
        .SQ_DEPTH(SQ_DEPTH)
    ) lsu_sq_inst (
        .clk(clk),
        .n_rst(n_rst),
        .i_flush(i_flush),
        .o_full(sq_full),
        .i_alloc_data(alloc_data),
        .i_alloc_tag(alloc_tag),
        .i_alloc_addr(alloc_addr),
        .i_alloc_lsu_func(alloc_lsu_func),
        .i_alloc_en(alloc_sq_en),
        .i_sq_retire_dc_hit(i_sq_retire_dc_hit),
        .i_sq_retire_msq_full(i_sq_retire_msq_full),
        .o_sq_retire_data(o_sq_retire_data),
        .o_sq_retire_addr(sq_retire_addr),
        .o_sq_retire_lsu_func(sq_retire_lsu_func),
        .o_sq_retire_en(sq_retire_en),
        .i_rob_retire_tag(i_rob_retire_tag),
        .i_rob_retire_en(i_rob_retire_sq_en),
        .o_rob_retire_stall(o_rob_retire_stall)
    );

endmodule
/* verilator lint_on  MULTIDRIVEN */
