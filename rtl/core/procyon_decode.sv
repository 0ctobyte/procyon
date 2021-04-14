/*
 * Copyright (c) 2021 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

// Decode module
// Decodes and dispatches instructions over two cycles
// Cycle 1:
// * Decodes instruction
// * Renames destination register in Register Alias Table and reserves and entry in the ROB and RS
// * Lookup source register from the Register Alias Table
// Cycle 2:
// * Dispatches to ROB with new op, pc and rdst
// * Dispatches to reservation station with new op

`include "procyon_constants.svh"

module procyon_decode #(
    parameter OPTN_DATA_WIDTH       = 32,
    parameter OPTN_ADDR_WIDTH       = 32,
    parameter OPTN_RAT_IDX_WIDTH    = 5,
    parameter OPTN_ROB_IDX_WIDTH    = 5
)(
    input  logic                             clk,

    input  logic                             i_flush,
    input  logic                             i_rob_stall,
    input  logic                             i_rs_stall,

    // Fetch interface
    input  logic [OPTN_ADDR_WIDTH-1:0]       i_fetch_pc,
    input  logic [OPTN_DATA_WIDTH-1:0]       i_fetch_insn,
    input  logic                             i_fetch_valid,
    output logic                             o_decode_stall,

    // Register Alias Table lookup interface
    output logic [OPTN_RAT_IDX_WIDTH-1:0]    o_rat_lookup_rsrc [0:1],
    input  logic                             i_rat_lookup_rdy [0:1],
    input  logic [OPTN_DATA_WIDTH-1:0]       i_rat_lookup_data [0:1],
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]    i_rat_lookup_tag [0:1],

    // ROB lookup interface
    input  logic                             i_rob_lookup_rdy [0:1],
    input  logic [OPTN_DATA_WIDTH-1:0]       i_rob_lookup_data [0:1],

    // ROB tag used to rename destination register in the Register Alias Table
    input  logic [OPTN_ROB_IDX_WIDTH-1:0]    i_rob_dst_tag,

    // Register Alias Table rename interface
    output logic [OPTN_RAT_IDX_WIDTH-1:0]    o_rat_rename_rdst,

    // Reservation Station reserve interface
    output logic                             o_rs_reserve_en,
    output logic [`PCYN_OP_IS_WIDTH-1:0]     o_rs_reserve_op_is,

    // ROB reserve interface
    output logic                             o_rob_reserve_en,

    // ROB dispatch interface
    output logic [`PCYN_OP_IS_WIDTH-1:0]     o_rob_dispatch_op_is,
    output logic [OPTN_ADDR_WIDTH-1:0]       o_rob_dispatch_pc,
    output logic [OPTN_RAT_IDX_WIDTH-1:0]    o_rob_dispatch_rdst,
    output logic [OPTN_DATA_WIDTH-1:0]       o_rob_dispatch_rdst_data,

    // Reservation Station dispatch interface
    output logic [`PCYN_OP_WIDTH-1:0]        o_rs_dispatch_op,
    output logic [OPTN_DATA_WIDTH-1:0]       o_rs_dispatch_imm,
    output logic [OPTN_ROB_IDX_WIDTH-1:0]    o_rs_dispatch_dst_tag,
    output logic                             o_rs_dispatch_src_rdy [0:1],
    output logic [OPTN_DATA_WIDTH-1:0]       o_rs_dispatch_src_data [0:1],
    output logic [OPTN_ROB_IDX_WIDTH-1:0]    o_rs_dispatch_src_tag [0:1]
);

    assign o_decode_stall = i_rob_stall | i_rs_stall;

    // Signal the RS to reserve an entry
    logic dispatch_en;
    assign dispatch_en = ~i_flush & ~i_rs_stall & ~i_rob_stall & i_fetch_valid;

    // Decode op into the following control and data signals:
    // dispatch_op:        The operation this instruction intends to perform
    // dispatch_op_is:     Is the op a load, store or branch? These need to be treated a bit specially by the ROB and RS switch.
    // dispatch_pc:        The address of this instruction. For branches and jumps, this is the jump address (except for JALR)
    // dispatch_imm:       Immediate value needed by the instruction. Only stores use this because they use 2 source registers + immediate to calculate an address
    // dispatch_rdst:      The destination register for the result. For those instructions that don't update a register, this is set to 0
    // dispatch_rdst_data: The data to write to the destination register. This is only used by JAL and JALR where pc+4 is stored in the link register
    // lookup_rdy_ovrd:    Indicates whether we need to wait for a source register or not. Some instructions only need 1 source register.
    // lookup_data_ovrd:   Use the data in this signal instead of the ones in the ROB or Register Alias Table. Used to pass immediates via the source data field.
    logic [`PCYN_OP_WIDTH-1:0] dispatch_op;
    logic [OPTN_ADDR_WIDTH-1:0] dispatch_pc;
    logic [OPTN_DATA_WIDTH-1:0] dispatch_imm;
    logic [OPTN_RAT_IDX_WIDTH-1:0] dispatch_rdst;
    logic [OPTN_DATA_WIDTH-1:0] dispatch_rdst_data;
    logic [`PCYN_OP_IS_WIDTH-1:0] dispatch_op_is;
    logic [OPTN_RAT_IDX_WIDTH-1:0] lookup_rsrc [0:1];
    logic [1:0] lookup_rdy_ovrd;
    logic [OPTN_DATA_WIDTH-1:0] lookup_data_ovrd [0:1];

    always_comb begin
        logic [`PCYN_RV_OPCODE_WIDTH-1:0] opcode;
        logic [OPTN_RAT_IDX_WIDTH-1:0] rdst;
        logic [2:0] funct3;
        logic [6:0] funct7;
        logic [OPTN_DATA_WIDTH-1:0] imm_i;
        logic [OPTN_DATA_WIDTH-1:0] imm_s;
        logic [OPTN_DATA_WIDTH-1:0] imm_b;
        logic [OPTN_DATA_WIDTH-1:0] imm_u;
        logic [OPTN_DATA_WIDTH-1:0] imm_j;
        logic funct7_is_0;
        logic funct7_is_32;
        logic [1:0] funct7_mux_sel;
        logic [OPTN_ADDR_WIDTH-1:0] jmp_pc;
        logic [OPTN_ADDR_WIDTH-1:0] pc_plus_4;

        // Generate immediates
        imm_i = {{(OPTN_DATA_WIDTH-11){i_fetch_insn[31]}}, i_fetch_insn[30:25], i_fetch_insn[24:21], i_fetch_insn[20]};
        imm_s = {{(OPTN_DATA_WIDTH-11){i_fetch_insn[31]}}, i_fetch_insn[30:25], i_fetch_insn[11:8], i_fetch_insn[7]};
        imm_b = {{(OPTN_DATA_WIDTH-12){i_fetch_insn[31]}}, i_fetch_insn[7], i_fetch_insn[30:25], i_fetch_insn[11:8], 1'b0};
        imm_u = {{(OPTN_DATA_WIDTH-31){i_fetch_insn[31]}}, i_fetch_insn[30:25], i_fetch_insn[24:21], i_fetch_insn[20], i_fetch_insn[19:12], {12{1'b0}}};
        imm_j = {{(OPTN_DATA_WIDTH-20){i_fetch_insn[31]}}, i_fetch_insn[19:12], i_fetch_insn[20], i_fetch_insn[30:25], i_fetch_insn[24:21], 1'b0};

        lookup_rsrc[0] = i_fetch_insn[19:15];
        lookup_rsrc[1] = i_fetch_insn[24:20];
        rdst = i_fetch_insn[11:7];
        opcode = i_fetch_insn[6:0];
        funct3 = i_fetch_insn[14:12];
        funct7 = i_fetch_insn[31:25];

        funct7_is_0 = (funct7 == 0);
        funct7_is_32 = (funct7 == 7'b0100000);
        funct7_mux_sel = {funct7_is_32, funct7_is_0};
        jmp_pc = (i_fetch_insn[2] ? imm_j : imm_b) + i_fetch_pc;
        pc_plus_4 = i_fetch_pc + OPTN_DATA_WIDTH'(4);

        case (opcode)
            `PCYN_RV_OPCODE_OPIMM: begin
                case (funct3)
                    3'b000:  dispatch_op = `PCYN_OP_ADD;
                    3'b001:  dispatch_op = funct7_is_0 ? `PCYN_OP_SLL : `PCYN_OP_UNDEFINED;
                    3'b010:  dispatch_op = `PCYN_OP_LT;
                    3'b011:  dispatch_op = `PCYN_OP_LTU;
                    3'b100:  dispatch_op = `PCYN_OP_XOR;
                    3'b101:  dispatch_op = funct7_is_0 ? `PCYN_OP_SRL : (funct7_is_32 ? `PCYN_OP_SRA : `PCYN_OP_UNDEFINED);
                    3'b110:  dispatch_op = `PCYN_OP_OR;
                    3'b111:  dispatch_op = `PCYN_OP_AND;
                    default: dispatch_op = `PCYN_OP_UNDEFINED;
                endcase
                dispatch_op_is = `PCYN_OP_IS_OP;
                dispatch_pc = i_fetch_pc;
                dispatch_imm = imm_i;
                dispatch_rdst = rdst;
                dispatch_rdst_data = '0;
                lookup_rdy_ovrd = 2'b10;
                lookup_data_ovrd = '{'0, imm_i};
            end
            `PCYN_RV_OPCODE_LUI: begin
                dispatch_op = `PCYN_OP_ADD;
                dispatch_op_is = `PCYN_OP_IS_OP;
                dispatch_pc = i_fetch_pc;
                dispatch_imm = imm_u;
                dispatch_rdst = rdst;
                dispatch_rdst_data = '0;
                lookup_rdy_ovrd = 2'b11;
                lookup_data_ovrd = '{'0, imm_u};
            end
            `PCYN_RV_OPCODE_AUIPC: begin
                dispatch_op = `PCYN_OP_ADD;
                dispatch_op_is = `PCYN_OP_IS_OP;
                dispatch_pc = i_fetch_pc;
                dispatch_imm = imm_u;
                dispatch_rdst = rdst;
                dispatch_rdst_data = '0;
                lookup_rdy_ovrd = 2'b11;
                lookup_data_ovrd = '{i_fetch_pc, imm_u};
            end
            `PCYN_RV_OPCODE_OP: begin
                case (funct7_mux_sel)
                    2'b01: begin
                        case (funct3)
                            3'b000:  dispatch_op = `PCYN_OP_ADD;
                            3'b001:  dispatch_op = `PCYN_OP_SLL;
                            3'b010:  dispatch_op = `PCYN_OP_LT;
                            3'b011:  dispatch_op = `PCYN_OP_LTU;
                            3'b100:  dispatch_op = `PCYN_OP_XOR;
                            3'b101:  dispatch_op = `PCYN_OP_SRL;
                            3'b110:  dispatch_op = `PCYN_OP_OR;
                            3'b111:  dispatch_op = `PCYN_OP_AND;
                            default: dispatch_op = `PCYN_OP_UNDEFINED;
                        endcase
                    end
                    2'b10: begin
                        case (funct3)
                            3'b000:  dispatch_op = `PCYN_OP_SUB;
                            3'b101:  dispatch_op = `PCYN_OP_SRA;
                            default: dispatch_op = `PCYN_OP_UNDEFINED;
                        endcase
                    end
                    default begin
                        dispatch_op = `PCYN_OP_UNDEFINED;
                    end
                endcase
                dispatch_op_is = `PCYN_OP_IS_OP;
                dispatch_pc = i_fetch_pc;
                dispatch_imm = imm_i;
                dispatch_rdst = rdst;
                dispatch_rdst_data = '0;
                lookup_rdy_ovrd = 2'b00;
                lookup_data_ovrd = '{'0, '0};
            end
            `PCYN_RV_OPCODE_JAL: begin
                dispatch_op = `PCYN_OP_ADD;
                dispatch_op_is = `PCYN_OP_IS_JL;
                dispatch_pc = jmp_pc;
                dispatch_imm = imm_j;
                dispatch_rdst = rdst;
                dispatch_rdst_data = pc_plus_4;
                lookup_rdy_ovrd = 2'b11;
                lookup_data_ovrd = '{i_fetch_pc, imm_j};
            end
            `PCYN_RV_OPCODE_JALR: begin
                case (funct3)
                    3'b000:  dispatch_op = `PCYN_OP_ADD;
                    default: dispatch_op = `PCYN_OP_UNDEFINED;
                endcase
                dispatch_op_is = `PCYN_OP_IS_JL;
                dispatch_pc = i_fetch_pc;
                dispatch_imm = imm_i;
                dispatch_rdst = rdst;
                dispatch_rdst_data = pc_plus_4;
                lookup_rdy_ovrd = 2'b10;
                lookup_data_ovrd = '{'0, imm_i};
            end
            `PCYN_RV_OPCODE_BRANCH: begin
                case (funct3)
                    3'b000:  dispatch_op = `PCYN_OP_EQ;
                    3'b001:  dispatch_op = `PCYN_OP_NE;
                    3'b100:  dispatch_op = `PCYN_OP_LT;
                    3'b101:  dispatch_op = `PCYN_OP_GE;
                    3'b110:  dispatch_op = `PCYN_OP_LTU;
                    3'b111:  dispatch_op = `PCYN_OP_GEU;
                    default: dispatch_op = `PCYN_OP_UNDEFINED;
                endcase
                dispatch_op_is = `PCYN_OP_IS_BR;
                dispatch_pc = jmp_pc;
                dispatch_imm = imm_b;
                dispatch_rdst = '0;
                dispatch_rdst_data = '0;
                lookup_rdy_ovrd = 2'b00;
                lookup_data_ovrd = '{'0, '0};
            end
            `PCYN_RV_OPCODE_LOAD: begin
                case (funct3)
                    3'b000:  dispatch_op = `PCYN_OP_LB;
                    3'b001:  dispatch_op = `PCYN_OP_LH;
                    3'b010:  dispatch_op = `PCYN_OP_LW;
                    3'b100:  dispatch_op = `PCYN_OP_LBU;
                    3'b101:  dispatch_op = `PCYN_OP_LHU;
                    default: dispatch_op = `PCYN_OP_UNDEFINED;
                endcase
                dispatch_op_is = `PCYN_OP_IS_LD;
                dispatch_pc = i_fetch_pc;
                dispatch_imm = imm_i;
                dispatch_rdst = rdst;
                dispatch_rdst_data = '0;
                lookup_rdy_ovrd = 2'b10;
                lookup_data_ovrd = '{'0, imm_i};
            end
            `PCYN_RV_OPCODE_STORE: begin
                case (funct3)
                    3'b000:  dispatch_op = `PCYN_OP_SB;
                    3'b001:  dispatch_op = `PCYN_OP_SH;
                    3'b010:  dispatch_op = `PCYN_OP_SW;
                    default: dispatch_op = `PCYN_OP_UNDEFINED;
                endcase
                dispatch_op_is = `PCYN_OP_IS_ST;
                dispatch_pc = i_fetch_pc;
                dispatch_imm = imm_s;
                dispatch_rdst = '0;
                dispatch_rdst_data = '0;
                lookup_rdy_ovrd = 2'b00;
                lookup_data_ovrd = '{'0, '0};
            end
            default: begin
                dispatch_op = `PCYN_OP_UNDEFINED;
                dispatch_op_is = `PCYN_OP_IS_OP;
                dispatch_pc = i_fetch_pc;
                dispatch_imm = imm_i;
                dispatch_rdst = '0;
                dispatch_rdst_data = '0;
                lookup_rdy_ovrd = 2'b11;
                lookup_data_ovrd = '{'0, '0};
            end
        endcase

        // FIXME ignoring undefined ops for now
        if (dispatch_op == `PCYN_OP_UNDEFINED) begin
            lookup_rdy_ovrd = 2'b11;
            dispatch_rdst = '0;
        end
    end

    // Interface to Register Alias Table to lookup source operands
    assign o_rat_lookup_rsrc = lookup_rsrc;

    // Signal the ROB and RS to reserve an entry
    assign o_rob_reserve_en = dispatch_en;
    assign o_rs_reserve_en = dispatch_en;
    assign o_rs_reserve_op_is = dispatch_op_is;

    // Interface to Register Alias Table to rename destination register for new instruction
    assign o_rat_rename_rdst = dispatch_rdst;

    // Register dispatch signals to ROB and RS for the next cycle
    procyon_ff #(`PCYN_OP_IS_WIDTH) o_rob_dispatch_op_is_ff (.clk(clk), .i_en(1'b1), .i_d(dispatch_op_is), .o_q(o_rob_dispatch_op_is));
    procyon_ff #(OPTN_ADDR_WIDTH) o_rob_dispatch_pc_ff (.clk(clk), .i_en(1'b1), .i_d(dispatch_pc), .o_q(o_rob_dispatch_pc));
    procyon_ff #(OPTN_RAT_IDX_WIDTH) o_rob_dispatch_rdst_ff (.clk(clk), .i_en(1'b1), .i_d(dispatch_rdst), .o_q(o_rob_dispatch_rdst));
    procyon_ff #(OPTN_DATA_WIDTH) o_rob_dispatch_rdst_data_ff (.clk(clk), .i_en(1'b1), .i_d(dispatch_rdst_data), .o_q(o_rob_dispatch_rdst_data));

    procyon_ff #(`PCYN_OP_WIDTH) o_rs_dispatch_op_ff (.clk(clk), .i_en(1'b1), .i_d(dispatch_op), .o_q(o_rs_dispatch_op));
    procyon_ff #(OPTN_DATA_WIDTH) o_rs_dispatch_imm_ff (.clk(clk), .i_en(1'b1), .i_d(dispatch_imm), .o_q(o_rs_dispatch_imm));
    procyon_ff #(OPTN_ROB_IDX_WIDTH) o_rs_dispatch_dst_tag_ff (.clk(clk), .i_en(1'b1), .i_d(i_rob_dst_tag), .o_q(o_rs_dispatch_dst_tag));

    // Getting the right source register tags/data is tricky. If the register alias table has ready data then that must be used
    // Otherwise the ROB entry corresponding to the tag in the register alias table for the source register is looked up and the data,
    // if available, is retrieved from that entry. If it's not available then the instruction must wait for the tag to be broadcast
    // on the CDB. Now if there is something available on the CDB in the same cycle and it matches the tag from the register alias table,
    // then that value must be used over the ROB data.
    // An instructions source ready bits can be overrided to 1 if that instruction has no use for that source which allows it to skip waiting for that source in RS
    logic dispatch_src_rdy [0:1];
    logic [OPTN_DATA_WIDTH-1:0] dispatch_src_data_mux [0:1];

    always_comb begin
        for (int src_idx = 0; src_idx < 2; src_idx++) begin
            dispatch_src_rdy[src_idx]  = i_rat_lookup_rdy[src_idx] | i_rob_lookup_rdy[src_idx] | lookup_rdy_ovrd[src_idx];
            dispatch_src_data_mux[src_idx] = lookup_rdy_ovrd[src_idx] ? lookup_data_ovrd[src_idx] : (i_rat_lookup_rdy[src_idx] ? i_rat_lookup_data[src_idx] : i_rob_lookup_data[src_idx]);
        end
    end

    procyon_ff #(1) o_rs_dispatch_src_rdy_0_ff (.clk(clk), .i_en(1'b1), .i_d(dispatch_src_rdy[0]), .o_q(o_rs_dispatch_src_rdy[0]));
    procyon_ff #(1) o_rs_dispatch_src_rdy_1_ff (.clk(clk), .i_en(1'b1), .i_d(dispatch_src_rdy[1]), .o_q(o_rs_dispatch_src_rdy[1]));
    procyon_ff #(OPTN_DATA_WIDTH) o_rs_dispatch_src_data_0_ff (.clk(clk), .i_en(1'b1), .i_d(dispatch_src_data_mux[0]), .o_q(o_rs_dispatch_src_data[0]));
    procyon_ff #(OPTN_DATA_WIDTH) o_rs_dispatch_src_data_1_ff (.clk(clk), .i_en(1'b1), .i_d(dispatch_src_data_mux[1]), .o_q(o_rs_dispatch_src_data[1]));
    procyon_ff #(OPTN_ROB_IDX_WIDTH) o_rs_dispatch_src_tag_0_ff (.clk(clk), .i_en(1'b1), .i_d(i_rat_lookup_tag[0]), .o_q(o_rs_dispatch_src_tag[0]));
    procyon_ff #(OPTN_ROB_IDX_WIDTH) o_rs_dispatch_src_tag_1_ff (.clk(clk), .i_en(1'b1), .i_d(i_rat_lookup_tag[1]), .o_q(o_rs_dispatch_src_tag[1]));

endmodule
