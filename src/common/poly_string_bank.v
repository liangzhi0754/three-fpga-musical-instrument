// Four parallel pipelines, each time-sharing 28 independent partial states.
// B computes harmonics1..16 for7 notes; C17..32. 224 partials across B/C.
// At27MHz the bank commits all112 partials in <40 clocks, before A frame+80.
module poly_string_bank #(parameter integer FIRST_HARMONIC=1)(
 input wire clk,input wire reset,input wire sample_tick,
 input wire [6:0] gates,input wire [2:0] timbre,
 input wire [223:0] steps,input wire [111:0] gains,
 output reg signed [23:0] sample=0
);
 reg run=0,issue=0;
 reg [4:0] row=0;
 reg [6:0] held_gates=0;
 reg [2:0] held_timbre=3;
 reg [223:0] held_steps=0;
 reg [111:0] held_gains=0;
 reg [8:0] note_gain[0:6];
 reg [31:0] note_step[0:6];
 wire [95:0] sums;
 wire [3:0] done;
 integer k;
 initial for(k=0;k<7;k=k+1) begin note_gain[k]=256;note_step[k]=0;end
 genvar l;
 generate for(l=0;l<4;l=l+1) begin: lane
  poly_string_lane #(FIRST_HARMONIC+l*4) pipe(clk,reset,sample_tick,
   issue,row,held_gates,held_timbre,held_steps,held_gains,
   sums[l*24+:24],done[l]);
 end endgenerate
 wire signed [25:0] total=$signed({{2{sums[23]}},sums[23:0]})+
                          $signed({{2{sums[47]}},sums[47:24]})+
                          $signed({{2{sums[71]}},sums[71:48]})+
                          $signed({{2{sums[95]}},sums[95:72]});
 always @(posedge clk) begin
  if(reset) begin run<=0;issue<=0;row<=0;sample<=0;end
  else begin
   if(sample_tick) begin
    run<=1;issue<=1;row<=0;held_gates<=timbre>=3?gates:7'd0;
    held_timbre<=timbre;
    for(k=0;k<7;k=k+1) begin
     if(gates[k]&&timbre>=3) begin
      note_gain[k]<=gains[k*16+:9];
      note_step[k]<=timbre==3?(steps[k*32+:32]>>1):steps[k*32+:32];
     end
     held_gains[k*16+:16]<={7'd0,(gates[k]&&timbre>=3)?gains[k*16+:9]:note_gain[k]};
     held_steps[k*32+:32]<=(gates[k]&&timbre>=3)?
       (timbre==3?(steps[k*32+:32]>>1):steps[k*32+:32]):note_step[k];
    end
   end else if(issue) begin
    if(row==27) issue<=0;else row<=row+1'b1;
   end
   if(&done) begin
    // Fixed headroom for7 simultaneous keys; independent of pressed key count.
    sample<=total>>>2;run<=0;
   end
  end
 end
endmodule

module poly_string_lane #(parameter integer BASE_HARMONIC=1)(
 input wire clk,input wire reset,input wire start,
 input wire issue,input wire [4:0] row,
 input wire [6:0] gates,input wire [2:0] timbre,
 input wire [223:0] steps,input wire [111:0] gains,
 output reg signed [23:0] sum=0,output reg done=0
);
 // Packed RAM: phase[31:0], envelope[47:32], state[49:48], previous_gate[50].
 reg [50:0] states[0:31];
 reg [50:0] q=0;
 reg valid1=0,valid2=0,valid3=0,valid4=0,valid5=0;
 reg [4:0] addr1=0;
 reg last2=0,last3=0,last4=0,last5=0;
 reg [31:0] wave_phase=0;
 reg [7:0] env2=0;
 reg flute_fundamental2=0;
 reg [8:0] gain2=256,gain3=256;
 reg [3:0] shift2=0,shift3=0;
 wire signed [15:0] wave;
 reg signed [24:0] product3=0;
 reg signed [15:0] weighted4=0;
 reg [8:0] gain4=256;
 reg signed [25:0] product5=0;
 reg signed [23:0] accumulator=0;
 integer i;
 initial for(i=0;i<32;i=i+1) states[i]=0;
 synth_waveform lut(wave_phase,2'd0,wave);
 wire [2:0] key_index=addr1[4:2];
 wire [5:0] h=BASE_HARMONIC+addr1[1:0];
 wire gate_now=gates[key_index];
 wire [15:0] envelope=q[47:32];
 wire [1:0] env_state=q[49:48];
 wire previous=q[50];
 wire flute=timbre==4;
 // Soft breath onset, fundamental-led spectrum and a gentle release.
 wire [15:0] attack=flute?(h<=3?16'd128:16'd80):
                                    (h<=4?16'd64:h<=12?16'd96:16'd128);
 wire [15:0] sustain=flute?(h<=3?16'd57344:h<=10?16'd40960:16'd24576):
                                     (h<=4?16'd45056:h<=12?16'd28672:16'd16384);
 wire [15:0] decay=flute?(h<=3?16'd3:16'd5):(h<=4?16'd2:h<=12?16'd4:16'd8);
 wire [15:0] release_step=flute?(h<=3?16'd10:16'd14):(h<=4?16'd6:h<=12?16'd8:16'd12);
 // Quiet filtered breath on the fundamental only. Shift/add logic; no new DSP.
 wire signed [15:0] voiced_wave;
 generate if(BASE_HARMONIC==1) begin: breath
  reg [15:0] lfsr=16'hace1;
  reg signed [19:0] smooth=0;
  wire signed [19:0] noise={{4{lfsr[15]}},lfsr};
  always @(posedge clk) begin
   if(reset) begin lfsr<=16'hace1;smooth<=0;end
   else if(start) begin
    lfsr<={lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
    smooth<=smooth+((noise-smooth)>>>4);
   end
  end
  // Reserve headroom before adding air so the signed sine cannot wrap.
  assign voiced_wave=flute_fundamental2?
    ($signed(wave)-($signed(wave)>>>4)+(smooth>>>4)):wave;
 end else begin: no_breath
  assign voiced_wave=wave;
 end endgenerate
 reg [15:0] env_next;
 reg [1:0] state_next;
 reg [3:0] amplitude_shift;
 wire [31:0] base_step=steps[key_index*32+:32];
 reg [31:0] harmonic_step;
 // Four constant multipliers become shifts/adds, not variable32x32 DSPs.
 always @* begin
  case(addr1[1:0])
   0:harmonic_step=base_step*BASE_HARMONIC;
   1:harmonic_step=base_step*(BASE_HARMONIC+1);
   2:harmonic_step=base_step*(BASE_HARMONIC+2);
   default:harmonic_step=base_step*(BASE_HARMONIC+3);
  endcase
  env_next=envelope;state_next=env_state;
  if(!gate_now) begin
   if(envelope<=release_step) begin env_next=0;state_next=0;end
   else begin env_next=envelope-release_step;state_next=3;end
  end else if(!previous||env_state==0||env_state==3) begin
   env_next=envelope>65535-attack?16'hffff:envelope+attack;state_next=1;
  end else if(env_state==1) begin
   if(envelope>=65535-attack) begin env_next=65535;state_next=2;end
   else env_next=envelope+attack;
  end else begin
   env_next=envelope<=sustain+decay?sustain:envelope-decay;state_next=2;
  end
  if(flute) amplitude_shift=h==1?1:h==2?4:h==3?5:h==4?7:h<=6?8:h<=10?10:h<=16?11:h<=24?12:13;
  else amplitude_shift=h<=2?2:h==3?3:h<=5?4:h<=8?5:h<=10?6:h<=12?7:h<=16?8:h<=24?9:10;
 end
 always @(posedge clk) begin
  done<=0;
  if(reset) begin
   valid1<=0;valid2<=0;valid3<=0;valid4<=0;valid5<=0;
   sum<=0;accumulator<=0;
   for(i=0;i<32;i=i+1) states[i]<=0;
  end else begin
   valid1<=issue;valid2<=valid1;valid3<=valid2;valid4<=valid3;valid5<=valid4;
   if(start) accumulator<=0;
   if(issue) begin q<=states[row];addr1<=row;end
   if(valid1) begin
    states[addr1]<={gate_now,state_next,env_next,q[31:0]+harmonic_step};
    wave_phase<=q[31:0];env2<=env_next[15:8];gain2<=gains[key_index*16+:9];
    flute_fundamental2<=flute && h==1;
    // Strongly attenuate harmonics above Nyquist.
    shift2<=harmonic_step[31]?4'd15:amplitude_shift;
    last2<=addr1==27;
   end
   if(valid2) begin
    product3<=voiced_wave*$signed({1'b0,env2});gain3<=gain2;shift3<=shift2;last3<=last2;
   end
   if(valid3) begin
    weighted4<=($signed(product3)>>>8)>>>shift3;gain4<=gain3;last4<=last3;
   end
   if(valid4) begin product5<=weighted4*$signed({1'b0,gain4});last5<=last4;end
   if(valid5) begin
    accumulator<=accumulator+($signed(product5)>>>8);
    if(last5) begin sum<=accumulator+($signed(product5)>>>8);done<=1;end
   end
  end
 end
endmodule
