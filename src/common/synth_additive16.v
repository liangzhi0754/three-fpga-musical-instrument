// Cello-inspired harmonic bank: B harmonics 1..16; C harmonics 17..32.
// Formant-like weighting and brighter transient / darker sustain; no PCM.
// Wide unscaled partial sum. Final division by two is done once on Board A.
module synth_additive16 #(
 parameter integer START_HARMONIC=1
)(
 input wire clk,input wire reset,input wire sample_tick,
 input wire gate,input wire [31:0] phase_step,
 output wire signed [23:0] sample
);
 wire [383:0] terms;
 genvar k;
 generate for(k=0;k<16;k=k+1) begin: component
  localparam integer H=START_HARMONIC+k;
  localparam integer SHIFT=(H<=2)?2:(H==3)?3:(H<=5)?4:
                           (H<=8)?5:(H<=10)?6:(H<=12)?7:(H<=16)?8:(H<=24)?9:10;
  // A non-linear phase pattern keeps the spectrum but changes the waveform
  // away from the all-in-phase saw-like crest. Each partial keeps its phase.
  localparam [31:0] INITIAL_PHASE=((H*H+3*H)%16)*32'h04000000;
  localparam [15:0] ATTACK=(H<=4)?16'd64:(H<=12)?16'd96:16'd128;
  localparam [15:0] SUSTAIN=(H<=4)?16'd45056:(H<=12)?16'd28672:16'd16384;
  localparam [15:0] DECAY=(H<=4)?16'd2:(H<=12)?16'd4:16'd8;
  localparam [15:0] RELEASE=(H<=4)?16'd6:(H<=12)?16'd8:16'd12;
  wire [31:0] step=phase_step*H;
  wire signed [15:0] raw;
  additive_component #(.INITIAL_PHASE(INITIAL_PHASE),.ATTACK_STEP(ATTACK),
      .SUSTAIN_LEVEL(SUSTAIN),.DECAY_STEP(DECAY),.RELEASE_STEP(RELEASE))
      osc(clk,reset,sample_tick,gate,step,raw);
  assign terms[k*24+:24]=$signed({{8{raw[15]}},raw}) >>> SHIFT;
 end endgenerate
 integer j;
 reg signed [23:0] sum;
 always @* begin
  sum=0;
  for(j=0;j<16;j=j+1) sum=sum+$signed(terms[j*24+:24]);
 end
 assign sample=sum;
endmodule
