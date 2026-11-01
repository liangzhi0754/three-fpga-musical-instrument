`timescale 1ns/1ps
module tb_normal_timbres;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,tick=0;
 reg [6:0] gates=0;
 reg [1:0] timbre=0;
 reg [15:0] pitch=13200;
 reg [111:0] gains={7{16'd256}};
 reg signed [31:0] vibrato=0;
 wire signed [23:0] actual,expected;
`ifdef C_NODE
 node_synth #(3,4,17,1) dut(clk,reset,tick,gates,timbre,pitch,gains,vibrato,actual);
 normal_reference_c #(3,4,17,1) refnode(clk,reset,tick,gates,timbre,pitch,gains,vibrato,expected);
`else
 node_synth #(0,3,1) dut(clk,reset,tick,gates,timbre,pitch,gains,vibrato,actual);
 normal_reference_b #(0,3,1) refnode(clk,reset,tick,gates,timbre,pitch,gains,vibrato,expected);
`endif
 integer t,n,checks=0;
 reg comparing=1;
 always @(negedge clk) begin
  if(comparing && actual!==expected) $fatal(1,"normal timbre changed: mode=%d expected=%d actual=%d",timbre,expected,actual);
  checks=checks+1;
 end
 task sample;
 begin
  repeat(12) @(negedge clk);tick=1;
  @(negedge clk);tick=0;
 end endtask
 initial begin
  repeat(3) @(negedge clk);reset=0;
  for(t=0;t<3;t=t+1) begin
   timbre=t;
   for(n=0;n<1200;n=n+1) begin
    gates=(n<1000)?((n<500)?7'h7F:7'h55):0;
    pitch=(n<600)?13200:18000;
    vibrato=(n<700)?32'sd0:-32'sd28000;
    sample;
   end
  end
  $display("PASS ordinary timbres0/1/2 bit-identical to v19 including chords, release, pitch and modulation");
  $finish;
 end
endmodule
