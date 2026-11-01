`timescale 1ns/1ps
module tb_oled_capture;
 reg clk=0;always #5 clk=~clk;
 reg signed [15:0] sample=0;
 reg valid=0,online=1,done=0;
 reg [6:0] x=0;
 wire [5:0] y;wire ready,was_online;
 oled_wave_capture #(.TRIGGER_TIMEOUT(16)) dut(clk,sample,valid,online,done,x,y,ready,was_online);
 task send;input [15:0] v;begin
  @(negedge clk);sample=v;valid=1;
  @(negedge clk);valid=0;
 end endtask
 integer i;
 initial begin
  repeat(20) @(negedge clk);
  send(0); // timeout starts trace even without a rising zero crossing
  for(i=0;i<256;i=i+1) send(16'h2000);
  wait(ready);
  for(i=0;i<128;i=i+1) begin x=i;#1;if(y!==28) $fatal(1,"sample scale %d",y);end
  for(i=0;i<10;i=i+1) send(16'hC000);
  if(y!==28) $fatal(1,"trace changed during display");
  @(negedge clk);done=1;@(negedge clk);done=0;
  online=0;wait(ready);
  for(i=0;i<128;i=i+1) begin x=i;#1;if(y!==36) $fatal(1,"offline centre %d",y);end
  if(was_online) $fatal(1,"offline status");
  $display("PASS waveform actual sample scale, snapshot freeze, no-clock fallback centre");$finish;
 end
 initial begin #2000000;$fatal(1,"capture timeout");end
endmodule
