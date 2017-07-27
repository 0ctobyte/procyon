// user-defined types and interfaces

package types;

    typedef enum logic [1:0] {
        ROB_OP_INT = 2'b00,
        ROB_OP_BR  = 2'b01,
        ROB_OP_LD  = 2'b10,
        ROB_OP_STR = 2'b11
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
    ) alu_func_t;

endpackage

import types::*;

// FIFO interface
interface fifo_wr_if #(
    parameter DATA_WIDTH = 8
) ();

    logic                  wr_en;
    logic [DATA_WIDTH-1:0] data_in;
    logic                  full;

    modport fifo (
        input  wr_en,
        input  data_in,
        output full
    );

    modport sys (
        output wr_en,
        output data_in,
        input  full
    );

endinterface

interface fifo_rd_if #(
    parameter DATA_WIDTH = 8
) ();

    logic                  rd_en;
    logic [DATA_WIDTH-1:0] data_out;
    logic                  empty;

    modport fifo (
        input  rd_en,
        output data_out,
        output empty
    );

    modport sys (
        output rd_en,
        input  data_out,
        input  empty
    );

endinterface

// Dual-Port RAM interface
interface dp_ram_if #(
    parameter DATA_WIDTH = 8,
    parameter RAM_DEPTH  = 8
) ();

    logic                         wr_en;
    logic [$clog2(RAM_DEPTH)-1:0] wr_addr;
    logic [DATA_WIDTH-1:0]        data_in;

    logic                         rd_en;
    logic [$clog2(RAM_DEPTH)-1:0] rd_addr;
    logic [DATA_WIDTH-1:0]        data_out;

    modport ram (
        input  wr_en,
        input  wr_addr,
        input  data_in,
        input  rd_en,
        input  rd_addr,
        output data_out
    );

    modport sys (
        output wr_en,
        output wr_addr,
        output data_in,
        output rd_en,
        output rd_addr,
        input  data_out
    );

endinterface

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

// Interface between the ROB and dispatcher to enqueue a new instruction
interface rob_dispatch_if #(
    parameter ADDR_WIDTH     = 32,
    parameter DATA_WIDTH     = 32,
    parameter TAG_WIDTH      = 6,
    parameter REG_ADDR_WIDTH = 5
) ();
    
    // Signals needed to enqueue new entry
    logic                      en;
    logic                      rdy;
    rob_op_t                   op;
    logic [ADDR_WIDTH-1:0]     iaddr;
    logic [ADDR_WIDTH-1:0]     addr;
    logic [DATA_WIDTH-1:0]     data;
    logic [REG_ADDR_WIDTH-1:0] rdest;
    logic [TAG_WIDTH-1:0]      tag;
    logic                      stall;

    modport source (
        output en,
        output rdy,
        output op,
        output iaddr,
        output addr,
        output data,
        output rdest,
        input  tag,
        input  stall
    );

    modport sink (
        input  en,
        input  rdy,
        input  op,
        input  iaddr,
        input  addr,
        input  data,
        input  rdest,
        output tag,
        output stall
    );

endinterface

// Interface between ROB and dispatcher to lookup tags/data for source operands
interface rob_lookup_if #(
    parameter DATA_WIDTH     = 32,
    parameter TAG_WIDTH      = 6,
    parameter REG_ADDR_WIDTH = 5
) ();

    // Lookup source operands
    logic [REG_ADDR_WIDTH-1:0] rsrc     [0:1];
    logic [DATA_WIDTH-1:0]     src_data [0:1];
    logic [TAG_WIDTH-1:0]      src_tag  [0:1];
    logic                      src_rdy  [0:1];

    modport source (
        output rsrc,
        input  src_data,
        input  src_tag,
        input  src_rdy
    );

    modport sink (
        input  rsrc,
        output src_data,
        output src_tag,
        output src_rdy
    );

endinterface

// Interface between ROB and register map to update destination register
// on instruction retire
interface regmap_dest_wr_if #(
    parameter DATA_WIDTH     = 32,
    parameter REG_ADDR_WIDTH = 5
) ();

    logic [DATA_WIDTH-1:0]     data;
    logic [REG_ADDR_WIDTH-1:0] rdest;
    logic                      wr_en;

    modport source (
        output data,
        output rdest,
        output wr_en
    );

    modport sink (
        input  data,
        input  rdest,
        input  wr_en
    );

endinterface

// Interface between ROB and register map to update tag of a register
// when renaming a new instructions destination register
interface regmap_tag_wr_if #(
    parameter TAG_WIDTH      = 6,
    parameter REG_ADDR_WIDTH = 5
) ();

    logic [TAG_WIDTH-1:0]      tag;
    logic [REG_ADDR_WIDTH-1:0] rdest;
    logic                      wr_en;

    modport source (
        output tag,
        output rdest,
        output wr_en
    );

    modport sink (
        input  tag,
        input  rdest,
        input  wr_en
    );

endinterface

// Interface between ROB and register map to allow the ROB 
// to look up tags and data and ready bits for the source operands of the next instruction
interface regmap_lookup_if #(
    parameter DATA_WIDTH     = 32,
    parameter TAG_WIDTH      = 6,
    parameter REG_ADDR_WIDTH = 5
) ();

    logic [REG_ADDR_WIDTH-1:0] rsrc [0:1];
    logic [DATA_WIDTH-1:0]     data [0:1];
    logic [TAG_WIDTH-1:0]      tag  [0:1];
    logic                      rdy  [0:1];

    modport source (
        output rsrc,
        input  data,
        input  tag,
        input  rdy
    );

    modport sink (
        input  rsrc,
        output data,
        output tag,
        output rdy
    );

endinterface

interface rs_dispatch_if #(
    parameter DATA_WIDTH     = 32,
    parameter ADDR_WIDTH     = 32,
    parameter TAG_WIDTH      = 6,
    parameter REG_ADDR_WIDTH = 5
) ();

    opcode_t               opcode;
    logic [ADDR_WIDTH-1:0] iaddr;
    logic [DATA_WIDTH-1:0] insn;
    logic [TAG_WIDTH-1:0]  src_tag  [0:1];
    logic [DATA_WIDTH-1:0] src_data [0:1];
    logic                  src_rdy  [0:1];
    logic [TAG_WIDTH-1:0]  dst_tag;
    logic                  en;
    logic                  stall;

    modport source (
        output opcode,
        output iaddr,
        output insn,
        output src_tag,
        output src_data,
        output src_rdy,
        output dst_tag,
        output en,
        input  stall
    );

    modport sink (
        input  opcode,
        input  iaddr,
        input  insn,
        input  src_tag,
        input  src_data,
        input  src_rdy,
        input  dst_tag,
        input  en,
        output stall
    );

endinterface

interface rs_funit_if #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter TAG_WIDTH  = 6
) ();

    opcode_t               opcode;
    logic [ADDR_WIDTH-1:0] iaddr;
    logic [DATA_WIDTH-1:0] insn;
    logic [DATA_WIDTH-1:0] src_a;
    logic [DATA_WIDTH-1:0] src_b;
    logic [TAG_WIDTH-1:0]  tag;
    logic                  valid;

    modport source (
        output opcode,
        output iaddr,
        output insn,
        output src_a,
        output src_b,
        output tag,
        output valid
    );
    
    modport sink (
        input  opcode,
        input  iaddr,
        input  insn,
        input  src_a,
        input  src_b,
        input  tag,
        input  valid
    );

endinterface
