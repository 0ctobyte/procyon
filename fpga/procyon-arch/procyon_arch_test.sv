`define SRAM_ADDR_WIDTH 20
`define SRAM_DATA_WIDTH 16

module procyon_arch_test #(
    parameter OPTN_DATA_WIDTH         = 32,
    parameter OPTN_ADDR_WIDTH         = 32,
    parameter OPTN_REGMAP_DEPTH       = 32,
    parameter OPTN_ROB_DEPTH          = 32,
    parameter OPTN_RS_IEU_DEPTH       = 16,
    parameter OPTN_RS_LSU_DEPTH       = 16,
    parameter OPTN_LQ_DEPTH           = 8,
    parameter OPTN_SQ_DEPTH           = 8,
    parameter OPTN_MHQ_DEPTH          = 4,
    parameter OPTN_DC_CACHE_SIZE      = 1024,
    parameter OPTN_DC_LINE_SIZE       = 32,
    parameter OPTN_DC_WAY_COUNT       = 1,
    parameter OPTN_WB_DATA_WIDTH      = 16,
    parameter OPTN_WB_ADDR_WIDTH      = 32,
    parameter OPTN_WB_SRAM_BASE_ADDR  = 0,
    parameter OPTN_WB_SRAM_FIFO_DEPTH = 8,
    parameter OPTN_HEX_FILE           = "",
    parameter OPTN_HEX_SIZE           = 0
) (
    input  logic                        CLOCK_50,
    input  logic [17:17]                SW,

    input  logic [0:0]                  KEY,

    output logic [17:0]                 LEDR,
    output logic [7:0]                  LEDG,

    inout  wire  [`SRAM_DATA_WIDTH-1:0] SRAM_DQ,
    output logic [`SRAM_ADDR_WIDTH-1:0] SRAM_ADDR,
    output logic                        SRAM_CE_N,
    output logic                        SRAM_WE_N,
    output logic                        SRAM_OE_N,
    output logic                        SRAM_LB_N,
    output logic                        SRAM_UB_N,

    output logic [6:0]                  HEX0,
    output logic [6:0]                  HEX1,
    output logic [6:0]                  HEX2,
    output logic [6:0]                  HEX3,
    output logic [6:0]                  HEX4,
    output logic [6:0]                  HEX5,
    output logic [6:0]                  HEX6,
    output logic [6:0]                  HEX7
);

    localparam REGMAP_IDX_WIDTH = $clog2(OPTN_REGMAP_DEPTH);
    localparam WB_WORD_SIZE     = OPTN_WB_DATA_WIDTH / 8;
    localparam TEST_STATE_WIDTH = 1;
    localparam TEST_STATE_RUN   = 1'b0;
    localparam TEST_STATE_HALT  = 1'b1;

    logic [TEST_STATE_WIDTH-1:0]   state;

    logic                          clk;
    logic                          n_rst;

    // FIXME: To test if simulations pass/fail
    logic [OPTN_DATA_WIDTH-1:0]    sim_tp;

    // FIXME: FPGA debugging output
    logic                          rob_redirect;
    logic [OPTN_ADDR_WIDTH-1:0]    rob_redirect_addr;
    logic                          regmap_retire_en;
    logic [REGMAP_IDX_WIDTH-1:0]   regmap_retire_rdest;
    logic [OPTN_DATA_WIDTH-1:0]    regmap_retire_data;

    // FIXME: Temporary instruction cache interface
    logic [OPTN_DATA_WIDTH-1:0]    ic_insn;
    logic                          ic_valid;
    logic [OPTN_ADDR_WIDTH-1:0]    ic_pc;
    logic                          ic_en;

    // Wishbone interface
    logic                          wb_rst;
    logic                          wb_ack;
    logic                          wb_stall;
    logic [OPTN_WB_DATA_WIDTH-1:0] wb_data_i;
    logic                          wb_cyc;
    logic                          wb_stb;
    logic                          wb_we;
    logic [WB_WORD_SIZE-1:0]       wb_sel;
    logic [OPTN_WB_ADDR_WIDTH-1:0] wb_addr;
    logic [OPTN_WB_DATA_WIDTH-1:0] wb_data_o;

    logic                          key0;
    logic                          key_pulse;
    logic [6:0]                    o_hex [0:7];

    assign n_rst      = SW[17];
    assign wb_rst     = n_rst;

    assign key0       = ~KEY[0];
    assign LEDR[17]   = SW[17];
    assign LEDR[16]   = rob_redirect;
    assign LEDR[15:0] = rob_redirect_addr[15:0];
    assign LEDG       = regmap_retire_rdest;
    assign HEX0       = o_hex[0];
    assign HEX1       = o_hex[1];
    assign HEX2       = o_hex[2];
    assign HEX3       = o_hex[3];
    assign HEX4       = o_hex[4];
    assign HEX5       = o_hex[5];
    assign HEX6       = o_hex[6];
    assign HEX7       = o_hex[7];

    always_comb begin
        case (state)
            TEST_STATE_RUN:  clk = CLOCK_50;
            TEST_STATE_HALT: clk = 1'b0;
        endcase
    end

    always_ff @(negedge CLOCK_50) begin
        if (~n_rst) begin
            state <= TEST_STATE_RUN;
        end else begin
            case (state)
                TEST_STATE_RUN:  state <= regmap_retire_en ? TEST_STATE_HALT : TEST_STATE_RUN;
                TEST_STATE_HALT: state <= key_pulse ? TEST_STATE_RUN : TEST_STATE_HALT;
            endcase
        end
    end

    genvar i;
    generate
        for (i = 0; i < 8; i++) begin : SEG7_DECODER_INSTANCES
            procyon_seg7_decoder procyon_seg7_decoder_inst (
                .n_rst(n_rst),
                .i_hex(regmap_retire_data[i*4+3:i*4]),
                .o_hex(o_hex[i])
            );
        end
    endgenerate

    procyon_edge_detector procyon_edge_detector_inst (
        .clk(CLOCK_50),
        .n_rst(n_rst),
        .i_async(key0),
        .o_pulse(key_pulse)
    );

    boot_rom #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_HEX_FILE(OPTN_HEX_FILE),
        .OPTN_HEX_SIZE(OPTN_HEX_SIZE)
    ) boot_rom_inst (
        .o_ic_insn(ic_insn),
        .o_ic_valid(ic_valid),
        .i_ic_pc(ic_pc),
        .i_ic_en(ic_en)
    );

    procyon #(
        .OPTN_DATA_WIDTH(OPTN_DATA_WIDTH),
        .OPTN_ADDR_WIDTH(OPTN_ADDR_WIDTH),
        .OPTN_REGMAP_DEPTH(OPTN_REGMAP_DEPTH),
        .OPTN_ROB_DEPTH(OPTN_ROB_DEPTH),
        .OPTN_RS_IEU_DEPTH(OPTN_RS_IEU_DEPTH),
        .OPTN_RS_LSU_DEPTH(OPTN_RS_LSU_DEPTH),
        .OPTN_LQ_DEPTH(OPTN_LQ_DEPTH),
        .OPTN_SQ_DEPTH(OPTN_SQ_DEPTH),
        .OPTN_MHQ_DEPTH(OPTN_MHQ_DEPTH),
        .OPTN_DC_CACHE_SIZE(OPTN_DC_CACHE_SIZE),
        .OPTN_DC_LINE_SIZE(OPTN_DC_LINE_SIZE),
        .OPTN_DC_WAY_COUNT(OPTN_DC_WAY_COUNT),
        .OPTN_WB_DATA_WIDTH(OPTN_WB_DATA_WIDTH),
        .OPTN_WB_ADDR_WIDTH(OPTN_WB_ADDR_WIDTH)
    ) procyon (
        .clk(clk),
        .n_rst(n_rst),
        .o_sim_tp(sim_tp),
        .o_rob_redirect(rob_redirect),
        .o_rob_redirect_addr(rob_redirect_addr),
        .o_regmap_retire_en(regmap_retire_en),
        .o_regmap_retire_rdest(regmap_retire_rdest),
        .o_regmap_retire_data(regmap_retire_data),
        .i_ic_insn(ic_insn),
        .i_ic_valid(ic_valid),
        .o_ic_pc(ic_pc),
        .o_ic_en(ic_en),
        .i_wb_clk(clk),
        .i_wb_rst(wb_rst),
        .i_wb_ack(wb_ack),
        .i_wb_stall(wb_stall),
        .i_wb_data(wb_data_i),
        .o_wb_cyc(wb_cyc),
        .o_wb_stb(wb_stb),
        .o_wb_we(wb_we),
        .o_wb_sel(wb_sel),
        .o_wb_addr(wb_addr),
        .o_wb_data(wb_data_o)
    );

    wb_sram #(
        .OPTN_WB_DATA_WIDTH(OPTN_WB_DATA_WIDTH),
        .OPTN_WB_ADDR_WIDTH(OPTN_WB_ADDR_WIDTH),
        .OPTN_BASE_ADDR(OPTN_WB_SRAM_BASE_ADDR),
        .OPTN_FIFO_DEPTH(OPTN_WB_SRAM_FIFO_DEPTH)
    ) wb_sram_inst (
        .i_wb_clk(clk),
        .i_wb_rst(wb_rst),
        .i_wb_cyc(wb_cyc),
        .i_wb_stb(wb_stb),
        .i_wb_we(wb_we),
        .i_wb_sel(wb_sel),
        .i_wb_addr(wb_addr),
        .i_wb_data(wb_data_o),
        .o_wb_data(wb_data_i),
        .o_wb_ack(wb_ack),
        .o_wb_stall(wb_stall),
        .io_sram_dq(SRAM_DQ),
        .o_sram_addr(SRAM_ADDR),
        .o_sram_ce_n(SRAM_CE_N),
        .o_sram_oe_n(SRAM_OE_N),
        .o_sram_we_n(SRAM_WE_N),
        .o_sram_ub_n(SRAM_UB_N),
        .o_sram_lb_n(SRAM_LB_N)
    );
endmodule
