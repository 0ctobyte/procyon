// Generic linear shifting reservation station

import types::*;

module reservation_station #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter TAG_WIDTH  = 6,
    parameter RS_DEPTH   = 8
) (
    input  logic        clk,
    input  logic        n_rst,

    input  logic        i_flush,
    output logic        o_stall,

    // Dispatch interface
    rs_dispatch_if.sink rs_dispatch,

    // Functional Unit interface
    rs_funit_if.source  rs_funit
);

    typedef struct packed {
        opcode_t               opcode;
        logic [ADDR_WIDTH-1:0] iaddr;
        logic [DATA_WIDTH-1:0] insn;
        logic                  src_rdy  [0:1];
        logic [DATA_WIDTH-1:0] src_data [0:1];
        logic [TAG_WIDTH-1:0]  src_tag  [0:1];
        logic [TAG_WIDTH-1:0]  dst_tag;
        logic                  empty;
    } rs_entry_t;

    typedef struct packed {
        logic                full;
        logic [RS_DEPTH-1:0] issue_ready;
        logic [RS_DEPTH-1:0] shift_en;
        rs_entry_t           entries [RS_DEPTH-1:0];
    } rs_t;

    rs_t rs;

    // CDB bypass enable signals for each RS entry
    logic [RS_DEPTH-1:0] cdb_bypass;

    logic [RS_DEPTH-1:0] empty;
    logic [RS_DEPTH-1:0] issue_select;

    // Gather all the RS empty signals
    genvar i;
    generate
    for (i = 0; i < RS_DEPTH; i++) begin
        assign empty[i]       = rs[i].empty;
        assign issue_ready[i] = ~rs[i].empty && rs[i].src_rdy[0] && rs[i].src_rdy[1];
    end
    endgenerate

endmodule
