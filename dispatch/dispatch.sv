// Dispatch module
// Takes an instruction from the instruction queue and performs the following functions
// 1) Allocates an entry in the ROB for the instruction and renames the destination register
// 2) Renames source operands by looking up the source operands in the register map & ROB
// 3) Allocates entry in the reservation station for the instruction

import types::*;

module dispatch #(
    parameter DATA_WIDTH     = 32,
    parameter ADDR_WIDTH     = 32,
    parameter REG_ADDR_WIDTH = 5
) (
    input  logic           clk,
    input  logic           n_rst,

    // Instruction FIFO interface
    fifo_rd_if.sys         insn_fifo_rd,

    // Reservation Station interface
    rs_dispatch_if.source  rs_dispatch,

    // ROB interface
    rob_dispatch_if.source rob_dispatch,
    rob_lookup_if.source   rob_lookup
);

    logic [DATA_WIDTH-1:0]     insn;
    logic [ADDR_WIDTH-1:0]     iaddr;
    logic [6:0]                opcode;
    logic [REG_ADDR_WIDTH-1:0] rdest;
    logic [REG_ADDR_WIDTH-1:0] rsrc [0:1];

    logic stall;
    logic enable;
    logic noop;

    // Pull out the signals from the insn FIFO
    assign insn  = insn_fifo_rd.data_out[DATA_WIDTH-1:0];
    assign iaddr = insn_fifo_rd.data_out[ADDR_WIDTH+DATA_WIDTH-1:DATA_WIDTH];

    // Pull out the relevant signals from the insn
    assign opcode  = insn[6:0];
    assign rdest   = insn[11:7];
    assign rsrc[0] = insn[19:15];
    assign rsrc[1] = insn[24:20];

    // Stall if either the reservation station is full or if the ROB is full
    // Assert enable only if there are no stalls and the insn FIFO is not empty
    assign stall  = rob_dispatch.stall || rs_dispatch.stall;
    assign enable = ~stall && ~insn_fifo_rd.empty; 

    assign insn_fifo_rd.rd_en = enable;
    assign rs_dispatch.en     = enable;
    assign rob_dispatch.en    = enable;

    assign rob_dispatch.iaddr = iaddr;
    assign rob_dispatch.addr  = 'b0;
    assign rob_dispatch.data  = 'b0; 

    assign rs_dispatch.iaddr      = iaddr;
    assign rs_dispatch.insn       = noop ? 32'h00000013 : insn;
    assign rs_dispatch.dst_tag    = rob_dispatch.tag; 

    genvar i;
    generate
    for (i = 0; i < 2; i++) begin
        assign rob_lookup.rsrc[i]    = noop ? 'b0 : rsrc[i];
        assign rs_dispatch.src_tag[i]  = rob_lookup.src_tag[i];
        assign rs_dispatch.src_data[i] = rob_lookup.src_data[i];
    end
    endgenerate

    always_comb begin
        case (opcode)
            OPCODE_OPIMM: begin
                rs_dispatch.opcode     = OPCODE_OPIMM;
                rs_dispatch.src_rdy[0] = rob_lookup.src_rdy[0];
                rs_dispatch.src_rdy[1] = 'b1;

                rob_dispatch.rdy       = 'b0;
                rob_dispatch.op        = ROB_OP_INT;
                rob_dispatch.rdest     = rdest;

                noop                   = 'b0;
            end
            OPCODE_LUI: begin
                rs_dispatch.opcode     = OPCODE_LUI;
                rs_dispatch.src_rdy[0] = 'b1;
                rs_dispatch.src_rdy[1] = 'b1;

                rob_dispatch.rdy       = 'b0;
                rob_dispatch.op        = ROB_OP_INT;
                rob_dispatch.rdest     = rdest;

                noop                   = 'b0;
            end
            OPCODE_AUIPC: begin
                rs_dispatch.opcode     = OPCODE_AUIPC;
                rs_dispatch.src_rdy[0] = 'b1;
                rs_dispatch.src_rdy[1] = 'b1;

                rob_dispatch.rdy       = 'b0;
                rob_dispatch.op        = ROB_OP_INT;
                rob_dispatch.rdest     = rdest;

                noop                   = 'b0;
            end
            OPCODE_OP: begin
                rs_dispatch.opcode     = OPCODE_OP;
                rs_dispatch.src_rdy[0] = rob_lookup.src_rdy[0];
                rs_dispatch.src_rdy[1] = rob_lookup.src_rdy[1];

                rob_dispatch.rdy       = 'b0;
                rob_dispatch.op        = ROB_OP_INT;
                rob_dispatch.rdest     = rdest;

                noop                   = 'b0;
            end
            OPCODE_JAL: begin
                rs_dispatch.opcode     = OPCODE_JAL;
                rs_dispatch.src_rdy[0] = 'b1;
                rs_dispatch.src_rdy[1] = 'b1;

                rob_dispatch.rdy       = 'b0;
                rob_dispatch.op        = ROB_OP_BR;
                rob_dispatch.rdest     = rdest;

                noop                   = 'b0;
            end
            OPCODE_JALR: begin
                rs_dispatch.opcode     = OPCODE_JALR;
                rs_dispatch.src_rdy[0] = rob_lookup.src_rdy[0];
                rs_dispatch.src_rdy[1] = 'b1;

                rob_dispatch.rdy       = 'b0;
                rob_dispatch.op        = ROB_OP_BR;
                rob_dispatch.rdest     = rdest;

                noop                   = 'b0;
            end
            OPCODE_BRANCH: begin
                rs_dispatch.opcode     = OPCODE_BRANCH;
                rs_dispatch.src_rdy[0] = rob_lookup.src_rdy[0];
                rs_dispatch.src_rdy[1] = rob_lookup.src_rdy[1];

                rob_dispatch.rdy       = 'b0;
                rob_dispatch.op        = ROB_OP_BR;
                rob_dispatch.rdest     = 'b0;

                noop                   = 'b0;
            end
            OPCODE_LOAD: begin
                rs_dispatch.opcode     = OPCODE_LOAD;
                rs_dispatch.src_rdy[0] = rob_lookup.src_rdy[0];
                rs_dispatch.src_rdy[1] = 'b1;

                rob_dispatch.rdy       = 'b0;
                rob_dispatch.op        = ROB_OP_LD;
                rob_dispatch.rdest     = rdest;

                noop                   = 'b0;
            end
            OPCODE_STORE: begin
                rs_dispatch.opcode     = OPCODE_STORE;
                rs_dispatch.src_rdy[0] = rob_lookup.src_rdy[0];
                rs_dispatch.src_rdy[1] = rob_lookup.src_rdy[1];

                rob_dispatch.rdy       = 'b0;
                rob_dispatch.op        = ROB_OP_STR;
                rob_dispatch.rdest     = 'b0;

                noop                   = 'b0;
            end
            default: begin
                rs_dispatch.opcode     = OPCODE_OPIMM;
                rs_dispatch.src_rdy[0] = rob_lookup.src_rdy[0];
                rs_dispatch.src_rdy[1] = 'b1;

                rob_dispatch.rdy       = 'b0;
                rob_dispatch.op        = ROB_OP_INT;
                rob_dispatch.rdest     = 'b0;

                noop                   = 'b1;
            end
        endcase
    end

endmodule
