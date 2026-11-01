`timescale 1ns/1ps
module tb_poly_strings;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,tick=0;
 reg [6:0] gates=0;reg [2:0] mode=3;
 reg [223:0] steps=0;reg [111:0] gains={7{16'd256}};
 wire signed [23:0] b,c;
 poly_string_bank #(1) dut_b(clk,reset,tick,gates,mode,steps,gains,b);
 poly_string_bank #(17) dut_c(clk,reset,tick,gates,mode,steps,gains,c);
 integer n,k,m,latency,f;
 integer reference[0:511];integer actual,error,difference,max_error=0;
 task sample;begin
  @(negedge clk);tick=1;@(negedge clk);tick=0;
  latency=0;
  while(dut_b.run||dut_c.run) begin
   @(negedge clk);latency=latency+1;
   if(latency>40) $fatal(1,"string bank missed return deadline");
  end
  repeat(4) @(negedge clk);
 end endtask
 task restart;begin
  reset=1;repeat(3) @(negedge clk);reset=0;
 end endtask
 initial begin
  steps[31:0]=21308210;steps[63:32]=23917636;steps[95:64]=26846653;
  steps[127:96]=28442981;steps[159:128]=31926153;
  steps[191:160]=35835935;steps[223:192]=40224452;
  for(m=3;m<=4;m=m+1) begin
   mode=m;
   for(n=0;n<512;n=n+1) reference[n]=0;
   // Separate note renders are an independent superposition reference.
   for(k=0;k<7;k=k+1) begin
    restart;gates=1<<k;
    for(n=0;n<512;n=n+1) begin
     if(n==400) gates=0;
     sample;reference[n]=reference[n]+$signed(b)+$signed(c);
    end
   end
   restart;gates=127;
   for(n=0;n<512;n=n+1) begin
    if(n==400) gates=0;
    sample;actual=$signed(b)+$signed(c);
    difference=actual-reference[n];error=difference<0?-difference:difference;
    if(error>max_error) max_error=error;
    if(error>14) $fatal(1,"seven-note superposition mismatch mode=%d n=%d error=%d",mode,n,error);
   end
  end
  // Produce real HDL output for numerical spectrum/tone comparison.
  for(m=3;m<=4;m=m+1) begin
   mode=m;restart;gates=7'h15;
   if(m==3) f=$fopen("validation/cello_chord.txt","w");
   else f=$fopen("validation/flute_chord.txt","w");
   for(n=0;n<4096;n=n+1) begin sample;$fdisplay(f,"%d",($signed(b)+$signed(c))>>>1);end
   $fclose(f);
   gates=0;
   actual=dut_b.lane[0].pipe.states[0][47:32];
   for(n=0;n<512;n=n+1) sample;
   if(dut_b.lane[0].pipe.states[0][47:32]>=actual)
    $fatal(1,"release envelope did not decay");
   restart;sample;
   if(b!=0||c!=0) $fatal(1,"reset left audible output");
  end
  // Release pitch for a still-decaying note must survive another key press.
  mode=3;restart;gates=1;repeat(500) sample;
  gates=2;repeat(50) sample;
  if(dut_b.note_step[0]!=10654105 || dut_b.note_step[1]!=11958818)
   $fatal(1,"per-note release pitch was replaced by new key");
  $display("PASS seven-note32-partial superposition cello/flute, ADSR release, held release pitch, two-bank deadline<40clocks; max rounding error=%d",max_error);
  $finish;
 end
 initial begin #100000000;$fatal(1,"poly strings timeout");end
endmodule
