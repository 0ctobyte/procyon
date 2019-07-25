// Decode & Rename
// Decode instruction
// Lookup source register for instruction from Register Map
// Send destination register rename request to Register Map
// Register ROB enqueue signals for ROB enqueue in the next cycle
// Register RS enqueue signals for next cycle

`include "procyon_constants.svh"

module decode_rename #(
    parameter OPTN_DATA_WIDTH       = 32,
    parameter OPTN_ADDR_WIDTH       = 32,
    parameter OPTN_REGMAP_IDX_WIDTH = 5,
    parameter OPTN_ROB_IDX_WIDTH    = 5
)(
    input  logic                             clk,
    input  logic                             n_rst,

    input  logic                             i_flush,
    input  logic                             i_rob_stall,
    input  logic                             i_rs_stall,

    // Fetch interface
    input  logic [OPTN_ADDR_WIDTH-1:0]       i_dispatch_pc,
    input  logic [OPTN_DATA_WIDTH-1:0]       i_dispatch_insn,
    input  logic                             i_dispatch_valid,

    // ROB rename destination tag
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]    i_rob_dst_tag,

    // Register Map lookup interface
    output logic [OPTN_REGMAP_IDX_WIDTH-1:0] o_regmap_lookup_rsrc [0:1],
    output logic                             o_regmap_lookup_valid,

    // Register Map rename interface
    output logic [OPTN_REGMAP_IDX_WIDTH-1:0] o_regmap_rename_rdest,
    output logic                             o_regmap_rename_en,

    // ROB src register ready signal override
    output logic                             o_rob_lookup_rdy_ovrd [0:1],

    // ROB enqueue interface
    output logic                             o_rob_enq_en,
    output logic [OPTN_ADDR_WIDTH-1:0]       o_rob_enq_pc,
    output logic [`PCYN_ROB_OP_WIDTH-1:0]    o_rob_enq_op,
    output logic [OPTN_REGMAP_IDX_WIDTH-1:0] o_rob_enq_rdest,

    // Reservation Station interface Stage 0
    output logic                             o_rs_en,
    output logic [`PCYN_OPCODE_WIDTH-1:0]    o_rs_opcode,
    output logic [OPTN_ADDR_WIDTH-1:0]       o_rs_pc,
    output logic [OPTN_DATA_WIDTH-1:0]       o_rs_insn,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]    o_rs_dst_tag
);

    logic [`PCYN_OPCODE_WIDTH-1:0]    opcode;
    logic                             is_opimm;
    logic                             is_lui;
    logic                             is_auipc;
    logic                             is_op;
    logic                             is_jal;
    logic                             is_jalr;
    logic                             is_branch;
    logic                             is_load;
    logic                             is_store;
    logic [OPTN_REGMAP_IDX_WIDTH-1:0] rdest;
    logic [OPTN_REGMAP_IDX_WIDTH-1:0] rsrc [0:1];
    logic                             rob_rdest_sel;
    logic [OPTN_REGMAP_IDX_WIDTH-1:0] rob_enq_rdest;
    logic [`PCYN_ROB_OP_WIDTH-1:0]    rob_enq_op;
    logic                             rob_src_rdy [0:1];
    logic                             enable;
    logic                             clear;

    assign clear                 = ~n_rst | i_flush;
    assign enable                = ~(i_rob_stall | i_rs_stall);

    assign is_opimm              = (opcode == `PCYN_OPCODE_OPIMM);
    assign is_lui                = (opcode == `PCYN_OPCODE_LUI);
    assign is_auipc              = (opcode == `PCYN_OPCODE_AUIPC);
    assign is_op                 = (opcode == `PCYN_OPCODE_OP);
    assign is_jal                = (opcode == `PCYN_OPCODE_JAL);
    assign is_jalr               = (opcode == `PCYN_OPCODE_JALR);
    assign is_branch             = (opcode == `PCYN_OPCODE_BRANCH);
    assign is_load               = (opcode == `PCYN_OPCODE_LOAD);
    assign is_store              = (opcode == `PCYN_OPCODE_STORE);

    assign rob_src_rdy[0]        = ~(is_opimm | is_op | is_jalr | is_branch | is_load | is_store);
    assign rob_src_rdy[1]        = ~(is_op | is_branch | is_store);
    assign rob_rdest_sel         = is_opimm | is_lui | is_auipc | is_op | is_jal | is_jalr | is_load;
    assign rob_enq_rdest         = rob_rdest_sel ? rdest : {(OPTN_REGMAP_IDX_WIDTH){1'b0}};

    // Pull out the relevant signals from the insn
    assign opcode                = i_dispatch_insn[6:0];
    assign rdest                 = i_dispatch_insn[11:7];
    assign rsrc[0]               = i_dispatch_insn[19:15];
    assign rsrc[1]               = i_dispatch_insn[24:20];

    // Interface to Register Map to lookup source operands
    assign o_regmap_lookup_rsrc  = rsrc;
    assign o_regmap_lookup_valid = enable;

    // Interface to Register Map to rename destination register for new instruction
    assign o_regmap_rename_rdest = rob_enq_rdest;
    assign o_regmap_rename_en    = enable & i_dispatch_valid;

    always_comb begin
        logic [1:0] rob_op_sel = {is_store | is_branch | is_jal | is_jalr, is_load | is_branch | is_jal | is_jalr};
        case (rob_op_sel)
            2'b00: rob_enq_op = `PCYN_ROB_OP_INT;
            2'b01: rob_enq_op = `PCYN_ROB_OP_LD;
            2'b10: rob_enq_op = `PCYN_ROB_OP_ST;
            2'b11: rob_enq_op = `PCYN_ROB_OP_BR;
        endcase
    end

    always_ff @(posedge clk) begin
        if (clear)       o_rob_enq_en <= 1'b0;
        else if (enable) o_rob_enq_en <= i_dispatch_valid;
    end

    always_ff @(posedge clk) begin
        if (enable) begin
            o_rob_enq_pc          <= i_dispatch_pc;
            o_rob_enq_op          <= rob_enq_op;
            o_rob_enq_rdest       <= rob_enq_rdest;
            o_rob_lookup_rdy_ovrd <= rob_src_rdy;
        end
    end

    always_ff @(posedge clk) begin
        if (clear)       o_rs_en <= 1'b0;
        else if (enable) o_rs_en <= i_dispatch_valid;
    end


    always_ff @(posedge clk) begin
        if (enable) begin
            o_rs_opcode  <= opcode;
            o_rs_pc      <= i_dispatch_pc;
            o_rs_insn    <= i_dispatch_insn;
            o_rs_dst_tag <= i_rob_dst_tag;
        end
    end

endmodule

