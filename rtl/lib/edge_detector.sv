// Posedge/Negedge Detector
// Use a synchronizer because the edge is most likely asynchronous
// Posedge detection is easy, the nth flop in the delay line LOW and the n-1 flop is HIGH
// Similarly for negedge detection, the nth flop is HIGH an the n-1 flop is LOW

module edge_detector #(
    parameter EDGE = 1  // Default "1" == detect posedge
) (
    input  logic clk,
    input  logic n_rst,

    input  logic i_async,
    output logic o_pulse
);

    // Last two flops in the synchronization pipeline
    logic pulse1;
    logic pulse0;

    generate if (~EDGE)
        assign o_pulse = pulse1 & ~pulse0;
    else
        assign o_pulse = ~pulse1 & pulse0;
    endgenerate

    synchronizer #(
        .DATA_WIDTH(1),
        .SYNC_DEPTH(2)
    ) sync (
        .clk(clk),
        .n_rst(n_rst),
        .i_async_data(i_async),
        .o_sync_data(pulse0)
    );

    always_ff @(posedge clk, negedge n_rst) begin
        if (~n_rst) begin
            pulse1 <= 1'b0;
        end else begin
            pulse1 <= pulse0;
        end
    end

endmodule
