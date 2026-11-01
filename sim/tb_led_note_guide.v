`timescale 1ns/1ps
module tb_led_note_guide;
 reg clk=0;always #5 clk=~clk;
 reg key=1,online=1;reg [6:0] notes=0;wire [6:0] leds;
 led_note_guide dut(clk,key,online,notes,leds);
 integer i;
 initial begin
  for(i=0;i<128;i=i+1) begin
   notes=i;#10;if(leds!==notes) $fatal(1,"LED gate mapping %d",i);
   key=0;#10;if(leds!==notes) $fatal(1,"C86 must not affect LEDs");
   key=1;
  end
  online=0;#10;if(leds!==0) $fatal(1,"stale LED on link loss");
  online=1;notes=0;#10;if(leds!==0) $fatal(1,"release must clear");
  $display("PASS LED all128 gate combinations, chords, key ignored, release and offline");$finish;
 end
endmodule
