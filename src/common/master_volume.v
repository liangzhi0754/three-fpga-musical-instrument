// Master gain after mixing. Unity preserves the previous maximum output level.
module master_volume (
    input wire clk,
    input wire sample_tick,
    input wire [15:0] volume_value,
    input wire volume_valid,
    input wire signed [15:0] audio_in,
    output reg signed [15:0] audio_out = 16'sd0
);
    wire [15:0] limited = (volume_value > 16'd26400) ? 16'd26400 : volume_value;
    // 1271 / 32768 closely approximates 1024 / 26400 without a divider.
    wire [26:0] scaled = limited * 11'd1271;
    wire [10:0] target_gain = !volume_valid ? 11'd0 :
                              (limited <= 16'd64) ? 11'd0 :
                              (limited >= 16'd26336) ? 11'd1024 : scaled[25:15];
    reg [10:0] gain = 11'd0;
    reg signed [27:0] product = 28'sd0;
    always @(posedge clk) begin
        if (sample_tick) begin
            // At most 2.43 ms for a full-scale change; avoid a hard gain jump.
            if (target_gain > gain)
                gain <= ((target_gain - gain) > 11'd8) ? gain + 11'd8 : target_gain;
            else if (gain > target_gain)
                gain <= ((gain - target_gain) > 11'd8) ? gain - 11'd8 : target_gain;
        end
        product <= audio_in * $signed({1'b0, gain});
        audio_out <= product[25:10];
    end
endmodule
