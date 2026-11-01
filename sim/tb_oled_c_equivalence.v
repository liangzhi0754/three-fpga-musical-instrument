`timescale 1ns/1ps
module tb_oled_c_equivalence;
 reg clk=0;always #5 clk=~clk;
 reg [8:0] phase=0;
 reg frame_toggle=0;
 reg [15:0] frame=0;
 reg start=0;
 reg [1:0] timbre=0;
 wire [511:0] packet;
 wire sck,mosi,cs,busy,txdone;
 wire old_audio,new_audio;
 wire [5:0] old_led,new_led;
 wire old_uart,new_uart;
 tri1 scl,sda;
 reg slave_low=0,selected=0;
 integer busbits=0;
 assign sda=slave_low?1'b0:1'bz;
 always @(negedge sda) if(scl===1'b1) begin selected=1;busbits=0;end
 always @(posedge sda) if(scl===1'b1) begin selected=0;slave_low=0;end
 always @(posedge scl) if(selected) begin
  if(busbits==8) busbits=0;else busbits=busbits+1;
 end
 always @(negedge scl) if(selected) slave_low=(busbits==8);
 reg signed [15:0] monitor=0;
 reg monitor_din=0;
 wire [5:0] bi=phase[8:3];
 control_pack pack(8'd1,frame+16'd32,frame,8'h80,7'h7F,timbre,
  16'd13200,16'd26400,{7{16'd256}},32'd0,16'd0,8'd0,packet);
 ctrl_packet_tx tx(clk,start,packet,sck,mosi,cs,busy,txdone);
 // Fast audio-return polling, exercising C's original serial output.
 wire ret_cs=!(phase>=80 && phase<480);
 wire ret_sck=ret_cs?1'b0:phase[2];
 board_c_baseline old(clk,sck,mosi,cs,frame_toggle,ret_sck,ret_cs,old_audio,old_led,old_uart);
 board_c_top dut(clk,sck,mosi,cs,frame_toggle,ret_sck,ret_cs,new_audio,new_led,new_uart,
  phase[2],bi[5],monitor_din,scl,sda,1'b1,1'b1,);
 wire [6:0] expected_display=7'h7F;
 integer display_checks=0;
 integer comparisons=0,nonzero=0,packets=0,oled_edges=0;
 always @(posedge scl) oled_edges=oled_edges+1;
 always @(posedge clk) begin
  phase<=phase+1'b1;
  start<=0;
  if(phase==511) begin frame_toggle<=!frame_toggle;frame<=frame+1'b1;end
  if(phase==8 && (frame==0 || frame==45 || frame==90)) begin
   timbre<=frame==0?0:frame==45?1:3;
  end
  if(phase==16 && (frame==0 || frame==45 || frame==90)) start<=1;
  if(phase==0) monitor<=monitor+16'd523;
  if(phase[2:0]==7) begin
   if(bi<16) monitor_din<=monitor[15-bi];
   else if(bi>=32 && bi<48) monitor_din<=monitor[47-bi];
   else monitor_din<=0;
  end
 end
 always @(negedge clk) if($time>100) begin
  comparisons=comparisons+1;
  if({new_audio,new_led,new_uart}!=={old_audio,old_led,old_uart})
   $fatal(1,"C old/new external behavior differs at frame=%d phase=%d",frame,phase);
  if(dut.node.partial_sum!==old.node.partial_sum) $fatal(1,"C synth sample differs");
  if(dut.node.partial_sum!=0) nonzero=nonzero+1;
  if(dut.packet_valid) packets=packets+1;
  if(dut.node.locked) begin
   if(dut.display_notes!==expected_display) $fatal(1,"note mask must follow CRC-validated active packet / additive lowest note");
   display_checks=display_checks+1;
  end
 end
 initial begin
  // Exercise OLED concurrently without waiting the real 100ms boot delay.
  force dut.screen.delay_count=22'd2699999;
  // Accelerate visualization acquisition only: the audio node and all of its
  // serial timing remain real. This exercises XY drawing during synthesis.
  force dut.monitor_valid=1;
  force dut.mode=1;
  force dut.visual.trigger_timer=20'd540000;
  repeat(2) @(negedge clk);release dut.screen.delay_count;
  release dut.visual.trigger_timer;
  wait(frame==140);
  if(nonzero<1000 || packets!=3 || oled_edges<100 || display_checks<1000) $fatal(1,"test did not exercise synthesis/link/OLED");
  $display("PASS C audio with/without OLED: %d cycle comparisons, %d nonzero samples, 3 real CRC packets, sine/saw/new-cello, concurrent OLED",comparisons,nonzero);
  $finish;
 end
 initial begin #10000000;$fatal(1,"C equivalence timeout");end
endmodule
