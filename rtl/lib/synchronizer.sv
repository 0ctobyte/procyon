// n-bit, m-deep Synchronizer
// Synchronizes an asynchronous signal into the clock domain
// The synchronization depth, m, (i.e. the number of flops from input signal
// to output signal) can be adjusted

module synchronizer #(
    parameter                       OPTN_DATA_WIDTH = 1,
    parameter                       OPTN_SYNC_DEPTH = 2,
    parameter [OPTN_DATA_WIDTH-1:0] OPTN_RESET_VAL  = 0
) (
    input  logic                  clk,
    input  logic                  n_rst,

    input  logic [OPTN_DATA_WIDTH-1:0] i_async_data,
    output logic [OPTN_DATA_WIDTH-1:0] o_sync_data
);

    // Synchronization flops
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [OPTN_DATA_WIDTH-1:0] sync_flops [0:OPTN_SYNC_DEPTH-1];

    // The last stage of flops in the synchronization pipeline holds our synchronized signal
    assign o_sync_data = sync_flops[OPTN_SYNC_DEPTH-1];

    // Capture the async signal
    always_ff @(posedge clk) begin : CAPTURE_ASYNC_SIGNAL
        if (~n_rst) begin
            sync_flops[0] <= OPTN_RESET_VAL;
        end else begin
            sync_flops[0] <= i_async_data;
        end
    end

    // Every clock cycle, propagate the captured async signal through the synchronization pipeline
    genvar i;
    generate
    for (i = 1; i < OPTN_SYNC_DEPTH; i = i + 1) begin : SYNC_FLOPS_PROPAGATE
        always_ff @(posedge clk) begin
            if (~n_rst) begin
                sync_flops[i] <= OPTN_RESET_VAL;
            end else begin
                sync_flops[i] <= sync_flops[i-1];
            end
        end
    end
    endgenerate

endmodule
