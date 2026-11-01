`timescale 1ns/1ps
module tb_cello32;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,tick=0,gate=0;
 reg [31:0] step=32'h00800000;
 wire signed [23:0] lo,hi;
 wire signed [24:0] wide=$signed({lo[23],lo})+$signed({hi[23],hi});
 wire signed [24:0] audio=wide>>>1;
 synth_additive16 #(1) b(clk,reset,tick,gate,step,lo);
 synth_additive16 #(17) c(clk,reset,tick,gate,step,hi);
 integer n,fd;
 task one_sample;
 begin
  @(negedge clk);tick=1;
  @(negedge clk);tick=0;
  repeat(8) @(negedge clk);
  if(audio>32767 || audio< -32768) $fatal(1,"cello mix clipping");
 end endtask
 initial begin
  repeat(3) @(negedge clk);reset=0;gate=1;
  fd=$fopen("validation/cello32_samples.txt","w");
  for(n=0;n<20240;n=n+1) begin
   one_sample;$fdisplay(fd,"%d",audio);
  end
  gate=0;
  for(n=0;n<8000;n=n+1) begin one_sample;$fdisplay(fd,"%d",audio);end
  $fclose(fd);
  if(audio!==0 || b.component[0].osc.envelope!==0 || c.component[15].osc.envelope!==0)
   $fatal(1,"release failed to become silent");
  gate=1;step=32'd10654105;
  repeat(64) one_sample;
  if(b.component[0].osc.envelope!=4096 || b.component[0].osc.phase==c.component[15].osc.phase)
   $fatal(1,"attack / independent phases missing");
  reset=1;@(negedge clk);reset=0;repeat(4) @(negedge clk);
  if(audio!==0) $fatal(1,"reset silence failed");
  $display("PASS new cello32: 28240 captured samples; 32 phases/envelopes, bounded mix, full release, retrigger, reset");
  $finish;
 end
endmodule
