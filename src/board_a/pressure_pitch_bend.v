// Two independent pressure sensors bend the live pitch around the potentiometer.
// A0 raises pitch, A1 lowers pitch. The rest value is captured automatically on
// the first valid sample and can be refreshed with the existing zero command.
module pressure_pitch_bend(
    input wire clk,
    input wire [15:0] base_pitch,
    input wire [15:0] up_raw,
    input wire up_valid,
    input wire [15:0] down_raw,
    input wire down_valid,
    input wire capture_zero,
    output wire [15:0] adjusted_pitch
);
    localparam [15:0] PITCH_MIN = 16'd0;
    localparam [15:0] PITCH_MAX = 16'd26400;
    localparam [15:0] NOISE_BAND = 16'd128;

    reg [15:0] up_zero = 16'd0;
    reg [15:0] down_zero = 16'd0;
    reg up_zero_ready = 1'b0;
    reg down_zero_ready = 1'b0;

    always @(posedge clk) begin
        if (capture_zero) begin
            if (up_valid) begin up_zero <= up_raw; up_zero_ready <= 1'b1; end
            if (down_valid) begin down_zero <= down_raw; down_zero_ready <= 1'b1; end
        end else begin
            if (up_valid && !up_zero_ready) begin
                up_zero <= up_raw;
                up_zero_ready <= 1'b1;
            end
            if (down_valid && !down_zero_ready) begin
                down_zero <= down_raw;
                down_zero_ready <= 1'b1;
            end
        end
    end

    wire [15:0] up_delta = (up_valid && up_zero_ready && up_raw > up_zero)
                         ? up_raw - up_zero : 16'd0;
    wire [15:0] down_delta = (down_valid && down_zero_ready && down_raw > down_zero)
                           ? down_raw - down_zero : 16'd0;
    wire [15:0] up_effective = up_delta > NOISE_BAND ? up_delta - NOISE_BAND : 16'd0;
    wire [15:0] down_effective = down_delta > NOISE_BAND ? down_delta - NOISE_BAND : 16'd0;

    // v12.1: four times the v12 bend gain (1 unit per 4 ADC counts).
    // Keep the 128-count noise deadband and the final pitch limits unchanged.
    wire [15:0] up_bend = {2'b00, up_effective[15:2]};
    wire [15:0] down_bend = {2'b00, down_effective[15:2]};
    wire signed [17:0] summed = $signed({1'b0, base_pitch}) +
                                $signed({2'b0, up_bend}) -
                                $signed({2'b0, down_bend});
    assign adjusted_pitch = summed < 0 ? PITCH_MIN :
                            summed > PITCH_MAX ? PITCH_MAX : summed[15:0];
endmodule
