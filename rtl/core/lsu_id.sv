// Instruction decode and address generation unit
// Will send signals to load or store queue to allocate op

`include "common.svh"
import procyon_types::*;

module lsu_id (
    // Inputs from reservation station
    input  procyon_opcode_t     i_opcode,
/* verilator lint_off UNUSED */
    input  procyon_data_t       i_insn,
/* verilator lint_on  UNUSED */
    input  procyon_data_t       i_src_a,
    input  procyon_data_t       i_src_b,
    input  procyon_tag_t        i_tag,
    input                       i_valid,

    // Outputs to next pipeline stage
    output procyon_lsu_func_t   o_lsu_func,
    output procyon_addr_t       o_addr,
    output procyon_tag_t        o_tag,
    output logic                o_valid,

    // Enqueue newly issued load/store ops in the load/store queues
    output procyon_lsu_func_t   o_alloc_lsu_func,
    output procyon_tag_t        o_alloc_tag,
    output procyon_data_t       o_alloc_data,
    output procyon_addr_t       o_alloc_addr,
    output logic                o_alloc_sq_en,
    output logic                o_alloc_lq_en
);

    procyon_lsu_func_t      lsu_func;
    procyon_data_t          imm_i;
    procyon_data_t          imm_s;
    procyon_addr_t          addr;
    logic                   load_or_store;

    // Generate immediates
    assign imm_i            = {{(`DATA_WIDTH-11){i_insn[31]}}, i_insn[30:25], i_insn[24:20]};
    assign imm_s            = {{(`DATA_WIDTH-11){i_insn[31]}}, i_insn[30:25], i_insn[11:7]};

    // Determine if op is load or store
    assign load_or_store    = i_opcode == OPCODE_STORE;

    // Calculate address
    assign addr             = i_src_a + (load_or_store ? imm_s : imm_i);

    // Allocate op in load queue or store queue
    assign o_alloc_lsu_func = lsu_func;
    assign o_alloc_tag      = i_tag;
    assign o_alloc_data     = i_src_b;
    assign o_alloc_addr     = addr;
    assign o_alloc_sq_en    = load_or_store & i_valid;
    assign o_alloc_lq_en    = ~load_or_store & i_valid;

    // Assign outputs to next stage in the pipeline
    assign o_lsu_func       = lsu_func;
    assign o_addr           = addr;
    assign o_tag            = i_tag;
    assign o_valid          = i_valid;

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

endmodule
