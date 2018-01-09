// Re-Order Buffer
// Every cycle a new entry may be allocated at the tail of the buffer
// Every cycle a ready entry from the head of the FIFO is committed to the register file
// This enforces instructions to complete in program order

import types::*;

module reorder_buffer #(
    parameter DATA_WIDTH     = 32,
    parameter ADDR_WIDTH     = 32,
    parameter ROB_DEPTH      = 64,
    parameter REG_ADDR_WIDTH = 5
) (
    input  logic                                clk,
    input  logic                                n_rst,

    // The redirect signal and addr/iaddr are used by the Fetch unit to jump to the redirect address
    // Used for branches, exception etc.
    output logic                                o_redirect,
    output logic [ADDR_WIDTH-1:0]               o_redirect_addr,

    // Common Data Bus interface
    cdb_if.sink                                 cdb,

    // Dispatcher <-> ROB interface to enqueue a new instruction and lookup
    // data/tags for source operands of newly enqueued instructions
    input  logic                                i_rob_en,
    input  logic                                i_rob_rdy,
    input  rob_op_t                             i_rob_op,
    input  logic [ADDR_WIDTH-1:0]               i_rob_iaddr,
    input  logic [ADDR_WIDTH-1:0]               i_rob_addr,
    input  logic [DATA_WIDTH-1:0]               i_rob_data,
    input  logic [REG_ADDR_WIDTH-1:0]           i_rob_rdest,
    input  logic [REG_ADDR_WIDTH-1:0]           i_rob_rsrc     [0:1],
    output logic [$clog2(ROB_DEPTH)-1:0]        o_rob_tag,
    output logic [DATA_WIDTH-1:0]               o_rob_src_data [0:1],
    output logic [$clog2(ROB_DEPTH)-1:0]        o_rob_src_tag  [0:1],
    output logic                                o_rob_src_rdy  [0:1],
    output logic                                o_rob_stall,

    // Interface to register map to update destination register for retired instruction
    output logic [DATA_WIDTH-1:0]               o_regmap_retire_data,
    output logic [REG_ADDR_WIDTH-1:0]           o_regmap_retire_rdest,
    output logic [$clog2(ROB_DEPTH)-1:0]        o_regmap_retire_tag,
    output logic                                o_regmap_retire_wr_en,

    // Interface to register map to update tag information of the destination register of the
    // newly enqueued instruction
    output logic [$clog2(ROB_DEPTH)-1:0]        o_regmap_rename_tag,
    output logic [REG_ADDR_WIDTH-1:0]           o_regmap_rename_rdest,
    output logic                                o_regmap_rename_wr_en,

    // Interface to register map to lookeup src register data/tags/rdy for newly enqueued instructions
    input  logic                                i_regmap_lookup_rdy  [0:1],
    input  logic [$clog2(ROB_DEPTH)-1:0]        i_regmap_lookup_tag  [0:1],
    input  logic [DATA_WIDTH-1:0]               i_regmap_lookup_data [0:1],
    output logic [REG_ADDR_WIDTH-1:0]           o_regmap_lookup_rsrc [0:1]
);

    localparam TAG_WIDTH     = $clog2(ROB_DEPTH);

    // ROB entry consists of the following:
    // rdy:      Is the data valid/ready?
    // redirect: Asserted by branches or instructions that cause exceptions
    // op:       What operation is the instruction doing?
    // iaddr:    Address of the instruction (to rollback on exception)
    // addr:     Destination address for branch 
    // data:     The data for the destination register
    // rdest:    The destination register 
    typedef struct packed {
        logic                      rdy;
        logic                      redirect;
        rob_op_t                   op;
        logic [ADDR_WIDTH-1:0]     iaddr;
        logic [ADDR_WIDTH-1:0]     addr;
        logic [DATA_WIDTH-1:0]     data;
        logic [REG_ADDR_WIDTH-1:0] rdest;
    } rob_entry_t;

    typedef struct {
        // It's convenient to add an extra bit for the head and tail pointers so that they may wrap around and allow for easier queue full/empty detection
        logic [TAG_WIDTH:0]   head;
        logic [TAG_WIDTH:0]   tail;
        logic [TAG_WIDTH-1:0] head_addr;
        logic [TAG_WIDTH-1:0] tail_addr;
        logic                 full;
        logic                 empty;
        rob_entry_t           entries [0:ROB_DEPTH-1];
    } rob_t;
    rob_t rob;

    logic                 redirect;

    logic                 rob_dispatch_en;
    logic                 rob_retire_en;
    
    logic [ROB_DEPTH-1:0] rob_dispatch_select;
    logic [ROB_DEPTH-1:0] cdb_tag_select;
    
    assign rob_dispatch_select    = 1 << rob.tail_addr;
    assign cdb_tag_select         = 1 << cdb.tag;

    assign rob_dispatch_en        = i_rob_en && ~rob.full;
    assign rob_retire_en          = rob.entries[rob.head_addr].rdy && ~rob.empty;

    // If the instruction to be retired generated a branch and it is ready then assert the redirect signal
    assign redirect               = rob.entries[rob.head_addr].rdy && rob.entries[rob.head_addr].redirect;
    assign o_redirect             = redirect;
    assign o_redirect_addr        = rob.entries[rob.head_addr].addr;

    assign rob.tail_addr          = rob.tail[TAG_WIDTH-1:0];
    assign rob.head_addr          = rob.head[TAG_WIDTH-1:0]; 
    assign rob.full               = ({~rob.tail[TAG_WIDTH], rob.tail[TAG_WIDTH-1:0]} == rob.head);
    assign rob.empty              = (rob.tail == rob.head);

    // Assign outputs to regmap
    assign o_regmap_retire_data   = rob.entries[rob.head_addr].data;
    assign o_regmap_retire_rdest  = rob.entries[rob.head_addr].rdest;
    assign o_regmap_retire_tag    = rob.head_addr;
    assign o_regmap_retire_wr_en  = rob_retire_en;

    assign o_regmap_rename_tag    = rob.tail_addr;
    assign o_regmap_rename_rdest  = i_rob_rdest;
    assign o_regmap_rename_wr_en  = rob_dispatch_en;

    // Assign outputs to dispatcher
    // Stall if the ROB is full
    assign o_rob_stall            = rob.full;
    assign o_rob_tag              = rob.tail_addr;

    genvar i;
    generate
    for (i = 0; i < 2; i++) begin : ASSIGN_REGMAP_LOOKUP_RSRC
        assign o_regmap_lookup_rsrc[i] = i_rob_rsrc[i];
    end
    endgenerate 

    // Getting the right source register tags/data is tricky
    // If the register map has ready data then that must be used
    // Otherwise the ROB entry corresponding to the tag in the register map for the
    // source register is looked up and the data, if available, is retrieved from that 
    // entry. If it's not available then the instruction must wait for the tag to be broadcast
    // on the CDB. Now if there is something available on the CDB in the same cycle and it
    // matches the tag from the register map, then that value must be used over the ROB data.
    always_comb begin
        for (int i = 0; i < 2; i++) begin
            case ({i_regmap_lookup_rdy[i], (cdb.en && (cdb.tag == i_regmap_lookup_tag[i]))})
                2'b00: {o_rob_src_data[i], o_rob_src_tag[i], o_rob_src_rdy[i]} = {rob.entries[i_regmap_lookup_tag[i]].data, i_regmap_lookup_tag[i], rob.entries[i_regmap_lookup_tag[i]].rdy};
                2'b01: {o_rob_src_data[i], o_rob_src_tag[i], o_rob_src_rdy[i]} = {cdb.data, cdb.tag, 1'b1};
                2'b10: {o_rob_src_data[i], o_rob_src_tag[i], o_rob_src_rdy[i]} = {i_regmap_lookup_data[i], i_regmap_lookup_tag[i], i_regmap_lookup_rdy[i]};
                2'b11: {o_rob_src_data[i], o_rob_src_tag[i], o_rob_src_rdy[i]} = {i_regmap_lookup_data[i], i_regmap_lookup_tag[i], i_regmap_lookup_rdy[i]};
            endcase
        end
    end

    // Now update the ROB entry with the newly dispatched instruction
    // Or with the data broadcast over the CDB
    always_ff @(posedge clk) begin
        for (int i = 0; i < ROB_DEPTH; i++) begin
            if (rob_dispatch_en && rob_dispatch_select[i]) begin
                {rob.entries[i].op, rob.entries[i].iaddr, rob.entries[i].rdest} <= {i_rob_op, i_rob_iaddr, i_rob_rdest};
            end
        end
    end

    always_ff @(posedge clk) begin
        for (int i = 0; i < ROB_DEPTH; i++) begin
            if (rob_dispatch_en && rob_dispatch_select[i]) begin
                {rob.entries[i].redirect, rob.entries[i].addr, rob.entries[i].data} <= {1'b0, i_rob_addr, i_rob_data};
            end else if (cdb.en && cdb_tag_select[i]) begin
                {rob.entries[i].redirect, rob.entries[i].addr, rob.entries[i].data} <= {cdb.redirect, cdb.addr, cdb.data};
            end
        end
    end 

    // Clear the ready bits on a flush or reset
    always_ff @(posedge clk, negedge n_rst) begin
        for (int i = 0; i < ROB_DEPTH; i++) begin
            if (~n_rst) begin
                rob.entries[i].rdy <= 1'b0;
            end else if (redirect) begin
                rob.entries[i].rdy <= 1'b0;
            end else if (rob_dispatch_en && rob_dispatch_select[i]) begin
                rob.entries[i].rdy <= i_rob_rdy;
            end else if (cdb.en && cdb_tag_select[i]) begin
                rob.entries[i].rdy <= 1'b1;
            end
        end
    end 

    // Increment the tail pointer if the dispatcher signals a new instruction to be enqueued
    // and the ROB is not full. Reset if redirect asserted
    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            rob.tail <= 'b0;
        end else if (redirect) begin
            rob.tail <= 'b0;
        end else if (rob_dispatch_en) begin
            rob.tail <= rob.tail + 1'b1;
        end
    end

    // Increment the head pointer if the instruction to be retired is ready and the ROB is not
    // empty (of course this should never be the case). Reset if redirect asserted
    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            rob.head <= 'b0;
        end else if (redirect) begin
            rob.head <= 'b0;
        end else if (rob_retire_en) begin
            rob.head <= rob.head + 1'b1;
        end
    end

endmodule
