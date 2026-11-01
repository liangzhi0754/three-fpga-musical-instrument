// Robust EC11 decoder: synchronize and debounce the complete AB state.
// The output/telemetry interface is kept compatible with v11.1.
module rotary_encoder #(
    parameter integer DEBOUNCE_CLOCKS = 1350, // 50 us at 27 MHz
    parameter integer SAMPLE_WINDOW = 4096,
    parameter integer STOP_SAMPLES = 15821
)(
    input wire clk, sample_tick, enable, enc_a, enc_b,
    output reg active = 0,
    output reg direction = 1,
    output reg [13:0] depth = 0,
    output wire signed [31:0] modulation,
    output wire [13:0] diagnostic
);
    reg [1:0] a_sync=3, b_sync=3;
    reg [1:0] raw_state=3, stable_state=3, previous_state=3;
    reg [31:0] debounce_count=0;
    reg armed=0;
    reg signed [5:0] accumulator=0;
    reg [31:0] age=0, window=0;
    reg [7:0] events=0;
    reg [13:0] target_depth=0;
    reg [31:0] lfo_phase=0;
    reg signed [31:0] product=0;
    reg [1:0] raw_seen=0;
    reg legal_seen=0, illegal_seen=0;
    reg [5:0] motion_count=0;

    wire [1:0] current={a_sync[1],b_sync[1]};
    wire candidate_changed=current!=raw_state;
    wire commit=(!candidate_changed) && (debounce_count>=DEBOUNCE_CLOCKS) &&
                (raw_state!=stable_state);
    reg signed [2:0] edge_delta;
    always @* begin
        edge_delta=0;
        case ({previous_state,raw_state})
            4'b0001,4'b0111,4'b1110,4'b1000: edge_delta=1;
            4'b0010,4'b1011,4'b1101,4'b0100: edge_delta=-1;
            default: edge_delta=0;
        endcase
    end
    wire signed [6:0] accumulator_next=accumulator+edge_delta;
    wire at_detent=(raw_state==2'b00)||(raw_state==2'b11);
    // EC11 modules may be full-step or half-step. Count at a detent after
    // two net legal edges, and also accept four edges at any state.
    wire step=commit && armed && edge_delta!=0 &&
              ((at_detent && ((accumulator_next>=7'sd2)||
                              (accumulator_next<=-7'sd2))) ||
               (accumulator_next>=7'sd4)||(accumulator_next<=-7'sd4));
    wire [8:0] window_events={1'b0,events}+(step ? 9'd1:9'd0);
    wire [13:0] movement_depth=(window_events>=5)?14'd15000:
                                           14'd7000+window_events*14'd1600;
    wire signed [16:0] triangle=lfo_phase[31] ?
        17'sd32767-$signed({1'b0,lfo_phase[30:15]}) :
        $signed({1'b0,lfo_phase[30:15]})-17'sd32768;

    always @(posedge clk) begin
        a_sync<={a_sync[0],enc_a};
        b_sync<={b_sync[0],enc_b};
        if(candidate_changed) begin
            raw_seen<=raw_seen|(current^raw_state);
            raw_state<=current;
            debounce_count<=0;
        end else if(debounce_count<DEBOUNCE_CLOCKS)
            debounce_count<=debounce_count+1'b1;

        if(commit) begin
            stable_state<=raw_state;
            if(!armed) begin
                // Do not create a boot movement. The first stable state arms it.
                previous_state<=raw_state;
                accumulator<=0;
                armed<=1;
            end else if(edge_delta==0) begin
                // A two-bit jump is rejected and the decoder resynchronizes.
                previous_state<=raw_state;
                accumulator<=0;
                illegal_seen<=1;
            end else begin
                previous_state<=raw_state;
                legal_seen<=1;
                if(step) begin
                    direction<=accumulator_next>0;
                    accumulator<=0;
                    if(motion_count!=63) motion_count<=motion_count+1'b1;
                    age<=STOP_SAMPLES;
                    if(enable) target_depth<=movement_depth;
                    if(events!=255) events<=events+1'b1;
                end else accumulator<=accumulator_next;
            end
        end
        if(sample_tick && !step && age!=0) age<=age-1'b1;

        if(sample_tick) begin
            lfo_phase<=lfo_phase+32'd407226;
            active<=step||age!=0;
            if(window==SAMPLE_WINDOW-1) begin
                window<=0;
                events<=0;
                if(window_events!=0) begin
                    target_depth<=movement_depth;
                end
            end else window<=window+1'b1;
            if(!enable || (age==0 && !step)) target_depth<=0;
            if(depth<target_depth) begin
                if(target_depth-depth<=12) depth<=target_depth;
                else depth<=depth+14'd12;
            end else if(depth>target_depth) begin
                if(depth-target_depth<=12) depth<=target_depth;
                else depth<=depth-14'd12;
            end
        end
        product<=triangle*$signed({1'b0,depth});
    end
    // Two times depth in Q20: maximum +/-30000 (about +/-50 cents).
    assign modulation=enable ? (product>>>14):32'sd0;
    // {motion_count, illegal_seen, legal_seen, stable_state,
    //  raw_seen, current}; kept compatible with v11.1 host diagnostics.
    assign diagnostic={motion_count,illegal_seen,legal_seen,stable_state,
                       raw_seen,current};
endmodule
