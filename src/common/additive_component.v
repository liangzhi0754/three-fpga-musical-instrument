// One independent oscillator used by the 32-component additive test voice.
module additive_component #(
    parameter [31:0] INITIAL_PHASE=0,
    parameter [15:0] ATTACK_STEP=16'd64,
    parameter [15:0] DECAY_STEP=16'd2,
    parameter [15:0] SUSTAIN_LEVEL=16'd45056,
    parameter [15:0] RELEASE_STEP=16'd6
)(
    input wire clk,
    input wire reset,
    input wire sample_tick,
    input wire gate,
    input wire [31:0] phase_step,
    output reg signed [15:0] sample = 16'sd0
);
    localparam [2:0] IDLE=0, ATTACK=1, DECAY=2, SUSTAIN=3, RELEASE=4;
    reg [31:0] phase = INITIAL_PHASE;
    reg [15:0] envelope = 16'd0;
    reg [2:0] state = IDLE;
    reg previous_gate = 1'b0;
    reg [15:0] next_envelope;
    reg [2:0] next_state;
    reg signed [24:0] product = 25'sd0;
    wire signed [15:0] wave;
    synth_waveform waveform(phase, 2'd0, wave);
    always @* begin
        next_envelope = envelope;
        next_state = state;
        if (gate && !previous_gate) begin
            next_state = ATTACK;
            next_envelope = (envelope > (16'hffff - ATTACK_STEP)) ?
                            16'hffff : envelope + ATTACK_STEP;
        end else if (!gate) begin
            if (envelope <= RELEASE_STEP) begin
                next_envelope = 16'd0;
                next_state = IDLE;
            end else begin
                next_envelope = envelope - RELEASE_STEP;
                next_state = RELEASE;
            end
        end else begin
            case (state)
                ATTACK: begin
                    if (envelope >= (16'hffff - ATTACK_STEP)) begin
                        next_envelope = 16'hffff;
                        next_state = DECAY;
                    end else next_envelope = envelope + ATTACK_STEP;
                end
                DECAY: begin
                    if (envelope <= (SUSTAIN_LEVEL + DECAY_STEP)) begin
                        next_envelope = SUSTAIN_LEVEL;
                        next_state = SUSTAIN;
                    end else next_envelope = envelope - DECAY_STEP;
                end
                SUSTAIN: next_envelope = SUSTAIN_LEVEL;
                default: begin next_state = ATTACK; next_envelope = ATTACK_STEP; end
            endcase
        end
    end
    always @(posedge clk) begin
        if (reset) begin
            phase <= INITIAL_PHASE;
            envelope <= 0;
            state <= IDLE;
            previous_gate <= 0;
            product <= 0;
            sample <= 0;
        end else begin
        if (sample_tick) begin
            phase <= phase + phase_step;
            envelope <= next_envelope;
            state <= next_state;
            previous_gate <= gate;
        end
        product <= wave * $signed({1'b0, envelope[15:8]});
        sample <= product[23:8];
        end
    end
endmodule
