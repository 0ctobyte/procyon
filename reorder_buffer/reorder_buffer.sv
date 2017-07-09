// Re-Order Buffer
// Every cycle a new entry may be allocated at the head of the buffer
// Every cycle a ready entry at the tail of the FIFO is committed to the register file
// This enforces instructions to complete in program order

module reorder_buffer #(
    parameter DATA_WIDTH         = 32,
    parameter ADDR_WIDTH         = 32,
    parameter REGFILE_DEPTH      = 32,
    parameter TAG_WIDTH          = 6,

    localparam REG_ADDR_WIDTH    = $clog2(REGFILE_DEPTH),
    localparam NUM_ROB_ENTRIES   = 1 << (TAG_WIDTH-1)
) (
    input  wire                         clk,
    input  wire                         n_rst,
    
    // Common Data Bus interface
    input  wire [TAG_WIDTH-1:0]         i_cdb_tag,
    input  wire [DATA_WIDTH-1:0]        i_cdb_data,
    input  wire                         i_cdb_exc, // Exception or branch mispredict 
    input  wire                         i_cdb_en,

    // Enqueue new entry request by Mapper/Dispatcher
    input  wire                         i_rob_enqueue_en,
    input  wire                         i_rob_enqueue_rdy,
    input  wire [1:0]                   i_rob_enqueue_op,
    input  wire [ADDR_WIDTH-1:0]        i_rob_enqueue_iaddr,
    input  wire [DATA_WIDTH-1:0]        i_rob_enqueue_data,
    input  wire [REG_ADDR_WIDTH-1:0]    i_rob_enqueue_rD,
    output wire [TAG_WIDTH-1:0]         o_rob_enqueue_tag,
    output wire                         o_rob_enqueue_stall,

    // Output data/rdy for source tags requested by Mapper/Dispatcher
    input  wire [TAG_WIDTH-1:0]         i_map_tag  [0:1],
    output wire [DATA_WIDTH-1:0]        o_map_data [0:1],
    output wire                         o_map_rdy  [0:1],

    // ROB outputs to register map and to fetch unit indicating branch
    // Exception signal is trigger to other units to flush their pipelines
    output wire                         o_rob_exc,
    output wire                         o_rob_br, 
    output wire [DATA_WIDTH-1:0]        o_rob_data,  // This will contain branch address if o_rob_br is asserted
    output wire [REG_ADDR_WIDTH-1:0]    o_rob_rD,
    output wire                         o_rob_rD_wr_en
);

    localparam INT_OP = 2'b00, BR_OP = 2'b01, LD_OP = 2'b10, STR_OP = 2'b11;
    
    // Create entry buffer RAMs
    reg                      rob_rdy        [0:NUM_ROB_ENTRIES-1]; // Ready to commit?
    reg                      rob_exc        [0:NUM_ROB_ENTRIES-1]; // Exception or Branch mispredict
    reg [1:0]                rob_op         [0:NUM_ROB_ENTRIES-1]; // load, store, branch or integer op 
    reg [ADDR_WIDTH-1:0]     rob_iaddr      [0:NUM_ROB_ENTRIES-1];
    reg [DATA_WIDTH-1:0]     rob_data       [0:NUM_ROB_ENTRIES-1];
    reg [REG_ADDR_WIDTH-1:0] rob_rD         [0:NUM_ROB_ENTRIES-1];

    // ROB head and tail counters. We enqueue at head and dequeue at tail
    // These are intentionally 1-MSB larger than the # of bits needed to store the buffer address so that they may wrap around
    // Also allows for easier full/empty detection
    reg [TAG_WIDTH-1:0] rob_head, rob_tail;

    // Head and Tail pointers into the ROB Queue
    wire [TAG_WIDTH-2:0] rob_head_addr, rob_tail_addr;

    // ROB full/empty signals
    wire rob_full, rob_empty;

    // ROB enqueue enable, dequeue enable
    wire rob_enqueue_en;
    wire rob_dequeue_en;

    // CDB tag convert to valid ROB addresses
    wire [TAG_WIDTH-2:0] cdb_tag_addr;

    // i_map_tag to ROB address
    wire [TAG_WIDTH-2:0] map_tag_addr [0:1];

    wire cdb_bypass [0:1];

    // Discard MSB for ROB addresses
    assign rob_head_addr = rob_head[TAG_WIDTH-2:0];
    assign rob_tail_addr = rob_tail[TAG_WIDTH-2:0];

    // Because of the symmetry of overflowing the binary head/tail counters we know the queue is empty if rob_head==rob_tail
    // and the queue is full if rob_head == rob_tail iff the MSB of rob_head is inverted (because the MSB indicates that the counter
    // has "wrapped around")
    assign rob_full  = ({~rob_head[TAG_WIDTH-1], rob_head[TAG_WIDTH-2:0]} == rob_tail);
    assign rob_empty = (rob_head == rob_tail);

    // Prevent manipulating the ROB incorrectly if rob_full or rob_empty
    assign rob_enqueue_en = (~rob_full && i_rob_enqueue_en);
    assign rob_dequeue_en = (~rob_empty && rob_rdy[rob_tail_addr]);

    // Discard MSB to generate real ROB addr
    assign cdb_tag_addr    = i_cdb_tag[TAG_WIDTH-2:0];

    // Bypass rob entry output to Mapper/Dispatcher if CDB has the value
    assign cdb_bypass[0] = (i_cdb_en && i_cdb_tag == i_map_tag[0]);
    assign cdb_bypass[1] = (i_cdb_en && i_cdb_tag == i_map_tag[1]);

    // Assign outputs to Mapper/Dispatcher
    // Stall if the ROB is full
    assign o_rob_enqueue_tag   = rob_head; 
    assign o_rob_enqueue_stall = rob_full;
    
    for (genvar i = 0; i < 2; i++) begin
        // Discard MSB to generate real ROB addr
        assign map_tag_addr[i] = i_map_tag[i][TAG_WIDTH-2:0];

        // Bypass rob entry output to Mapper/Dispatcher if CDB has the value
        assign cdb_bypass[i] = (i_cdb_en && i_cdb_tag == i_map_tag[i]);

        // Assign output to Mapper/Dispatcher for source inputs
        // bypass with CDB data if necessary
        assign o_map_data[i] = (cdb_bypass[i]) ? i_cdb_data : rob_data[map_tag_addr[i]];
        assign o_map_rdy[i]  = (cdb_bypass[i]) ? 'b1 : rob_rdy[map_tag_addr[i]];
    end

    // Assign outputs to register file and fetch unit as well as exception signal (for flushing)
    assign o_rob_exc      = rob_rdy[rob_tail_addr] && rob_exc[rob_tail_addr];
    assign o_rob_br       = rob_rdy[rob_tail_addr] && rob_exc[rob_tail_addr] && rob_op[rob_tail_addr] == BR_OP;
    assign o_rob_data     = rob_data[rob_tail_addr];
    assign o_rob_rD       = rob_rD[rob_tail_addr];
    assign o_rob_rD_wr_en = rob_rdy[rob_tail_addr];

    // Update head pointer
    always_ff @(posedge clk, negedge n_rst) begin : ROB_HEAD_Q
        if (~n_rst) begin
            rob_head <= 'b0;
        end else if (rob_enqueue_en) begin
            rob_head <= rob_head + 1;
        end
    end

    // Update tail pointer
    always_ff @(posedge clk, negedge n_rst) begin : ROB_TAIL_Q
        if (~n_rst) begin
            rob_tail <= 'b0;
        end else if (rob_dequeue_en) begin
            rob_tail <= rob_tail + 1;
        end
    end

    // Add entry to head
    always_ff @(posedge clk) begin
        if (rob_enqueue_en) begin
            rob_rdy[rob_head_addr]   <= i_rob_enqueue_rdy;
            rob_exc[rob_head_addr]   <= 'b0;
            rob_op[rob_head_addr]    <= i_rob_enqueue_op;
            rob_iaddr[rob_head_addr] <= i_rob_enqueue_iaddr;
            rob_data[rob_head_addr]  <= i_rob_enqueue_data;
            rob_rD[rob_head_addr]    <= i_rob_enqueue_rD;
        end
    end

    // Update entry specified by CDB tag
    // Move the entry to ready state
    always_ff @(posedge clk) begin
        if (i_cdb_en) begin
            rob_rdy[cdb_tag_addr]  <= 'b1;
            rob_exc[cdb_tag_addr]  <= i_cdb_exc;
            rob_data[cdb_tag_addr] <= i_cdb_data;
        end 
    end

endmodule
