`timescale 1ns/1ps
module tb_oled_mode_key;
 reg clk=0;always #5 clk=~clk;
 reg key=1;wire [1:0] mode;
 oled_mode_key #(.DEBOUNCE(10)) dut(clk,key,mode);
 task stable;input level;input integer cycles;begin
  @(negedge clk);key=level;repeat(cycles) @(negedge clk);
 end endtask
 initial begin
  stable(1,20);stable(0,2);stable(1,3);stable(0,2);stable(1,20);
  if(mode!=0) $fatal(1,"bounce counted");
  stable(0,30);if(mode!=1) $fatal(1,"press did not advance");
  stable(0,100);if(mode!=1) $fatal(1,"hold repeated");
  stable(1,30);stable(0,30);if(mode!=2) $fatal(1,"second press");
  stable(1,30);stable(0,30);if(mode!=3) $fatal(1,"third press: spectrum missing");
  stable(1,30);stable(0,30);if(mode!=0) $fatal(1,"wrap");
  $display("PASS mode key bounce rejection, hold, release, 4-mode wrap");$finish;
 end
endmodule
