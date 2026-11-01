// Read-only monitor of A's 16-bit Philips I2S, in 32-bit stereo slots.
// All three external signals are sampled through equal-length synchronizers.
module oled_i2s_rx #(parameter integer TIMEOUT=900000)(
 input wire clk, input wire bclk, input wire lrck, input wire din,
 output reg signed [15:0] sample=0, output reg sample_valid=0,
 output reg online=0
);
 reg [2:0] bs=0,ws=0,ds=0;
 reg previous_ws=0,aligned=0;
 reg [5:0] count=0;
 reg [15:0] shift=0;
 reg [19:0] silence=0;
 always @(posedge clk) begin
  bs<={bs[1:0],bclk};ws<={ws[1:0],lrck};ds<={ds[1:0],din};
  sample_valid<=0;
  if(silence<TIMEOUT) silence<=silence+1'b1;
  else if(silence==TIMEOUT) begin
   online<=0;aligned<=0;sample<=0;silence<=TIMEOUT+1;
  end
  if(bs[2:1]==2'b01) begin
   if(ws[2]!=previous_ws) begin
    previous_ws<=ws[2];count<=0;shift<=0;aligned<=1;
    // The WS-changing bit belongs to the previous slot (I2S one-bit delay).
   end else if(aligned && count<16) begin
    shift<={shift[14:0],ds[2]};count<=count+1'b1;
    if(count==15 && !ws[2]) begin
     sample<={shift[14:0],ds[2]};sample_valid<=1;online<=1;silence<=0;
    end
   end
  end
 end
endmodule
