// Re-Order Buffer
// Every cycle a new entry may be allocated at the head of the buffer
// Every cycle a ready entry at the tail of the FIFO is committed to the register file
// This enforces instructions to complete in program order

import types::*;

module reorder_buffer #(
    parameter DATA_WIDTH     = 32,
    parameter ADDR_WIDTH     = 32,
    parameter ROB_DEPTH      = 64,
    parameter REG_ADDR_WIDTH = 5
) (
    input logic                   clk,
    input logic                   n_rst,

    // The redirect signal and iaddr are used by the Fetch unit to jump to the redirect address
    // Used for branches, exception etc.
    output logic                  o_redirect,
    output logic [ADDR_WIDTH-1:0] o_redirect_addr,

    // Common Data Bus interface
    cdb_if.sink                   cdb,

    // Dispatcher <-> ROB interface to enqueue a new instruction
    rob_dispatch_if.sink          rob_dispatch, 

    // Dispatcher <-> ROB interface to lookup data/tags for source operands of newly enqueued instruction
    rob_lookup_if.sink            rob_lookup, 

    // Interface to register map to update destination register for retired instruction
    regmap_dest_wr_if.source      dest_wr,

    // Interface to register map to update tag information of the destination register of the
    // newly enqueued instruction
    regmap_tag_wr_if.source       tag_wr,

    // Interface to register map to lookeup src register data/tags/rdy for newly enqueued instructions
    regmap_lookup_if.source       regmap_lookup
);

    localparam TAG_WIDTH     = $clog2(ROB_DEPTH);

    // ROB entry consists of the following:
    // rdy:      Is the data valid/ready?
    // redirect: Did the instruction cause a PC redirect to another address? 
    // op:       What operation is the instruction doing?
    // iaddr:    Address of the instruction (for branches and to rollback on exception)
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

    logic redirect;

    logic rob_dispatch_en;
    logic rob_retire_en;
    
    logic [ROB_DEPTH-1:0] rob_dispatch_select;
    logic [ROB_DEPTH-1:0] cdb_tag_select;
    
    assign rob_dispatch_select = 1 << rob.tail_addr;
    assign cdb_tag_select      = 1 << cdb.tag;

    assign rob_dispatch_en = rob_dispatch.en && ~rob.full;
    assign rob_retire_en   = rob.entries[rob.head_addr].rdy && ~rob.empty;

    // If the instruction to be retired generated a branch and it is ready then assert the redirect signal
    assign redirect        = rob.entries[rob.head_addr].rdy && rob.entries[rob.head_addr].redirect;
    assign o_redirect      = redirect;
    assign o_redirect_addr = rob.entries[rob.head_addr].addr;

    assign rob.tail_addr = rob.tail[TAG_WIDTH-1:0];
    assign rob.head_addr = rob.head[TAG_WIDTH-1:0]; 
    assign rob.full      = ({~rob.tail[TAG_WIDTH], rob.tail[TAG_WIDTH-1:0]} == rob.head);
    assign rob.empty     = (rob.tail == rob.head);

    // Assign outputs to regmap
    assign dest_wr.data  = rob.entries[rob.head_addr].data;
    assign dest_wr.rdest = rob.entries[rob.head_addr].rdest;
    assign dest_wr.tag   = rob.head_addr;
    assign dest_wr.wr_en = rob_retire_en;

    assign tag_wr.tag    = rob.tail_addr;
    assign tag_wr.rdest  = rob_dispatch.rdest;
    assign tag_wr.wr_en  = rob_dispatch_en;

    genvar i;
    generate
    for (i = 0; i < 2; i++) begin : ASSIGN_REGMAP_LOOKUP_SRCS
        assign regmap_lookup.rsrc[i] = rob_lookup.rsrc[i];
    end
    endgenerate 

    // Assign outputs to dispatcher
    // Stall if the ROB is full
    assign rob_dispatch.stall = rob.full;
    assign rob_dispatch.tag   = rob.tail_addr;

    // Getting the right source register tags/data is tricky
    // If the register map has ready data then that must be used
    // Otherwise the ROB entry corresponding to the tag in the register map for the
    // source register is looked up and the data, if available, is retrieved from that 
    // entry. If it's not available then the instruction must wait for the tag to be broadcast
    // on the CDB. Now if there is something available on the CDB in the same cycle and it
    // matches the tag from the register map, then that value must be used over the ROB data.
    always_comb begin
        for (int i = 0; i < 2; i++) begin
            case ({regmap_lookup.rdy[i], (cdb.en && (cdb.tag == regmap_lookup.tag[i]))})
                2'b00: {rob_lookup.src_data[i], rob_lookup.src_tag[i], rob_lookup.src_rdy[i]} = {rob.entries[regmap_lookup.tag[i]].data, regmap_lookup.tag[i], rob.entries[regmap_lookup.tag[i]].rdy};
                2'b01: {rob_lookup.src_data[i], rob_lookup.src_tag[i], rob_lookup.src_rdy[i]} = {cdb.data, cdb.tag, 1'b1};
                2'b10: {rob_lookup.src_data[i], rob_lookup.src_tag[i], rob_lookup.src_rdy[i]} = {regmap_lookup.data[i], regmap_lookup.tag[i], regmap_lookup.rdy[i]};
                2'b11: {rob_lookup.src_data[i], rob_lookup.src_tag[i], rob_lookup.src_rdy[i]} = {regmap_lookup.data[i], regmap_lookup.tag[i], regmap_lookup.rdy[i]};
            endcase
        end
    end

    // Now update the ROB entry with the newly dispatched instruction
    // Or with the data broadcast over the CDB
    always_ff @(posedge clk) begin
        for (int i = 0; i < ROB_DEPTH; i++) begin
            if (rob_dispatch_en && rob_dispatch_select[i]) begin
                {rob.entries[i].op, rob.entries[i].iaddr, rob.entries[i].rdest} <= {rob_dispatch.op, rob_dispatch.iaddr, rob_dispatch.rdest};
            end
        end
    end

    always_ff @(posedge clk) begin
        for (int i = 0; i < ROB_DEPTH; i++) begin
            if (rob_dispatch_en && rob_dispatch_select[i]) begin
                {rob.entries[i].redirect, rob.entries[i].addr, rob.entries[i].data} <= {1'b0, rob_dispatch.addr, rob_dispatch.data};
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
                rob.entries[i].rdy <= rob_dispatch.rdy;
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
