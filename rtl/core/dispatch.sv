// Dispatch module
// Takes an instruction from the instruction queue and performs the following functions
// 1) Allocates an entry in the ROB for the instruction and renames the destination register
// 2) Renames source operands by looking up the source operands in the register map & ROB
// 3) Allocates entry in the reservation station for the instruction

`include "common.svh"
import procyon_types::*;

module dispatch (
    input  logic                  clk,

    input  logic                  i_flush,

    // Instruction FIFO interface
    input  logic                  i_insn_fifo_empty,
    input  procyon_addr_data_t    i_insn_fifo_data,
    output logic                  o_insn_fifo_rd_en,

    // Reservation Station interface
    input  logic                  i_rs_stall,
    output logic                  o_rs_en,
    output procyon_opcode_t       o_rs_opcode,
    output procyon_addr_t         o_rs_iaddr,
    output procyon_data_t         o_rs_insn,
    output procyon_tag_t          o_rs_src_tag   [0:1],
    output procyon_data_t         o_rs_src_data  [0:1],
    output logic                  o_rs_src_rdy   [0:1],
    output procyon_tag_t          o_rs_dst_tag,

    // ROB interface
    input  logic                  i_rob_stall,
    input  procyon_tag_t          i_rob_tag,
    input  logic                  i_rob_src_rdy  [0:1],
    input  procyon_data_t         i_rob_src_data [0:1],
    input  procyon_tag_t          i_rob_src_tag  [0:1],
    output logic                  o_rob_en,
    output logic                  o_rob_rdy,
    output procyon_rob_op_t       o_rob_op,
    output procyon_addr_t         o_rob_iaddr,
    output procyon_addr_t         o_rob_addr,
    output procyon_data_t         o_rob_data,
    output procyon_reg_t          o_rob_rdest,
    output procyon_reg_t          o_rob_rsrc     [0:1]
);

    logic [6:0]                opcode;
    logic                      is_opimm;
    logic                      is_lui;
    logic                      is_auipc;
    logic                      is_op;
    logic                      is_jal;
    logic                      is_jalr;
    logic                      is_branch;
    logic                      is_load;
    logic                      is_store;
    procyon_data_t             insn;
    procyon_addr_t             iaddr;
    procyon_reg_t              rdest;
    procyon_reg_t              rsrc [0:1];
    logic [1:0]                rob_op_sel;
    logic                      rob_rdest_sel;
    logic                      rob_rdy;
    logic [1:0]                rs_src_rdy;
    logic                      rs_rdy;
    procyon_addr_data_t        insn_fifo_data;
    logic                      insn_fifo_empty;
    logic                      insn_fifo_en;
    logic [1:0]                insn_fifo_empty_sel;
    logic                      insn_fifo_rdy;

    assign is_opimm            = (opcode == OPCODE_OPIMM);
    assign is_lui              = (opcode == OPCODE_LUI);
    assign is_auipc            = (opcode == OPCODE_AUIPC);
    assign is_op               = (opcode == OPCODE_OP);
    assign is_jal              = (opcode == OPCODE_JAL);
    assign is_jalr             = (opcode == OPCODE_JALR);
    assign is_branch           = (opcode == OPCODE_BRANCH);
    assign is_load             = (opcode == OPCODE_LOAD);
    assign is_store            = (opcode == OPCODE_STORE);

    assign rs_src_rdy[0]       = is_opimm | is_op | is_jalr | is_branch | is_load | is_store;
    assign rs_src_rdy[1]       = is_op | is_branch | is_store;
    assign rob_op_sel          = {is_store | is_branch | is_jal | is_jalr, is_load | is_branch | is_jal | is_jalr};
    assign rob_rdest_sel       = is_opimm | is_lui | is_auipc | is_op | is_jal | is_jalr | is_load;
    assign insn_fifo_empty_sel = {i_flush, insn_fifo_en};

    // Pull out the signals from the insn FIFO
    assign insn                = insn_fifo_data[`DATA_WIDTH-1:0];
    assign iaddr               = insn_fifo_data[`ADDR_WIDTH+`DATA_WIDTH-1:`DATA_WIDTH];

    // Pull out the relevant signals from the insn
    assign opcode              = insn[6:0];
    assign rdest               = insn[11:7];
    assign rsrc[0]             = insn[19:15];
    assign rsrc[1]             = insn[24:20];

    // Stall if either the reservation station is full or if the ROB is full
    // Assert o_insn_fifo_rd_en only if there are no stalls and the insn FIFO is not empty
    assign rob_rdy             = ~i_rob_stall;
    assign rs_rdy              = ~i_rs_stall;
    assign insn_fifo_rdy       = ~insn_fifo_empty;
    assign insn_fifo_en        = rob_rdy & rs_rdy;

    assign o_insn_fifo_rd_en   = insn_fifo_en;
    assign o_rs_en             = insn_fifo_rdy & rob_rdy;
    assign o_rob_en            = insn_fifo_rdy & rs_rdy;

    assign o_rob_rdy           = 1'b0;
    assign o_rob_iaddr         = iaddr;
    assign o_rob_addr          = {(`ADDR_WIDTH){1'b0}};
    assign o_rob_data          = {(`DATA_WIDTH){1'b0}};
    assign o_rob_rdest         = rob_rdest_sel ? rdest : {(`REG_ADDR_WIDTH){1'b0}};
    assign o_rob_op            = procyon_rob_op_t'(mux4_2b(ROB_OP_INT, ROB_OP_LD, ROB_OP_ST, ROB_OP_BR, rob_op_sel));
    assign o_rob_rsrc          = '{rsrc[0], rsrc[1]};

    assign o_rs_opcode         = procyon_opcode_t'(opcode);
    assign o_rs_iaddr          = iaddr;
    assign o_rs_insn           = insn;
    assign o_rs_dst_tag        = i_rob_tag;
    assign o_rs_src_tag        = '{i_rob_src_tag[0], i_rob_src_tag[1]};
    assign o_rs_src_data       = '{i_rob_src_data[0], i_rob_src_data[1]};
    assign o_rs_src_rdy        = '{~rs_src_rdy[0] | i_rob_src_rdy[0], ~rs_src_rdy[1] | i_rob_src_rdy[1]};

    // Staging flops for insn fifo data & empty signal
    always_ff @(posedge clk) begin
        if (insn_fifo_en) insn_fifo_data <= i_insn_fifo_data;
    end

    always_ff @(posedge clk) begin
        insn_fifo_empty <= mux4_1b(insn_fifo_empty, i_insn_fifo_empty, 1'b1, 1'b1, insn_fifo_empty_sel);
    end

endmodule
