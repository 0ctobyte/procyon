// Re-Order Buffer
// Every cycle a new entry may be allocated at the head of the buffer
// Every cycle a ready entry at the tail of the FIFO is committed to the register file
// This enforces instructions to complete in program order

import types::*;

module reorder_buffer #(
    parameter DATA_WIDTH     = 32,
    parameter ADDR_WIDTH     = 32,
    parameter ROB_DEPTH      = 64,
    parameter REG_ADDR_WIDTH = 5,

    localparam TAG_WIDTH     = $clog2(ROB_DEPTH)
) (
    input logic                   clk,
    input logic                   n_rst,

    // The branch signal and iaddr are used by the Fetch unit to jump to the branch address
    output logic                  o_branch,
    output logic [ADDR_WIDTH-1:0] o_branch_addr,

    // Common Data Bus interface
    cdb_if.sink                   cdb,

    // Dispatcher <-> ROB interface to enqueue a new instruction
    rob_dispatch_if.sink          rob_dispatch, 

    // Interface to register map to update destination register for retired instruction
    regmap_dest_wr_if.source      dest_wr,

    // Interface to register map to update tag information of the destination register of the
    // newly enqueued instruction
    regmap_tag_wr_if.source       tag_wr,

    // Interface to register map to lookeup src register data/tags/rdy for newly enqueued instructions
    regmap_lookup_if.source       regmap_lookup [0:1]
);

    // ROB entry consists of the following:
    // rdy:    Is the data valid/ready?
    // branch: Did the instruction cause a branch? 
    // op:     What operation is the instruction doing?
    // iaddr:  Address of the instruction (for branches and to rollback on exception)
    // addr:   Destination address for store or branch 
    // data:   The data for the destination register
    // rdest:  The destination register 
    typedef struct packed {
        logic                      rdy;
        logic                      branch;
        rob_op_t                   op;
        logic [ADDR_WIDTH-1:0]     iaddr;
        logic [ADDR_WIDTH-1:0]     addr;
        logic [DATA_WIDTH-1:0]     data;
        logic [REG_ADDR_WIDTH-1:0] rdest;
    } rob_entries_t;

    typedef struct {
        // It's convenient to add an extra bit for the head and tail pointers so that they may wrap around and allow for easier queue full/empty detection
        logic [TAG_WIDTH:0]   head;
        logic [TAG_WIDTH:0]   tail;
        logic [TAG_WIDTH-1:0] head_addr;
        logic [TAG_WIDTH-1:0] tail_addr;
        logic                 full;
        logic                 empty;
        rob_entries_t         entries [0:ROB_DEPTH-1];
    } rob_t;
    rob_t rob;

    logic exc_taken;
    logic branch_taken;

    logic rob_dispatch_en;
    logic rob_retire_en;

    assign rob_dispatch_en = rob_dispatch.en && ~rob.full;
    assign rob_retire_en   = rob.entries[rob.head_addr].rdy && ~rob.empty && ~rob.entries[rob.head_addr].branch;

    // If the instruction to be retired generated a branch and it is ready then assert the branch signal
    assign branch_taken  = rob.entries[rob.head_addr].rdy && rob.entries[rob.head_addr].branch;
    assign o_branch      = branch_taken;
    assign o_branch_addr = rob.entries[rob.head_addr].addr;

    assign rob.tail_addr = rob.tail[TAG_WIDTH-1:0];
    assign rob.head_addr = rob.head[TAG_WIDTH-1:0]; 
    assign rob.full      = ({~rob.tail[TAG_WIDTH], rob.tail[TAG_WIDTH-1:0]} == rob.head);
    assign rob.empty     = (rob.tail == rob.head);

    // Assign outputs to regmap
    assign dest_wr.data  = rob.entries[rob.head_addr].data;
    assign dest_wr.rdest = rob.entries[rob.head_addr].rdest;
    assign dest_wr.wr_en = rob_retire_en;

    assign tag_wr.tag    = rob.tail_addr;
    assign tag_wr.rdest  = rob_dispatch.rdest;
    assign tag_wr.wr_en  = rob_dispatch_en;

    genvar i;
    generate
    for (i = 0; i < 2; i++) begin
        assign regmap_lookup[i].rsrc = rob_dispatch.rsrc[i];
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
    generate
    for (i = 0; i < 2; i++) begin
        always_comb begin
            case ({regmap_lookup[i].rdy, (cdb.en && (cdb.tag == regmap_lookup[i].tag))})
                2'b11: begin
                    rob_dispatch.src_data[i] = regmap_lookup[i].data;
                    rob_dispatch.src_tag[i]  = regmap_lookup[i].tag;
                    rob_dispatch.src_rdy[i]  = regmap_lookup[i].rdy;
                end
                2'b10: begin
                    rob_dispatch.src_data[i] = regmap_lookup[i].data;
                    rob_dispatch.src_tag[i]  = regmap_lookup[i].tag;
                    rob_dispatch.src_rdy[i]  = regmap_lookup[i].rdy;
                end
                2'b01: begin
                    rob_dispatch.src_data[i] = cdb.data;
                    rob_dispatch.src_tag[i]  = cdb.tag;
                    rob_dispatch.src_rdy[i]  = 'b1;
                end
                2'b00: begin
                    rob_dispatch.src_data[i] = rob.entries[regmap_lookup[i].tag].data;
                    rob_dispatch.src_tag[i]  = regmap_lookup[i].tag;
                    rob_dispatch.src_rdy[i]  = rob.entries[regmap_lookup[i].tag].rdy;
                end
            endcase
        end
    end
    endgenerate

    // Now update the ROB entry with the newly dispatched instruction
    // Or with the data broadcast over the CDB
    always_ff @(posedge clk) begin
        if (rob_dispatch_en) begin
            rob.entries[rob.tail_addr].rdy    = rob_dispatch.rdy;
            rob.entries[rob.tail_addr].branch = 'b0;
            rob.entries[rob.tail_addr].op     = rob_dispatch.op;
            rob.entries[rob.tail_addr].iaddr  = rob_dispatch.iaddr;
            rob.entries[rob.tail_addr].addr   = rob_dispatch.addr;
            rob.entries[rob.tail_addr].data   = rob_dispatch.data;
            rob.entries[rob.tail_addr].rdest  = rob_dispatch.rdest;
        end else if (cdb.en) begin
            rob.entries[cdb.tag].rdy          = 'b1;
            rob.entries[cdb.tag].branch       = cdb.branch;
            rob.entries[cdb.tag].data         = cdb.data;
            rob.entries[cdb.tag].addr         = cdb.addr;
        end
    end 

    // Increment the tail pointer if the dispatcher signals a new instruction to be enqueued
    // and the ROB is not full. Reset if branch taken
    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            rob.tail <= 'b0;
        end else if (branch_taken) begin
            rob.tail <= 'b0;
        end else if (rob_dispatch_en) begin
            rob.tail <= rob.tail + 1'b1;
        end
    end

    // Increment the head pointer if the instruction to be retired is ready and the ROB is not
    // empty (of course this should never be the case). Reset if branch taken
    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            rob.head <= 'b0;
        end else if (branch_taken) begin
            rob.head <= 'b0;
        end else if (rob_retire_en) begin
            rob.head <= rob.head + 1'b1;
        end
    end

endmodule
