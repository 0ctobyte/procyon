// SRAM controller with a wishbone interface
// Controls the IS61WV102416BLL SRAM chip

// WISHBONE DATASHEET
// Description:                     Wishbone slave SRAM controller for the IS61WV102416BLL SRAM chip
// Wishbone rev:                    B4
// Supported Cycles:                Register feedback burst read/write
// CTI support:                     Classic, Incrementing Burst, End of Burst
// BTE support:                     Linear only
// Data port size:                  parameterized: 16-bit, 32-bit, 64-bit supported
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
`define SRAM_DATA_WIDTH 16
`define SRAM_ADDR_WIDTH 20
`define SRAM_DATA_SIZE  `SRAM_DATA_WIDTH / 8
`define SRAM_ADDR_SPAN  2097152 // 2M bytes, or 1M 2-byte words

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

module sram_wb #(
    parameter OPTN_WB_DATA_WIDTH = 16,
    parameter OPTN_WB_ADDR_WIDTH = 32,
    parameter OPTN_BASE_ADDR     = 0,

    parameter WB_DATA_SIZE       = OPTN_WB_DATA_WIDTH / 8
) (
    // Wishbone Interface
    input  logic                           i_wb_clk,
    input  logic                           i_wb_rst,
    input  logic                           i_wb_cyc,
    input  logic                           i_wb_stb,
    input  logic                           i_wb_we,
    input  logic [`WB_CTI_WIDTH-1:0]       i_wb_cti,
/* verilator lint_off UNUSED */
    input  logic [`WB_BTE_WIDTH-1:0]       i_wb_bte,
/* verilator lint_on  UNUSED */
    input  logic [WB_DATA_SIZE-1:0]        i_wb_sel,
/* verilator lint_off UNUSED */
    input  logic [OPTN_WB_ADDR_WIDTH-1:0]  i_wb_addr,
/* verilator lint_on  UNUSED */
    input  logic [OPTN_WB_DATA_WIDTH-1:0]  i_wb_data,
    output logic [OPTN_WB_DATA_WIDTH-1:0]  o_wb_data,
    output logic                           o_wb_ack,

    // SRAM interface
    output logic                           o_sram_ce_n,
    output logic                           o_sram_oe_n,
    output logic                           o_sram_we_n,
    output logic                           o_sram_lb_n,
    output logic                           o_sram_ub_n,
    output logic [`SRAM_ADDR_WIDTH-1:0]    o_sram_addr,
    inout  wire  [`SRAM_DATA_WIDTH-1:0]    io_sram_dq
);

    localparam GATHER_COUNT	           = OPTN_WB_DATA_WIDTH / `SRAM_DATA_WIDTH;
    localparam INITIAL_GATHER_COUNT    = GATHER_COUNT - 1;
    localparam GATHER_COUNT_WIDTH      = GATHER_COUNT == 1 ? 1 : $clog2(GATHER_COUNT);
    localparam SRAM_STATE_WIDTH        = 3;
    localparam SRAM_STATE_IDLE         = 3'b000;
    localparam SRAM_STATE_READ_ACK     = 3'b001;
    localparam SRAM_STATE_WRITE_ACK    = 3'b010;
    localparam SRAM_STATE_READ_GATHER  = 3'b011;
    localparam SRAM_STATE_WRITE_GATHER = 3'b100;

    logic [SRAM_STATE_WIDTH-1:0]   wb_sram_state_r;
    logic [SRAM_STATE_WIDTH-1:0]   wb_sram_state_next;
    logic                          wb_en;
    logic                          wb_we;
    logic                          wb_cti_eob;
    logic [`SRAM_DATA_SIZE-1:0]    wb_sel;
    logic [`SRAM_ADDR_WIDTH-1:0]   wb_addr;
    logic [`SRAM_DATA_WIDTH-1:0]   wb_data;
    logic [GATHER_COUNT_WIDTH-1:0] gather_cnt_r;
    logic [GATHER_COUNT_WIDTH-1:0] gather_cnt_next;
    logic [GATHER_COUNT_WIDTH-1:0] gather_idx_r;
    logic [GATHER_COUNT_WIDTH-1:0] gather_idx_next;

    // Qualify the write enable with a valid bus cycle
    assign wb_en       = i_wb_cyc && i_wb_stb;
    assign wb_we       = wb_en && i_wb_we;
    assign wb_cti_eob  = i_wb_cti == `WB_CTI_END_OF_BURST;
    assign wb_sel      = i_wb_sel[gather_idx_r*`SRAM_DATA_SIZE +: `SRAM_DATA_SIZE];
    assign wb_addr     = i_wb_addr[`SRAM_ADDR_WIDTH:1];
    assign wb_data     = i_wb_data[gather_idx_r*`SRAM_DATA_WIDTH +: `SRAM_DATA_WIDTH];

    // Assign SRAM outputs. Keep chip & output enable asserted
    assign o_sram_ce_n = 1'b0;
    assign o_sram_oe_n = 1'b0;
    assign o_sram_we_n = ~wb_we;
    assign o_sram_lb_n = ~wb_sel[0];
    assign o_sram_ub_n = ~wb_sel[1];
    assign o_sram_addr = wb_addr + ((wb_sram_state_r == SRAM_STATE_READ_ACK) ? `SRAM_ADDR_WIDTH'(GATHER_COUNT) : `SRAM_ADDR_WIDTH'(gather_idx_r));
    assign io_sram_dq  = wb_we ? wb_data : {(`SRAM_DATA_WIDTH){1'bz}};

    // Next state logic
    // GATHER_COUNT refers to how many operations it takes to read/write all the data from/to the wishbone bus to/from the SRAM
    // The SRAM can only handle 16 bit reads/writes in each cycle which means, depending on the wishbone data bus size, the read/write
    // will take place over multiple cycles. For example, if the WB data bus is 32 bits then a read operation will take two cycles
    // to gather the data from the SRAM and a thrid cycle to ACK. A write operation will take two cycles in total since the second
    // packet of 16 bits can be written to the SRAM in the same cycle the ACK is asserted with no issues.
    // The GATHER_COUNT is statically determined at elaboration time thus the state machine below will be different depending on the
    // GATHER_COUNT value. It is true that if the WB data bus is 16 bits (i.e the same as the SRAM data bus) then read/write operations
    // can take a single cycle (+ a second cycle for the ACK) and so the READ_GATHER/WRITE_GATHER states can be completely skipped.
    // Moreover, (as an optimization) in the case of GATHER_COUNT <= 2 (i.e. 16 bit or 32 bit WB data bus) the WRITE_GATHER state can
    // be completely skipped for writes since the last write packet can be committed to the SRAM on the same cycle the ACK is asserted.
    always_comb begin
        case (wb_sram_state_r)
            SRAM_STATE_IDLE: begin
                if (wb_we) begin
                    if (GATHER_COUNT > 2) wb_sram_state_next = SRAM_STATE_WRITE_GATHER;
                    else                  wb_sram_state_next = SRAM_STATE_WRITE_ACK;
                end else if (wb_en) begin
                    if (GATHER_COUNT > 1) wb_sram_state_next = SRAM_STATE_READ_GATHER;
                    else                  wb_sram_state_next = SRAM_STATE_READ_ACK;
                end else begin
                    wb_sram_state_next = SRAM_STATE_IDLE;
                end
            end
            SRAM_STATE_READ_ACK: begin
                if (~wb_cti_eob) begin
                    if (GATHER_COUNT > 1) wb_sram_state_next = SRAM_STATE_READ_GATHER;
                    else                  wb_sram_state_next = SRAM_STATE_READ_ACK;
                end else begin
                    wb_sram_state_next = SRAM_STATE_IDLE;
                end
            end
            SRAM_STATE_WRITE_ACK: begin
                if (~wb_cti_eob) begin
                    if (GATHER_COUNT > 1) wb_sram_state_next = SRAM_STATE_WRITE_GATHER;
                    else                  wb_sram_state_next = SRAM_STATE_WRITE_ACK;
                end else begin
                    wb_sram_state_next = SRAM_STATE_IDLE;
                end
            end
            SRAM_STATE_READ_GATHER: begin
                wb_sram_state_next = gather_cnt_r == 0 ? SRAM_STATE_READ_ACK : SRAM_STATE_READ_GATHER;
            end
            SRAM_STATE_WRITE_GATHER: begin
                wb_sram_state_next = gather_cnt_next == 0 ? SRAM_STATE_WRITE_ACK : SRAM_STATE_WRITE_GATHER;
            end
            default: begin
                wb_sram_state_next = SRAM_STATE_IDLE;
            end
        endcase
    end

    always_ff @(posedge i_wb_clk) begin
        if (i_wb_rst) wb_sram_state_r <= SRAM_STATE_IDLE;
        else          wb_sram_state_r <= wb_sram_state_next;
    end

    // Gather count and index register FSM
    // Tie these registers to zero if GATHER_COUNT == 1 (i.e. SRAM and WB data bus are the same widths, 16 bits)
    always_comb begin
        case (wb_sram_state_r)
            SRAM_STATE_IDLE: begin
                if (GATHER_COUNT > 1) begin
                    gather_cnt_next = wb_en ? GATHER_COUNT_WIDTH'(INITIAL_GATHER_COUNT-1) : GATHER_COUNT_WIDTH'(INITIAL_GATHER_COUNT);
                    gather_idx_next = wb_en ? GATHER_COUNT_WIDTH'(1) : {(GATHER_COUNT_WIDTH){1'b0}};
                end else begin
                    gather_cnt_next = {(GATHER_COUNT_WIDTH){1'b0}};
                    gather_idx_next = {(GATHER_COUNT_WIDTH){1'b0}};
                end
            end
            default: begin
                if (GATHER_COUNT > 1) begin
                    gather_cnt_next = gather_cnt_r - 1'b1;
                    gather_idx_next = gather_idx_r + 1'b1;
                end else begin
                    gather_cnt_next = {(GATHER_COUNT_WIDTH){1'b0}};
                    gather_idx_next = {(GATHER_COUNT_WIDTH){1'b0}};
                end
            end
        endcase
    end

    always_ff @(posedge i_wb_clk) begin
        if (i_wb_rst) begin
            gather_cnt_r <= {(GATHER_COUNT_WIDTH){1'b0}};
            gather_idx_r <= {(GATHER_COUNT_WIDTH){1'b0}};
        end else begin
            gather_cnt_r <= gather_cnt_next;
            gather_idx_r <= gather_idx_next;
        end
    end

    // Output to Wishbone interface
    always_ff @(posedge i_wb_clk) begin
        if (i_wb_rst) o_wb_ack <= 1'b0;
        else          o_wb_ack <= (wb_sram_state_next == SRAM_STATE_READ_ACK) || (wb_sram_state_next == SRAM_STATE_WRITE_ACK);
    end

    always_ff @(posedge i_wb_clk) begin
        o_wb_data[gather_idx_r*`SRAM_DATA_WIDTH +: `SRAM_DATA_WIDTH] <= io_sram_dq;
    end

endmodule
