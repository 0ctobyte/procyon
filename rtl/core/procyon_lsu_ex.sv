// LSU execute pipeline stage

`include "procyon_constants.svh"

module procyon_lsu_ex #(
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

    // Inputs from previous pipeline stage
    input  logic                            i_valid,
    input  logic [`PCYN_LSU_FUNC_WIDTH-1:0] i_lsu_func,
    input  logic [OPTN_LQ_DEPTH-1:0]        i_lq_select,
    input  logic [OPTN_SQ_DEPTH-1:0]        i_sq_select,
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]   i_tag,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_addr,
    input  logic                            i_retire,

    // Inputs from dcache
    input  logic                            i_dc_hit,
    input  logic [OPTN_DATA_WIDTH-1:0]      i_dc_data,
    input  logic                            i_dc_victim_valid,
    input  logic                            i_dc_victim_dirty,
    input  logic [OPTN_ADDR_WIDTH-1:0]      i_dc_victim_addr,
    input  logic [DC_LINE_WIDTH-1:0]        i_dc_victim_data,

    // Broadcast CDB results
    output logic                            o_valid,
    output logic [OPTN_DATA_WIDTH-1:0]      o_data,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_addr,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]   o_tag,

    // Update LQ/SQ
    output logic                            o_update_lq_en,
    output logic [OPTN_LQ_DEPTH-1:0]        o_update_lq_select,
    output logic                            o_update_lq_retry,
    output logic                            o_update_sq_en,
    output logic [OPTN_SQ_DEPTH-1:0]        o_update_sq_select,
    output logic                            o_update_sq_retry,

    // Enqueue victim data
    output logic                            o_victim_en,
    output logic [OPTN_ADDR_WIDTH-1:0]      o_victim_addr,
    output logic [DC_LINE_WIDTH-1:0]        o_victim_data
);

    logic                       is_fill;
    logic                       is_store;
    logic                       is_load;
    logic [OPTN_DATA_WIDTH-1:0] load_data;

    assign is_fill  = i_lsu_func == `PCYN_LSU_FUNC_FILL;
    assign is_store = (i_lsu_func == `PCYN_LSU_FUNC_SB) | (i_lsu_func == `PCYN_LSU_FUNC_SH) | (i_lsu_func == `PCYN_LSU_FUNC_SW);
    assign is_load  = ~is_fill & ~is_store;

    // LB and LH need to sign extend to DATA_WIDTH
    always_comb begin
        case (i_lsu_func)
            `PCYN_LSU_FUNC_LB:  load_data = {{(OPTN_DATA_WIDTH-8){i_dc_data[7]}}, i_dc_data[7:0]};
            `PCYN_LSU_FUNC_LH:  load_data = {{(OPTN_DATA_WIDTH-OPTN_DATA_WIDTH/2){i_dc_data[OPTN_DATA_WIDTH/2-1]}}, i_dc_data[OPTN_DATA_WIDTH/2-1:0]};
            default:            load_data = i_dc_data;
        endcase
    end

    always_ff @(posedge clk) begin
        o_data <= load_data;
        o_addr <= i_addr;
        o_tag  <= i_tag;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_valid <= 1'b0;
        else        o_valid <= ~i_flush & i_valid & ~is_fill & ~i_retire & (i_dc_hit | is_store);
    end

    always_ff @(posedge clk) begin
        o_update_lq_select   <= i_lq_select;
        o_update_lq_retry    <= ~i_dc_hit;
        o_update_sq_select   <= i_sq_select;
        o_update_sq_retry    <= ~i_dc_hit;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_update_lq_en <= 1'b0;
        else        o_update_lq_en <= ~i_flush & i_valid & is_load;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_update_sq_en <= 1'b0;
        else        o_update_sq_en <= ~i_flush & i_valid & i_retire;
    end

    always_ff @(posedge clk) begin
        o_victim_addr <= i_dc_victim_addr;
        o_victim_data <= i_dc_victim_data;
    end

    always_ff @(posedge clk) begin
        if (~n_rst) o_victim_en <= 1'b0;
        else        o_victim_en <= i_valid & is_fill & i_dc_victim_valid & i_dc_victim_dirty;
    end

endmodule
