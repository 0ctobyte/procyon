// user-defined types and interfaces

package types;

    typedef enum logic [1:0] {
        ROB_OP_INT = 2'b00,
        ROB_OP_BR  = 2'b01,
        ROB_OP_LD  = 2'b10,
        ROB_OP_ST  = 2'b11
    } rob_op_t;

    typedef enum logic [6:0] {
        OPCODE_OPIMM  = 7'b0010011,
        OPCODE_LUI    = 7'b0110111,
        OPCODE_AUIPC  = 7'b0010111,
        OPCODE_OP     = 7'b0110011,
        OPCODE_JAL    = 7'b1101111,
        OPCODE_JALR   = 7'b1100111,
        OPCODE_BRANCH = 7'b1100011,
        OPCODE_LOAD   = 7'b0000011,
        OPCODE_STORE  = 7'b0100011
    } opcode_t;

    typedef enum logic [3:0] {
        ALU_FUNC_ADD  = 4'b0000,
        ALU_FUNC_SUB  = 4'b0001,
        ALU_FUNC_AND  = 4'b0010,
        ALU_FUNC_OR   = 4'b0011,
        ALU_FUNC_XOR  = 4'b0100,
        ALU_FUNC_SLL  = 4'b0101,
        ALU_FUNC_SRL  = 4'b0110,
        ALU_FUNC_SRA  = 4'b0111,
        ALU_FUNC_EQ   = 4'b1000,
        ALU_FUNC_NE   = 4'b1001,
        ALU_FUNC_LT   = 4'b1010,
        ALU_FUNC_LTU  = 4'b1011,
        ALU_FUNC_GE   = 4'b1100,
        ALU_FUNC_GEU  = 4'b1101
    } alu_func_t;

    typedef enum logic [2:0] {
        LSU_FUNC_LB   = 3'b000,
        LSU_FUNC_LH   = 3'b001,
        LSU_FUNC_LW   = 3'b010,
        LSU_FUNC_LBU  = 3'b011,
        LSU_FUNC_LHU  = 3'b100,
        LSU_FUNC_SB   = 3'b101,
        LSU_FUNC_SH   = 3'b110,
        LSU_FUNC_SW   = 3'b111
    } lsu_func_t;

endpackage

import types::*;

// Common Data Bus interface
interface cdb_if #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter TAG_WIDTH  = 6
) ();

    logic [DATA_WIDTH-1:0] data;
    logic [ADDR_WIDTH-1:0] addr;
    logic [TAG_WIDTH-1:0]  tag;
    logic                  redirect;
    logic                  en;

    modport source (
        output  data,
        output  addr,
        output  tag,
        output  redirect,
        output  en
    );

    modport sink (
        input  data,
        input  addr,
        input  tag,
        input  redirect,
        input  en
    );

endinterface

interface arbiter_if ();

    logic req;
    logic gnt;

    modport source (
        output req,
        input  gnt
    );

    modport sink (
        input  req,
        output gnt
    );

endinterface
