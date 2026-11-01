`timescale 1ns/1ps
module tb_gesture_filter;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,poll=0;reg [7:0] raw=0;
 wire [7:0] gesture;wire event_pulse;
 integer events=0;
 aux_gesture_filter #(.CLOCKS_PER_MS(2)) dut(clk,reset,poll,raw,gesture,event_pulse);
 always @(negedge clk) if(event_pulse) events=events+1;
 task send;input [7:0] value;begin
  @(negedge clk);raw=value;poll=1;@(negedge clk);poll=0;
  repeat(2) @(negedge clk);
 end endtask
 initial begin
  repeat(3) @(negedge clk);reset=0;
  send(1);if(events!=1||gesture!=1) $fatal(1,"first action delayed");
  repeat(20) send(2);
  if(events!=1) $fatal(1,"direction guard missing");
  repeat(60) @(negedge clk);send(2);
  if(events!=2||gesture!=2) $fatal(1,"direction switch blocked beyond60ms");
  repeat(150) send(2);
  if(events!=2) $fatal(1,"persistent sample retriggered");
  send(0);repeat(20) @(negedge clk);send(2);
  if(events!=2) $fatal(1,"short neutral chatter retriggered");
  send(0);repeat(90) @(negedge clk);send(2);
  if(events!=3) $fatal(1,"fresh same-direction gesture lost");
  send(0);repeat(90) @(negedge clk);send(2);
  if(events!=3) $fatal(1,"same-direction180ms refractory missing");
  repeat(400) @(negedge clk);send(2);
  if(events!=3) $fatal(1,"persistent result after short-gap rejection retriggered");
  send(3);send(255);if(events!=3||gesture!=2) $fatal(1,"ambiguous result acted");
  send(4);if(events!=4||gesture!=4) $fatal(1,"new direction not accepted");
  repeat(130) @(negedge clk);send(8);
  if(events!=5||gesture!=8) $fatal(1,"down direction not accepted");
  reset=1;repeat(3) @(negedge clk);reset=0;send(1);
  if(events!=6||gesture!=1) $fatal(1,"retry did not reset history");
  $display("PASS first event,60ms direction guard,180ms repeat guard,40ms quiet rearm, persistent/chatter rejection, ambiguity, up/down and retry");
  $finish;
 end
 initial begin #100000;$fatal(1,"gesture filter timeout");end
endmodule
