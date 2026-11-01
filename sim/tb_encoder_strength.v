`timescale 1ns/1ps
module tb_encoder_strength;
 reg clk=0,a=1,b=1;
 reg [8:0] divider=0;
 always #5 clk=~clk;
 always @(posedge clk) divider<=divider+1'b1;
 wire tick=divider==511;
 wire [13:0] depth;wire active,dir;wire signed [31:0] mod;
 rotary_encoder dut(clk,tick,1'b1,a,b,active,dir,depth,mod,);
 integer n,peak=0,m;
 task state; input x,y;
 begin @(negedge clk);a=x;b=y;repeat(2700) @(negedge clk);end endtask
 task turn;
 begin state(1,0);state(0,0);state(0,1);state(1,1);end endtask
 task sample;
 begin @(posedge tick);@(negedge clk);end endtask
 initial begin
  state(1,1);repeat(10) sample;
  turn;
  if(dut.target_depth<8600) $fatal(1,"movement waited for speed window");
  repeat(900) sample;
  if(depth<8600) $fatal(1,"strong vibrato attack too slow");
  repeat(5) turn;
  for(n=0;n<11000;n=n+1) begin
   sample;m=mod<0?-mod:mod;if(m>peak) peak=m;
   if(m>30000) $fatal(1,"modulation exceeded bounded range");
  end
  if(peak<26000 || depth!=15000) $fatal(1,"fast rotation failed to reach strong depth: peak=%d depth=%d",peak,depth);
  repeat(18000) sample;
  if(active || depth!=0 || mod!=0) $fatal(1,"stop did not return to neutral");
  $display("PASS immediate motion target, full slow depth within 18ms, fast depth15000 / modulation about30000, smooth stop");
  $finish;
 end
 initial begin #200000000;$fatal(1,"strength timeout");end
endmodule
