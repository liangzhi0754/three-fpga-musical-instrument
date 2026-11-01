// Never consume an invalid payload. Brief gaps hold the last validated sample;
// persistent loss fades down, and recovery ramps gain over ~1.2ms.
module audio_continuity(
 input wire clk,input wire frame_done,input wire valid,
 input wire signed [23:0] sample_in,
 output reg signed [23:0] sample_out=0
);
 reg signed [23:0] last_sample=0;
 reg [8:0] gain=0;
 reg [3:0] missing=15;
 reg signed [23:0] selected=0;
 reg [8:0] next_gain=0;
 reg signed [33:0] scaled=0;
 always @* begin
  selected=valid?sample_in:last_sample;
  next_gain=gain;
  if(valid) next_gain=gain>=252?9'd256:gain+9'd4;
  else if(missing>=2) next_gain=gain<=4?9'd0:gain-9'd4;
  scaled=selected*$signed({1'b0,next_gain});
 end
 always @(posedge clk) begin
  if(frame_done) begin
   gain<=next_gain;
   if(valid) begin last_sample<=sample_in;missing<=0;end
   else if(missing!=15) missing<=missing+1'b1;
   sample_out<=scaled>>>8;
  end
 end
endmodule
