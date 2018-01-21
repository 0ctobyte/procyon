`timescale 1ns/1ns

`include "../../common/test_common.svh"

`define DATA_WIDTH      (16)

module cache_tb;

    localparam TEST_RAM_DEPTH  = 64;
    localparam TEST_RAM_WIDTH  = $clog2(TEST_RAM_DEPTH);

    logic                              clk;
    logic                              n_rst;
    logic                              wb_rst;

    logic [`SRAM_ADDR_WIDTH-1:0]       sram_addr;
    wire  [`SRAM_DATA_WIDTH-1:0]       sram_dq;
    logic                              sram_ce_n;
    logic                              sram_we_n;
    logic                              sram_oe_n;
    logic                              sram_ub_n;
    logic                              sram_lb_n;

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

    logic [`DATA_WIDTH-1:0]            count;
    logic [TEST_RAM_WIDTH-1:0]         addr;
    logic [`DATA_WIDTH-1:0]            data;

    logic [`DATA_WIDTH-1:0]            test_ram [0:TEST_RAM_DEPTH-1];

    assign wb_rst              = ~n_rst;
    assign data                = test_ram[addr];

    assign cache_driver_we     = count < TEST_RAM_DEPTH;
    assign cache_driver_re     = ~cache_driver_we;
    assign cache_driver_addr   = {{(`WB_ADDR_WIDTH-TEST_RAM_WIDTH-1){1'b0}}, addr, 1'b0};
    assign cache_driver_data_i = data;

    always_ff @(posedge clk) begin
        if (count >= (TEST_RAM_DEPTH*2)) begin
            $display("----- PASS -----\n");
            $stop;
        end else if ((count < TEST_RAM_DEPTH) && cache_driver_hit) begin
            $display("STORE: %h to %h\n", data, cache_driver_addr);
        end else if ((count >= TEST_RAM_DEPTH) && cache_driver_hit) begin
           $display("LOAD: %h = %h from %h\n", cache_driver_data_o, data, cache_driver_addr);
           if (cache_driver_data_o == data) begin
               $display("----- OKAY -----\n");
           end else begin
               $display("----- FAIL -----\n");
               $stop;
           end
        end
    end

    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            count <= 'b0;
        end else if (cache_driver_hit) begin
            count <= count + 1'b1;
        end
    end

    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            addr <= 'b0;
        end else if (cache_driver_hit) begin
            addr <= addr + 1'b1;
        end
    end

    initial clk = 1'b1;
    always #10 clk = ~clk;

    initial begin
        $readmemh("test_pattern", test_ram);
    end

    initial begin
        n_rst = 1'b0;
        #20 n_rst = 1'b1;
    end

    cache_driver #(
        .DATA_WIDTH(`DATA_WIDTH),
        .ADDR_WIDTH(`WB_ADDR_WIDTH),
        .CACHE_SIZE(`CACHE_SIZE),
        .CACHE_LINE_SIZE(`CACHE_LINE_SIZE)
    ) cache_driver_inst (
        .clk(clk),
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
        .io_sram_dq(sram_dq),
        .o_sram_addr(sram_addr),
        .o_sram_ce_n(sram_ce_n),
        .o_sram_oe_n(sram_oe_n),
        .o_sram_we_n(sram_we_n),
        .o_sram_ub_n(sram_ub_n),
        .o_sram_lb_n(sram_lb_n)
    );

    wb_master_driver #(
        .DATA_WIDTH(`CACHE_LINE_WIDTH),
        .WB_DATA_WIDTH(`WB_DATA_WIDTH),
        .ADDR_WIDTH(`WB_ADDR_WIDTH)
    ) wb_master_driver_inst (
        .i_wb_clk(clk),
        .i_wb_rst(wb_rst),
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

    sram_model sram_model_inst (
        .clk(clk),
        .i_sram_addr(sram_addr),
        .io_sram_dq(sram_dq),
        .i_sram_ce_n(sram_ce_n),
        .i_sram_we_n(sram_we_n),
        .i_sram_oe_n(sram_oe_n),
        .i_sram_ub_n(sram_ub_n),
        .i_sram_lb_n(sram_lb_n)
    );

endmodule
