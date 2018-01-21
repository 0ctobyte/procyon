`include "test_common.svh"

module sram_model (
    input logic                        clk,

    input logic [`SRAM_ADDR_WIDTH-1:0] i_sram_addr,
    inout wire  [`SRAM_DATA_WIDTH-1:0] io_sram_dq,
    input logic                        i_sram_ce_n,
    input logic                        i_sram_we_n,
    input logic                        i_sram_oe_n,
    input logic                        i_sram_ub_n,
    input logic                        i_sram_lb_n
);

    logic [(`SRAM_DATA_WIDTH/2)-1:0] sram_dq_lb;
    logic [(`SRAM_DATA_WIDTH/2)-1:0] sram_dq_ub;
    logic [`SRAM_DATA_WIDTH-1:0] sram [0:1048576];

    assign sram_dq_lb = (~i_sram_lb_n) ? io_sram_dq[(`SRAM_DATA_WIDTH/2)-1:0] : sram[i_sram_addr][(`SRAM_DATA_WIDTH/2)-1:0];
    assign sram_dq_ub = (~i_sram_ub_n) ? io_sram_dq[`SRAM_DATA_WIDTH-1:(`SRAM_DATA_WIDTH/2)] : sram[i_sram_addr][`SRAM_DATA_WIDTH-1:(`SRAM_DATA_WIDTH/2)];

    assign io_sram_dq[(`SRAM_DATA_WIDTH/2)-1:0] = (~i_sram_ce_n && ~i_sram_oe_n && i_sram_we_n) ?
                                                  (~i_sram_lb_n) ? sram[i_sram_addr][(`SRAM_DATA_WIDTH/2)-1:0] :
                                                  'bz : 'bz;

    assign io_sram_dq[`SRAM_DATA_WIDTH-1:(`SRAM_DATA_WIDTH/2)] = (~i_sram_ce_n && ~i_sram_oe_n && i_sram_we_n) ?
                                                                 (~i_sram_ub_n) ? sram[i_sram_addr][`SRAM_DATA_WIDTH-1:(`SRAM_DATA_WIDTH/2)] :
                                                                 'bz : 'bz;

    always_ff @(posedge clk) begin
        if (~i_sram_ce_n && ~i_sram_we_n) begin
            sram[i_sram_addr] <= {sram_dq_ub, sram_dq_lb};
        end
    end

endmodule
