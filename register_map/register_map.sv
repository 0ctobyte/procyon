// Register Map with tag information for register renaming

module register_map #(
    parameter DATA_WIDTH         = 32,
    parameter REGFILE_DEPTH      = 32,
    parameter TAG_WIDTH          = 6,

    localparam REG_ADDR_WIDTH    = $clog2(REGFILE_DEPTH)
) (
    input  wire                         clk,
    input  wire                         n_rst,

    // Update destinaton register request by ROB
    input  wire [REG_ADDR_WIDTH-1:0]    i_rD_rob,
    input  wire [DATA_WIDTH-1:0]        i_rD_rob_data,
    input  wire                         i_rD_rob_wr_en,

    // Update tag request by Mapper/Dispatcher
    input  wire [REG_ADDR_WIDTH-1:0]    i_rD_map,
    input  wire [DATA_WIDTH-1:0]        i_rD_map_tag,
    input  wire                         i_rD_map_wr_en,

    // Soure registers requested by Mapper/Dispatcher
    input  wire [REG_ADDR_WIDTH-1:0]    i_rsrc      [0:1],
    output wire [DATA_WIDTH-1:0]        o_rsrc_data [0:1],
    output wire [TAG_WIDTH-1:0]         o_rsrc_tag  [0:1],
    output wire                         o_rsrc_rdy  [0:1]
);

    // Each RF entry has a value, tag and ready bit
    reg [DATA_WIDTH-1:0] rf_data [0:REGFILE_DEPTH-1];
    reg [TAG_WIDTH-1:0]  rf_tag  [0:REGFILE_DEPTH-1];
    reg                  rf_rdy  [0:REGFILE_DEPTH-1];

    // Internal write enable
    wire rD_rob_wr_en;
    wire rD_map_wr_en;

    // Output rA and rB values. These are muxed with the RF table entries and the incoming rD values if rD == i_rA/i_rB
    wire                  rA_override, rB_override;
    wire [DATA_WIDTH-1:0] rA_data, rB_data;
    wire [TAG_WIDTH-1:0]  rA_tag, rB_tag;
    wire                  rA_rdy, rB_rdy;

    // Ignore i_rD_rob_wr_en if i_rD_rob == 0 since x0 is not a writable register
    // Ignore i_rD_map_wr_en if i_rD_map == 0 since x0 is not a writable register
    assign rD_rob_wr_en = i_rD_rob_wr_en && (i_rD_rob != 'b0);
    assign rD_map_wr_en = i_rD_map_wr_en && (i_rD_map != 'b0);

    // Override rA_data, rA_tag, rA_rdy if rD == i_rA
    // Override rB_data, rB_tag, rB_rdy if rD == i_rB
    assign rA_override = rD_rob_wr_en && (i_rD_rob == i_rsrc[0]);
    assign rB_override = rD_rob_wr_en && (i_rD_rob == i_rsrc[1]);

    // Pick up the rD value instead of what is in the register file if rD matches i_rA
    // if i_rA == 0 then assign 0;
    assign rA_data = (i_rsrc[0] == 'b0) ? 'b0 : (rA_override) ? i_rD_rob_data : rf_data[i_rsrc[0]];
    assign rA_tag = (rA_override) ? 'b0 : rf_tag[i_rsrc[0]];
    assign rA_rdy = (rA_override) ? 'b1 : rf_rdy[i_rsrc[0]];

    // Pick up the rD value instead of what is in the register file if rD matches i_rB
    // if i_rB == 0 then assign 0;
    assign rB_data = (i_rsrc[1] == 'b0) ? 'b0 : (rB_override) ? i_rD_rob_data : rf_data[i_rsrc[1]];
    assign rB_tag = (rB_override) ? 'b0 : rf_tag[i_rsrc[1]];
    assign rB_rdy = (rB_override) ? 'b1 : rf_rdy[i_rsrc[1]];

    // Assign outputs
    assign {o_rsrc_rdy[0], o_rsrc_tag[0], o_rsrc_data[0]} = {rA_rdy, rA_tag, rA_data};
    assign {o_rsrc_rdy[1], o_rsrc_tag[1], o_rsrc_data[1]} = {rB_rdy, rB_tag, rB_data};

    // Only the ROB updates the register value
    // This will have unknown values at reset, up to software to set register file to known values
    always_ff @(posedge clk) begin : RF_VAL_Q
        if (rD_rob_wr_en) begin
            rf_data[i_rD_rob] <= i_rD_rob_data;
        end
    end

    // Only the Mapper/Dispatcher updates the tags
    // This will have unknown values at reset
    always_ff @(posedge clk) begin : RF_TAG_Q
        if (rD_map_wr_en) begin
            rf_tag[i_rD_map] <= i_rD_map_tag;
        end
    end

    // The ready bit needs to be inferred as a flip-flop arrays rather than block RAM
    // because they need to be reset to a known value
    // The tricky case is when both the ROB and Mapper/Dispatcher attempts to modify the
    // same destination register on the same cycle. In this case, the Mapper/Dispatcher takes
    // priority and must clear the ready bit because any younger instructions issued must wait
    // for the value provided by the tag rather than the ROB committed value
    always_ff @(posedge clk, negedge n_rst) begin : RF_RDY_Q
        if (~n_rst) begin
            rf_rdy <= '{default:'b1};
        end else if (rD_map_wr_en) begin
            rf_rdy[i_rD_map] <= 'b0;
        end else if (rD_rob_wr_en) begin
            rf_rdy[i_rD_rob] <= 'b1;
        end
    end

endmodule
