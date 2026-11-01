// Keeps the verified 27 MHz / 512 sample rate and continuous I2S clocks.
module audio_sample_timing (
    input wire clk,
    output reg sample_tick = 1'b0,
    output reg frame_toggle = 1'b0,
    output reg i2s_bclk = 1'b0,
    output reg i2s_lrck = 1'b1,
    output reg [5:0] bit_index = 6'd63
);
    reg [1:0] divider = 2'd0;
    wire [5:0] next_bit = bit_index + 6'd1;
    always @(posedge clk) begin
        sample_tick <= 1'b0;
        if (divider == 2'd3) begin
            divider <= 2'd0;
            i2s_bclk <= ~i2s_bclk;
            if (i2s_bclk) begin
                bit_index <= next_bit;
                i2s_lrck <= next_bit[5];
                if (next_bit == 6'd0) begin
                    sample_tick <= 1'b1;
                    frame_toggle <= ~frame_toggle;
                end
            end
        end else begin
            divider <= divider + 1'b1;
        end
    end
endmodule
