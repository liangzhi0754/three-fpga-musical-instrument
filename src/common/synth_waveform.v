// Quarter-cycle sine constants describe a waveform, not a recorded sound.
module synth_waveform (
    input wire [31:0] phase,
    input wire [1:0] timbre_mode,
    output wire signed [15:0] wave
);
    wire [6:0] sine_index = phase[30] ? (7'd64 - {1'b0, phase[29:24]}) :
                                                    {1'b0, phase[29:24]};
    reg [15:0] sine_magnitude;
    // A signed sawtooth gives a clearly brighter timbre than the sine wave.
    wire signed [15:0] saw_wave = $signed(phase[31:16]);
    wire signed [15:0] sine_wave = phase[31] ? -$signed(sine_magnitude) : $signed(sine_magnitude);
    wire signed [15:0] square_wave = phase[31] ? -16'sd32767 : 16'sd32767;
    assign wave = (timbre_mode == 2'd1) ? saw_wave :
                  (timbre_mode == 2'd2) ? square_wave : sine_wave;
    always @* begin
        case (sine_index)
            7'd0: sine_magnitude = 16'd0;
            7'd1: sine_magnitude = 16'd804;
            7'd2: sine_magnitude = 16'd1608;
            7'd3: sine_magnitude = 16'd2410;
            7'd4: sine_magnitude = 16'd3212;
            7'd5: sine_magnitude = 16'd4011;
            7'd6: sine_magnitude = 16'd4808;
            7'd7: sine_magnitude = 16'd5602;
            7'd8: sine_magnitude = 16'd6393;
            7'd9: sine_magnitude = 16'd7179;
            7'd10: sine_magnitude = 16'd7962;
            7'd11: sine_magnitude = 16'd8739;
            7'd12: sine_magnitude = 16'd9512;
            7'd13: sine_magnitude = 16'd10278;
            7'd14: sine_magnitude = 16'd11039;
            7'd15: sine_magnitude = 16'd11793;
            7'd16: sine_magnitude = 16'd12539;
            7'd17: sine_magnitude = 16'd13279;
            7'd18: sine_magnitude = 16'd14010;
            7'd19: sine_magnitude = 16'd14732;
            7'd20: sine_magnitude = 16'd15446;
            7'd21: sine_magnitude = 16'd16151;
            7'd22: sine_magnitude = 16'd16846;
            7'd23: sine_magnitude = 16'd17530;
            7'd24: sine_magnitude = 16'd18204;
            7'd25: sine_magnitude = 16'd18868;
            7'd26: sine_magnitude = 16'd19519;
            7'd27: sine_magnitude = 16'd20159;
            7'd28: sine_magnitude = 16'd20787;
            7'd29: sine_magnitude = 16'd21403;
            7'd30: sine_magnitude = 16'd22005;
            7'd31: sine_magnitude = 16'd22594;
            7'd32: sine_magnitude = 16'd23170;
            7'd33: sine_magnitude = 16'd23731;
            7'd34: sine_magnitude = 16'd24279;
            7'd35: sine_magnitude = 16'd24811;
            7'd36: sine_magnitude = 16'd25329;
            7'd37: sine_magnitude = 16'd25832;
            7'd38: sine_magnitude = 16'd26319;
            7'd39: sine_magnitude = 16'd26790;
            7'd40: sine_magnitude = 16'd27245;
            7'd41: sine_magnitude = 16'd27683;
            7'd42: sine_magnitude = 16'd28105;
            7'd43: sine_magnitude = 16'd28510;
            7'd44: sine_magnitude = 16'd28898;
            7'd45: sine_magnitude = 16'd29268;
            7'd46: sine_magnitude = 16'd29621;
            7'd47: sine_magnitude = 16'd29956;
            7'd48: sine_magnitude = 16'd30273;
            7'd49: sine_magnitude = 16'd30571;
            7'd50: sine_magnitude = 16'd30852;
            7'd51: sine_magnitude = 16'd31113;
            7'd52: sine_magnitude = 16'd31356;
            7'd53: sine_magnitude = 16'd31580;
            7'd54: sine_magnitude = 16'd31785;
            7'd55: sine_magnitude = 16'd31971;
            7'd56: sine_magnitude = 16'd32137;
            7'd57: sine_magnitude = 16'd32285;
            7'd58: sine_magnitude = 16'd32412;
            7'd59: sine_magnitude = 16'd32521;
            7'd60: sine_magnitude = 16'd32609;
            7'd61: sine_magnitude = 16'd32678;
            7'd62: sine_magnitude = 16'd32728;
            7'd63: sine_magnitude = 16'd32757;
            7'd64: sine_magnitude = 16'd32767;
            default: sine_magnitude = 16'd0;
        endcase
    end
endmodule
