// Seven Segment Decoder
// Take a 4-bit input and drive a 6-bit output powering
// a seven segment display

module procyon_seg7_decoder (
    input  logic       n_rst,

    input  logic [3:0] i_hex,
    output logic [6:0] o_hex
);

    // According to the DE2 manual, the seven segments are
    // active low and are arranged as follows:
    //       _
    //      |_|
    //      |_|
    //
    // going clockwise from the top horizontal segment the
    // segments are numbered: 0, 1, 2, 3, 4, 5 and the middle
    // horizontal segment is 6
    always_comb begin : SEG7_DECODE
        if (~n_rst) begin
            o_hex = 7'h7F;
        end else begin
            case(i_hex)
                4'b0000: o_hex = 7'h40;
                4'b0001: o_hex = 7'h79;
                4'b0010: o_hex = 7'h24;
                4'b0011: o_hex = 7'h30;
                4'b0100: o_hex = 7'h19;
                4'b0101: o_hex = 7'h12;
                4'b0110: o_hex = 7'h02;
                4'b0111: o_hex = 7'h78;
                4'b1000: o_hex = 7'h00;
                4'b1001: o_hex = 7'h18;
                4'b1010: o_hex = 7'h08;
                4'b1011: o_hex = 7'h03;
                4'b1100: o_hex = 7'h46;
                4'b1101: o_hex = 7'h21;
                4'b1110: o_hex = 7'h06;
                4'b1111: o_hex = 7'h0E;
            endcase
        end
    end

endmodule
