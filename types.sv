// user-defined types and interfaces

package types;

    typedef enum logic [1:0] {
        INT = 2'b00,
        BR  = 2'b01,
        LD  = 2'b10,
        STR = 2'b11
    } rob_op_t;

endpackage

import types::*;

// Common Data Bus interface
interface cdb_if #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter TAG_WIDTH  = 6
) ();
   
    logic [ADDR_WIDTH-1:0] addr;
    logic [DATA_WIDTH-1:0] data;
    logic [TAG_WIDTH-1:0]  tag;
    logic                  branch;
    logic                  en; 

    modport source (
        output  addr,
        output  data,
        output  tag,
        output  branch,
        output  en
    );

    modport sink (
        input  addr,
        input  data,
        input  tag,
        input  branch,
        input  en
    );

endinterface

// Interface between the ROB and dispatcher to enqueue a new instruction
// and lookup tags/data for source operands
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

    // Lookup source operands
    logic [REG_ADDR_WIDTH-1:0] rsrc     [0:1];
    logic [DATA_WIDTH-1:0]     src_data [0:1];
    logic [TAG_WIDTH-1:0]      src_tag  [0:1];
    logic                      src_rdy  [0:1];

    modport source (
        output en,
        output rdy,
        output op,
        output iaddr,
        output addr,
        output data,
        output rdest,
        output rsrc,
        input  src_data,
        input  src_tag,
        input  src_rdy,
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
        input  rsrc,
        output src_data,
        output src_tag,
        output src_rdy,
        output tag,
        output stall
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

    logic [REG_ADDR_WIDTH-1:0] rsrc;
    logic [DATA_WIDTH-1:0]     data;
    logic [TAG_WIDTH-1:0]      tag;
    logic                      rdy;

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
