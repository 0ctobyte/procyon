// SRAM controller with a wishbone interface
// Controls the IS61WV102416BLL SRAM chip

// WISHBONE DATASHEET
// Description:                     Wishbone slave SRAM controller for the IS61WV102416BLL SRAM chip
// Wishbone rev:                    B4
// Supported Cycles:                Register feedback burst read/write
// CTI support:                     Classic, Incrementing Burst, End of Burst
// BTE support:                     Linear only
// Data port size:                  parameterized: 8-bit, 16-bit, 32-bit, 64-bit supported
// Data port granularity:           8-bit
// Data port max operand size:      8-bit
// Data ordering:                   Little Endian
// Data sequence:                   Undefined
// Clock constraints:               None
// Wishbone signals mapping:
// i_wb_clk   -> CLK_I
// i_wb_rst   -> RST_I
// i_wb_cyc   -> CYC_I
// i_wb_stb   -> STB_I
// i_wb_we    -> WE_I
// i_wb_cti   -> CTI_I()
// i_wb_bte   -> BTE_I()
// i_wb_sel   -> SEL_I()
// i_wb_addr  -> ADR_I()
// i_wb_data  -> DAT_I()
// o_wb_ack   -> ACK_O
// o_wb_data  -> DAT_O()

// Constants
`define WB_SRAM_DATA_WIDTH 16
`define WB_SRAM_ADDR_WIDTH 20
`define WB_SRAM_ADDR_SPAN  2097152 // 2M bytes, or 1M 2-byte words

// Wishbone bus Cycle Type Identifiers
`define WB_CTI_WIDTH        3
`define WB_CTI_CLASSIC      (`WB_CTI_WIDTH'b000)
`define WB_CTI_CONSTANT     (`WB_CTI_WIDTH'b001)
`define WB_CTI_INCREMENTING (`WB_CTI_WIDTH'b010)
`define WB_CTI_END_OF_BURST (`WB_CTI_WIDTH'b111)

// Wishbone bus Burst Type Extensions
`define WB_BTE_WIDTH 2
`define WB_BTE_LINEAR (`WB_BTE_WIDTH'b00)
`define WB_BTE_4BEAT  (`WB_BTE_WIDTH'b01)
`define WB_BTE_8BEAT  (`WB_BTE_WIDTH'b10)
`define WB_BTE_16BEAT (`WB_BTE_WIDTH'b11)

module wb_sram #(
    parameter OPTN_WB_DATA_WIDTH = 16,
    parameter OPTN_WB_ADDR_WIDTH = 32,
    parameter OPTN_BASE_ADDR     = 0,
    parameter OPTN_FIFO_DEPTH    = 8,

    parameter WB_DATA_SIZE       = OPTN_WB_DATA_WIDTH / 8
) (
    // Wishbone Interface
    input  logic                           i_wb_clk,
    input  logic                           i_wb_rst,
    input  logic                           i_wb_cyc,
    input  logic                           i_wb_stb,
    input  logic                           i_wb_we,
    input  logic [`WB_CTI_WIDTH-1:0]       i_wb_cti,
    input  logic [`WB_BTE_WIDTH-1:0]       i_wb_bte,
    input  logic [WB_DATA_SIZE-1:0]        i_wb_sel,
    input  logic [OPTN_WB_ADDR_WIDTH-1:0]  i_wb_addr,
    input  logic [OPTN_WB_DATA_WIDTH-1:0]  i_wb_data,
    output logic [OPTN_WB_DATA_WIDTH-1:0]  o_wb_data,
    output logic                           o_wb_ack,

    // SRAM interface
    inout  wire  [`WB_SRAM_DATA_WIDTH-1:0] io_sram_dq,
    output logic [`WB_SRAM_ADDR_WIDTH-1:0] o_sram_addr,
    output logic                           o_sram_ce_n,
    output logic                           o_sram_oe_n,
    output logic                           o_sram_we_n,
    output logic                           o_sram_ub_n,
    output logic                           o_sram_lb_n
);

    localparam WB_SRAM_DATA_SIZE   = `WB_SRAM_DATA_WIDTH / 8;
    localparam FIFO_DATA_WIDTH     = `WB_SRAM_DATA_WIDTH + `WB_SRAM_ADDR_WIDTH + 1 + WB_SRAM_DATA_SIZE + 1;
    localparam WB_SRAM_STATE_WIDTH = 2;
    localparam WB_SRAM_STATE_IDLE  = 2'b00;
    localparam WB_SRAM_STATE_ACK0  = 2'b01;
    localparam WB_SRAM_STATE_ACK1  = 2'b10;

    logic [WB_SRAM_STATE_WIDTH-1:0] next_state;
    logic [WB_SRAM_STATE_WIDTH-1:0] state;

    logic                           unaligned;
    logic                           cs;
    logic                           n_rst;

    logic                           wb_slave_fifo_flush;
    logic                           wb_slave_fifo_ack;
    logic                           wb_slave_fifo_we;
    logic                           wb_slave_fifo_valid;
    logic                           wb_slave_fifo_full;
    logic [FIFO_DATA_WIDTH-1:0]     wb_slave_fifo_rd_data;
    logic [FIFO_DATA_WIDTH-1:0]     wb_slave_fifo_wr_data;

    logic [`WB_SRAM_DATA_WIDTH-1:0] sram_data;
    logic [`WB_SRAM_ADDR_WIDTH:0]   sram_addr;
    logic [WB_SRAM_DATA_SIZE-1:0]   sram_sel;
    logic                           sram_we;

    logic [7:0]                     sram_data_q;
/* verilator lint_off UNUSED */
    logic [`WB_SRAM_ADDR_WIDTH:0]   sram_addr_q;
    logic [WB_SRAM_DATA_SIZE-1:0]   sram_sel_q;
/* verilator lint_on  UNUSED */
    logic                           sram_we_q;

    assign n_rst                 = ~i_wb_rst;
/* verilator lint_off UNSIGNED */
    assign cs                    = (i_wb_addr >= OPTN_BASE_ADDR) & (i_wb_addr < (OPTN_BASE_ADDR + `WB_SRAM_ADDR_SPAN));
/* verilator lint_on  UNSIGNED */

    // Wire up FIFO interface, stall if FIFO is full, flush FIFO if there is
    // no valid bus cycle but the FIFO is not empty
    assign wb_slave_fifo_flush   = wb_slave_fifo_valid & ~i_wb_cyc;
    assign wb_slave_fifo_wr_data = {i_wb_data[`WB_SRAM_DATA_WIDTH-1:0], i_wb_addr[`WB_SRAM_ADDR_WIDTH:0], i_wb_sel[WB_SRAM_DATA_SIZE-1:0], i_wb_we};
    assign wb_slave_fifo_we      = i_wb_cyc & i_wb_stb & cs;
    assign wb_slave_fifo_ack     = next_state == WB_SRAM_STATE_ACK0;

    // Pull out signals from FIFO
    assign sram_data             = wb_slave_fifo_rd_data[FIFO_DATA_WIDTH-1:FIFO_DATA_WIDTH-`WB_SRAM_DATA_WIDTH];
    assign sram_addr             = wb_slave_fifo_rd_data[`WB_SRAM_ADDR_WIDTH+WB_SRAM_DATA_SIZE+1:WB_SRAM_DATA_SIZE+1];
    assign sram_sel              = wb_slave_fifo_rd_data[WB_SRAM_DATA_SIZE:1];
    assign sram_we               = wb_slave_fifo_rd_data[0];
    assign unaligned             = sram_addr[0];

    // Assign SRAM outputs
    assign o_sram_ce_n           = 1'b0;
    assign o_sram_oe_n           = 1'b0;
    assign io_sram_dq            = (state == WB_SRAM_STATE_ACK0 & sram_we) ? (unaligned ? {sram_data[7:0], 8'b0} : sram_data) :
                                   (state == WB_SRAM_STATE_ACK1 & sram_we_q) ? {8'b0, sram_data_q} :
                                   {{(`WB_SRAM_DATA_WIDTH){1'bz}}};

    // Latch sram data, addr, we and select signals for unaligned case
    always_ff @(posedge i_wb_clk) begin
        if (state == WB_SRAM_STATE_ACK0) begin
            sram_data_q <= sram_we ? sram_data[`WB_SRAM_DATA_WIDTH-1:8] : io_sram_dq[`WB_SRAM_DATA_WIDTH-1:8];
            sram_addr_q <= sram_addr + 1'b1;
            sram_sel_q  <= sram_sel;
            sram_we_q   <= sram_we;
        end
    end

    // Latch next state
    always_ff @(posedge i_wb_clk) begin
        if (i_wb_rst) begin
            state <= WB_SRAM_STATE_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // Update state
    always_comb begin
        case (state)
            WB_SRAM_STATE_IDLE:    next_state = ~wb_slave_fifo_valid | ~i_wb_cyc ? WB_SRAM_STATE_IDLE : WB_SRAM_STATE_ACK0;
            WB_SRAM_STATE_ACK0:    next_state = ~wb_slave_fifo_valid | ~i_wb_cyc ? WB_SRAM_STATE_IDLE : (unaligned ? WB_SRAM_STATE_ACK1 : WB_SRAM_STATE_ACK0);
            WB_SRAM_STATE_ACK1:    next_state = ~wb_slave_fifo_valid | ~i_wb_cyc ? WB_SRAM_STATE_IDLE : WB_SRAM_STATE_ACK0;
            default:               next_state = WB_SRAM_STATE_IDLE;
        endcase
    end

    // Output signals depending on state
    always_comb begin
        case (state)
            WB_SRAM_STATE_IDLE: begin
                o_wb_data   = {(`WB_SRAM_DATA_WIDTH){1'b0}};
                o_wb_ack    = 1'b0;
                o_sram_addr = {(`WB_SRAM_ADDR_WIDTH){1'b0}};
                o_sram_we_n = 1'b1;
                o_sram_ub_n = 1'b0;
                o_sram_lb_n = 1'b0;

            end
            WB_SRAM_STATE_ACK0: begin
                o_wb_data   = sram_we ? {{(`WB_SRAM_DATA_WIDTH){1'b0}}} : io_sram_dq;
                o_wb_ack    = ~unaligned;
                o_sram_addr = sram_addr[`WB_SRAM_ADDR_WIDTH:1];
                o_sram_we_n = ~sram_we;
                o_sram_ub_n = unaligned ? ~sram_sel[0] : ~sram_sel[1];
                o_sram_lb_n = unaligned ? 1'b1 : ~sram_sel[0];
            end
            WB_SRAM_STATE_ACK1: begin
                o_wb_data   = sram_we_q ? {{(`WB_SRAM_DATA_WIDTH){1'b0}}} : {io_sram_dq[7:0], sram_data_q};
                o_wb_ack    = 1'b1;
                o_sram_addr = sram_addr_q[`WB_SRAM_ADDR_WIDTH:1];
                o_sram_we_n = ~sram_we_q;
                o_sram_ub_n = 1'b1;
                o_sram_lb_n = ~sram_sel_q[1];
            end
            default: begin
                o_wb_data   = {(`WB_SRAM_DATA_WIDTH){1'b0}};
                o_wb_ack    = 1'b0;
                o_sram_addr = {(`WB_SRAM_ADDR_WIDTH){1'b0}};
                o_sram_we_n = 1'b1;
                o_sram_ub_n = 1'b0;
                o_sram_lb_n = 1'b0;
            end
        endcase
    end

    procyon_sync_fifo #(
        .OPTN_DATA_WIDTH(FIFO_DATA_WIDTH),
        .OPTN_FIFO_DEPTH(OPTN_FIFO_DEPTH)
    ) procyon_wb_slave_fifo (
        .clk(i_wb_clk),
        .n_rst(n_rst),
        .i_flush(wb_slave_fifo_flush),
        .i_fifo_ack(wb_slave_fifo_ack),
        .o_fifo_data(wb_slave_fifo_rd_data),
        .o_fifo_valid(wb_slave_fifo_valid),
        .i_fifo_we(wb_slave_fifo_we),
        .i_fifo_data(wb_slave_fifo_wr_data),
        .o_fifo_full(wb_slave_fifo_full)
    );

endmodule
