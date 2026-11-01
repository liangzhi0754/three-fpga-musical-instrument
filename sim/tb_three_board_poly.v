`timescale 1ns/1ps
module tb_three_board_poly;
 reg clk=0;always #5 clk=~clk;
 tri1 ts,td,ascl,asd,gs,gd,os,od;
 wire sck,mosi,cs,ft,rclk,rcs,rb,rc,bclk,lrck,din;
 wire [6:0] note_led;
 wire signed [15:0] monitored;
 integer frames=0,nonzero=0,both_valid=0,clipped=0;
 board_a_top a(.clk(clk),.timbre_key(1'b1),.rec_key(1'b1),.play_key(1'b1),
  .stop_key(1'b1),.uart_rx(1'b1),.pc_uart_rx(1'b1),.encoder_a(1'b1),.encoder_b(1'b1),
  .touch_scl(ts),.touch_sda(td),.adc_scl(ascl),.adc_sda(asd),.aux_scl(gs),.aux_sda(gd),
  .ctrl_sck(sck),.ctrl_mosi(mosi),.ctrl_cs_n(cs),.frame_toggle(ft),.audio_sck(rclk),
  .audio_cs_n(rcs),.audio_data_b(rb),.audio_data_c(rc),.i2s_bclk(bclk),
  .i2s_lrck(lrck),.i2s_din(din),.flash_miso(1'b1));
 board_b_top b(.clk(clk),.ctrl_sck(sck),.ctrl_mosi(mosi),.ctrl_cs_n(cs),
  .frame_toggle(ft),.audio_sck(rclk),.audio_cs_n(rcs),.audio_data(rb));
 board_c_top c(.clk(clk),.ctrl_sck(sck),.ctrl_mosi(mosi),.ctrl_cs_n(cs),
  .frame_toggle(ft),.audio_sck(rclk),.audio_cs_n(rcs),.audio_data(rc),
  .monitor_bclk(bclk),.monitor_lrck(lrck),.monitor_din(din),
  .oled_scl(os),.oled_sda(od),.display_key(1'b1),.guide_key(1'b1),.note_led(note_led));
 always @(negedge clk) begin
  if(c.monitor_valid) begin
   frames=frames+1;
   if(c.monitor_sample!==a.frame_sample) $fatal(1,"final I2S monitor mismatch");
   if(c.monitor_sample!=0) nonzero=nonzero+1;
   if(c.monitor_sample==32767 || c.monitor_sample== -32768) clipped=clipped+1;
  end
  if(a.link_done && a.b_ok && a.c_ok) both_valid=both_valid+1;
 end
 initial begin
  force a.pitch=16'd13200;force a.pitch_valid=1;
  force a.volume=16'd26400;force a.volume_valid=1;
  force a.mpr_online=1;force a.gates=7'b0010101;
  force a.restore_cal=0;force a.features=3'b000;force a.timbre=3'd3;
  wait(frames>=320);
  if(nonzero<200 || both_valid<250 || clipped!=0) $fatal(1,"three-board cello path not healthy: %d %d %d",nonzero,both_valid,clipped);
  if(a.active_timbre!=3 || c.node.engine.strings.note_step[0]!=10654105 || b.node.engine.strings.note_step[0]!=10654105)
   $fatal(1,"cello octave failed across both boards");
  if(c.display_notes!=7'h15) $fatal(1,"cello note display wrong");
  if(note_led!=7'h15) $fatal(1,"validated note command did not reach external LED");
  force a.timbre=3'd4;
  wait(a.active_timbre==4&&c.node.active[426:424]==4);
  wait(frames>=450);
  if(c.node.engine.strings.note_step[2]!=26846653 || c.node.engine.strings.note_step[4]!=31926153)
   $fatal(1,"flute chord pitch/3bit transport failed");
  if(c.node.engine.strings.lane[0].pipe.states[0][47:32]==0 ||
     c.node.engine.strings.lane[0].pipe.states[8][47:32]==0 ||
     c.node.engine.strings.lane[0].pipe.states[16][47:32]==0)
   $fatal(1,"chord lost one independent envelope");
  $display("PASS three-board poly cello/flute chord: A control, B harmonics1..16 + C17..32, both validated returns, A mix/volume/I2S, OLED monitor; frames=%d nonzero=%d valid=%d",frames,nonzero,both_valid);
  $finish;
 end
 initial begin #5000000;$fatal(1,"three-board cello timeout");end
endmodule
