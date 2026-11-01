// Five-Hz triangle LFO. Near/far depth is smoothed independently of touch.
// Output is a signed fractional frequency offset in Q20 (about 30 cents max).
module vibrato_control(
 input wire clk,input wire sample_tick,input wire enable,
 input wire valid,input wire [15:0] distance,
 output wire signed [31:0] modulation
);
 reg [31:0] phase=0;
 reg [15:0] depth=0;
 wire [15:0] target=(!enable||!valid||distance<150||distance>500)?16'd0:
                    (16'd500-distance)*16'd52;
 wire signed [16:0] triangle=phase[31]?
                 17'sd32767-$signed({1'b0,phase[30:15]}):
                 $signed({1'b0,phase[30:15]})-17'sd32768;
 reg signed [33:0] product=0;
 always @(posedge clk) begin
  if(sample_tick) begin
   phase<=phase+32'd407226;
   if(depth<target) depth<=depth+1'b1;
   else if(depth>target) depth<=depth-1'b1;
  end
  product<=triangle*$signed({1'b0,depth});
 end
 assign modulation=product>>>15;
endmodule
