// Dispatch module
// Takes an instruction from the instruction queue and performs the following functions
// 1) Allocates an entry in the ROB for the instruction and renames the destination register
// 2) Renames source operands by looking up the source operands in the register map & ROB
// 3) Allocates entry in the reservation station for the instruction

`include "common.svh"
import procyon_types::*;

module dispatch (
    input  logic                  clk,
    input  logic                  n_rst,

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

    logic [6:0]           opcode;
    procyon_data_t        insn;
    procyon_addr_t        iaddr;
    procyon_reg_t         rdest;
    procyon_reg_t         rsrc [0:1];
    logic                 insn_fifo_rdy;
    logic                 rob_rdy;
    logic                 rs_rdy;
    procyon_addr_data_t   insn_fifo_data;
    logic                 insn_fifo_empty;

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

    assign o_insn_fifo_rd_en   = rob_rdy && rs_rdy;
    assign o_rs_en             = insn_fifo_rdy && rob_rdy;
    assign o_rob_en            = insn_fifo_rdy && rs_rdy;

    assign o_rob_iaddr         = iaddr;
    assign o_rob_addr          = 'b0;
    assign o_rob_data          = 'b0;

    assign o_rs_iaddr          = iaddr;
    assign o_rs_insn           = insn;
    assign o_rs_dst_tag        = i_rob_tag;

    genvar i;
    generate
        for (i = 0; i < 2; i++) begin : ASSIGN_RS_AND_ROB_OUTPUTS
            assign o_rob_rsrc[i]    = rsrc[i];
            assign o_rs_src_tag[i]  = i_rob_src_tag[i];
            assign o_rs_src_data[i] = i_rob_src_data[i];
        end
    endgenerate

    // Staging flops for insn fifo data & empty signal
    always_ff @(posedge clk) begin
        if (rob_rdy && rs_rdy) begin
            insn_fifo_data  <= i_insn_fifo_data;
        end
    end

    always_ff @(posedge clk) begin
        if (i_flush) begin
            insn_fifo_empty <= 1'b1;
        end else if (rob_rdy && rs_rdy) begin
            insn_fifo_empty <= i_insn_fifo_empty;
        end
    end

    // Dispatch interface to reorder buffer and reservation stations
    always_comb begin
        case (opcode)
            OPCODE_OPIMM: begin
                {o_rs_opcode, o_rs_src_rdy[0], o_rs_src_rdy[1]} = {OPCODE_OPIMM, i_rob_src_rdy[0], 1'b1};
                {o_rob_op, o_rob_rdest, o_rob_rdy}              = {ROB_OP_INT, rdest, 1'b0};
            end
            OPCODE_LUI: begin
                {o_rs_opcode, o_rs_src_rdy[0], o_rs_src_rdy[1]} = {OPCODE_LUI, 1'b1, 1'b1};
                {o_rob_op, o_rob_rdest, o_rob_rdy}              = {ROB_OP_INT, rdest, 1'b0};
            end
            OPCODE_AUIPC: begin
                {o_rs_opcode, o_rs_src_rdy[0], o_rs_src_rdy[1]} = {OPCODE_AUIPC, 1'b1, 1'b1};
                {o_rob_op, o_rob_rdest, o_rob_rdy}              = {ROB_OP_INT, rdest, 1'b0};
            end
            OPCODE_OP: begin
                {o_rs_opcode, o_rs_src_rdy[0], o_rs_src_rdy[1]} = {OPCODE_OP, i_rob_src_rdy[0], i_rob_src_rdy[1]};
                {o_rob_op, o_rob_rdest, o_rob_rdy}              = {ROB_OP_INT, rdest, 1'b0};
            end
            OPCODE_JAL: begin
                {o_rs_opcode, o_rs_src_rdy[0], o_rs_src_rdy[1]} = {OPCODE_JAL, 1'b1, 1'b1};
                {o_rob_op, o_rob_rdest, o_rob_rdy}              = {ROB_OP_BR, rdest, 1'b0};
            end
            OPCODE_JALR: begin
                {o_rs_opcode, o_rs_src_rdy[0], o_rs_src_rdy[1]} = {OPCODE_JALR, i_rob_src_rdy[0], 1'b1};
                {o_rob_op, o_rob_rdest, o_rob_rdy}              = {ROB_OP_BR, rdest, 1'b0};
            end
            OPCODE_BRANCH: begin
                {o_rs_opcode, o_rs_src_rdy[0], o_rs_src_rdy[1]} = {OPCODE_BRANCH, i_rob_src_rdy[0], i_rob_src_rdy[1]};
                {o_rob_op, o_rob_rdest, o_rob_rdy}              = {ROB_OP_BR, {(`REG_ADDR_WIDTH){1'b0}}, 1'b0};
            end
            OPCODE_LOAD: begin
                {o_rs_opcode, o_rs_src_rdy[0], o_rs_src_rdy[1]} = {OPCODE_LOAD, i_rob_src_rdy[0], 1'b1};
                {o_rob_op, o_rob_rdest, o_rob_rdy}              = {ROB_OP_LD, rdest, 1'b0};
            end
            OPCODE_STORE: begin
                {o_rs_opcode, o_rs_src_rdy[0], o_rs_src_rdy[1]} = {OPCODE_STORE, i_rob_src_rdy[0], i_rob_src_rdy[1]};
                {o_rob_op, o_rob_rdest, o_rob_rdy}              = {ROB_OP_ST, {(`REG_ADDR_WIDTH){1'b0}}, 1'b0};
            end
            default: begin
                {o_rs_opcode, o_rs_src_rdy[0], o_rs_src_rdy[1]} = {OPCODE_OPIMM, 1'b1, 1'b1};
                {o_rob_op, o_rob_rdest, o_rob_rdy}              = {ROB_OP_INT, {(`REG_ADDR_WIDTH){1'b0}}, 1'b0};
            end
        endcase
    end

endmodule
