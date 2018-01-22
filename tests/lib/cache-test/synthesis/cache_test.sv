`include "../../../common/test_common.svh"

`define DATA_WIDTH      (16)

module cache_test (
    input  logic                         CLOCK_50,

    input  logic [17:0]                  SW,
    input  logic [3:0]                   KEY,
    output logic [17:0]                  LEDR,
    output logic [7:0]                   LEDG,

    inout  wire  [`SRAM_DATA_WIDTH-1:0]  SRAM_DQ,
    output logic [`SRAM_ADDR_WIDTH-1:0]  SRAM_ADDR,
    output logic                         SRAM_CE_N,
    output logic                         SRAM_WE_N,
    output logic                         SRAM_OE_N,
    output logic                         SRAM_LB_N,
    output logic                         SRAM_UB_N,

    output logic [6:0]                   HEX0,
    output logic [6:0]                   HEX1,
    output logic [6:0]                   HEX2,
    output logic [6:0]                   HEX3,
    output logic [6:0]                   HEX4,
    output logic [6:0]                   HEX5,
    output logic [6:0]                   HEX6,
    output logic [6:0]                   HEX7
);

    localparam TEST_RAM_DEPTH  = 64;
    localparam TEST_RAM_WIDTH  = $clog2(TEST_RAM_DEPTH);

    logic                              n_rst;

    logic                              wb_cyc;
    logic                              wb_stb;
    logic                              wb_we;
    logic [`WB_WORD_SIZE-1:0]          wb_sel;
    logic [`WB_ADDR_WIDTH-1:0]         wb_addr;
    logic [`WB_DATA_WIDTH-1:0]         wb_data_i;
    logic [`WB_DATA_WIDTH-1:0]         wb_data_o;
    logic                              wb_ack;
    logic                              wb_stall;

    logic                              drv_en;
    logic                              drv_we;
    logic [`WB_ADDR_WIDTH-1:0]         drv_addr;
    logic [`CACHE_LINE_WIDTH-1:0]      drv_data_o;
    logic [`CACHE_LINE_WIDTH-1:0]      drv_data_i;
    logic                              drv_done;
    logic                              drv_busy;

    logic                              cache_driver_re;
    logic                              cache_driver_we;
    logic [`WB_ADDR_WIDTH-1:0]         cache_driver_addr;
    logic [`DATA_WIDTH-1:0]            cache_driver_data_i;
    logic [`DATA_WIDTH-1:0]            cache_driver_data_o;
    logic                              cache_driver_hit;
    logic                              cache_driver_busy;

    logic [3:0]                        key_pulse;
    logic [`DATA_WIDTH-1:0]            out_data;

    assign n_rst                        = ~SW[17];
    assign LEDR[17]                     = SW[17];
    assign LEDR[16]                     = 1'b0;
    assign LEDR[15:0]                   = SW[15:0];
    assign LEDG[`CACHE_INDEX_WIDTH-1:0] = cache_driver_addr[`CACHE_INDEX_WIDTH+`CACHE_OFFSET_WIDTH-1:`CACHE_OFFSET_WIDTH];

    assign cache_driver_data_i          = SW[`WB_DATA_WIDTH-1:0];
    assign cache_driver_we              = key_pulse[1];
    assign cache_driver_re              = key_pulse[0];

    always_ff @(posedge CLOCK_50) begin
        if (cache_driver_hit && cache_driver_re) begin
            out_data <= cache_driver_data_o;
        end
    end

    always_ff @(posedge CLOCK_50, posedge SW[17]) begin
        if (SW[17]) begin
            cache_driver_addr <= 'b0;
        end else if (key_pulse[2]) begin
            cache_driver_addr <= cache_driver_addr + 1;
        end else if (key_pulse[3]) begin
            cache_driver_addr <= cache_driver_addr - 1;
        end
    end

    cache_driver #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ADDR_WIDTH(`WB_ADDR_WIDTH),
        .CACHE_SIZE(`CACHE_SIZE),
        .CACHE_LINE_SIZE(`CACHE_LINE_SIZE)
    ) cache_driver_inst (
        .clk(CLOCK_50),
        .n_rst(n_rst),
        .i_cache_driver_re(cache_driver_re),
        .i_cache_driver_we(cache_driver_we),
        .i_cache_driver_addr(cache_driver_addr),
        .i_cache_driver_data(cache_driver_data_i),
        .o_cache_driver_data(cache_driver_data_o),
        .o_cache_driver_hit(cache_driver_hit),
        .o_cache_driver_busy(cache_driver_busy),
        .i_cache_driver_biu_done(drv_done),
        .i_cache_driver_biu_busy(drv_busy),
        .i_cache_driver_biu_data(drv_data_o),
        .o_cache_driver_biu_en(drv_en),
        .o_cache_driver_biu_we(drv_we),
        .o_cache_driver_biu_addr(drv_addr),
        .o_cache_driver_biu_data(drv_data_i)
    );

    wb_sram #(
        .DATA_WIDTH(`WB_DATA_WIDTH),
        .ADDR_WIDTH(`WB_ADDR_WIDTH),
        .BASE_ADDR(`WB_SRAM_BASE_ADDR),
        .FIFO_DEPTH(`WB_SRAM_FIFO_DEPTH)
    ) wb_sram_inst (
        .i_wb_clk(CLOCK_50),
        .i_wb_rst(SW[17]),
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

    wb_master_driver #(
        .DATA_WIDTH(`CACHE_LINE_WIDTH),
        .WB_DATA_WIDTH(`WB_DATA_WIDTH),
        .ADDR_WIDTH(`WB_ADDR_WIDTH)
    ) wb_master_driver_inst (
        .i_wb_clk(CLOCK_50),
        .i_wb_rst(SW[17]),
        .o_wb_cyc(wb_cyc),
        .o_wb_stb(wb_stb),
        .o_wb_we(wb_we),
        .o_wb_sel(wb_sel),
        .o_wb_addr(wb_addr),
        .o_wb_data(wb_data_o),
        .i_wb_data(wb_data_i),
        .i_wb_ack(wb_ack),
        .i_wb_stall(wb_stall),
        .i_drv_en(drv_en),
        .i_drv_we(drv_we),
        .i_drv_addr(drv_addr),
        .i_drv_data(drv_data_i),
        .o_drv_data(drv_data_o),
        .o_drv_done(drv_done),
        .o_drv_busy(drv_busy)
    );

    genvar i;
    generate
    for (i = 0; i < 4; i++) begin : GENERATE_EDGE_DETECTORS
        edge_detector #(
            .EDGE(1)
        ) edge_detector_inst (
            .clk(CLOCK_50),
            .n_rst(n_rst),
            .i_async(KEY[i]),
            .o_pulse(key_pulse[i])
        );
    end
    endgenerate

    seg7_decoder seg7_inst0 (
        .n_rst(n_rst),
        .i_hex(out_data[3:0]),
        .o_hex(HEX0)
    );

    seg7_decoder seg7_inst1 (
        .n_rst(n_rst),
        .i_hex(out_data[7:4]),
        .o_hex(HEX1)
    );

    seg7_decoder seg7_inst2 (
        .n_rst(n_rst),
        .i_hex(out_data[11:8]),
        .o_hex(HEX2)
    );

    seg7_decoder seg7_inst3 (
        .n_rst(n_rst),
        .i_hex(out_data[15:12]),
        .o_hex(HEX3)
    );

    seg7_decoder seg7_inst4 (
        .n_rst(n_rst),
        .i_hex(cache_driver_addr[3:0]),
        .o_hex(HEX4)
    );

    seg7_decoder seg7_inst5 (
        .n_rst(n_rst),
        .i_hex(cache_driver_addr[7:4]),
        .o_hex(HEX5)
    );

    seg7_decoder seg7_inst6 (
        .n_rst(n_rst),
        .i_hex(cache_driver_addr[11:8]),
        .o_hex(HEX6)
    );

    seg7_decoder seg7_inst7 (
        .n_rst(n_rst),
        .i_hex(cache_driver_addr[15:12]),
        .o_hex(HEX7)
    );

endmodule
