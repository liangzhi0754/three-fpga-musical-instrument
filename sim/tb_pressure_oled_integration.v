`timescale 1ns/1ps
module tb_pressure_oled_integration;
 reg clk=0;always #5 clk=~clk;
 tri1 touch_scl,touch_sda,adc_scl,adc_sda,aux_scl,aux_sda,oled_scl,oled_sda;
 wire ctrl_sck,ctrl_mosi,ctrl_cs_n,frame_toggle,audio_sck,audio_cs_n,audio_c;
 wire bclk,lrck,din;
 reg [111:0] pressure=0;
 integer monitored=0,nonzero=0,valid_returns=0;
 board_a_top a(.clk(clk),.timbre_key(1'b1),.rec_key(1'b1),.play_key(1'b1),
  .stop_key(1'b1),.uart_rx(1'b1),.pc_uart_rx(1'b1),.encoder_a(1'b1),.encoder_b(1'b1),
  .touch_scl(touch_scl),.touch_sda(touch_sda),.adc_scl(adc_scl),.adc_sda(adc_sda),
  .aux_scl(aux_scl),.aux_sda(aux_sda),.ctrl_sck(ctrl_sck),.ctrl_mosi(ctrl_mosi),
  .ctrl_cs_n(ctrl_cs_n),.frame_toggle(frame_toggle),.audio_sck(audio_sck),
  .audio_cs_n(audio_cs_n),.audio_data_b(1'b1),.audio_data_c(audio_c),
  .i2s_bclk(bclk),.i2s_lrck(lrck),.i2s_din(din),.flash_miso(1'b1));
 board_c_top c(.clk(clk),.ctrl_sck(ctrl_sck),.ctrl_mosi(ctrl_mosi),.ctrl_cs_n(ctrl_cs_n),
  .frame_toggle(frame_toggle),.audio_sck(audio_sck),.audio_cs_n(audio_cs_n),
  .audio_data(audio_c),.monitor_bclk(bclk),.monitor_lrck(lrck),.monitor_din(din),
  .oled_scl(oled_scl),.oled_sda(oled_sda),.display_key(1'b1),.guide_key(1'b1));
 always @(negedge clk) begin
  if(c.monitor_valid) begin
   monitored=monitored+1;
   if(c.monitor_sample!==a.frame_sample) $fatal(1,"OLED input differs from A final audio");
   if(c.monitor_sample!=0) nonzero=nonzero+1;
  end
  if(a.link_done && a.c_ok) valid_returns=valid_returns+1;
 end
 task expect_remote_pitch;
  input [15:0] expected;
  integer remaining;
  begin
   remaining=40000;
   while(c.node.active[415:400]!==expected && remaining>0) begin
    @(negedge clk);remaining=remaining-1;
   end
   if(remaining==0) $fatal(1,"pressure pitch failed to reach OLED C: expected %d got %d",expected,c.node.active[415:400]);
  end
 endtask
 initial begin
  // Isolate sensor values only; retain actual A scheduler, wire protocol,
  // C synthesis/return, A final mix/I2S, and C OLED receiver.
  pressure[15:0]=1000;pressure[31:16]=1000;
  force a.pressure=pressure;force a.pressure_valid=7'b0000011;
  force a.pitch=16'd13200;force a.pitch_valid=1;
  force a.volume=16'd26400;force a.volume_valid=1;
  force a.mpr_online=1;force a.gates=7'b0001000;
  force a.restore_cal=0;
  force a.features=3'b001;
  repeat(20) @(negedge clk);
  expect_remote_pitch(13200);
  pressure[15:0]=17128;
  expect_remote_pitch(17200);
  pressure[15:0]=1000;pressure[31:16]=17128;
  expect_remote_pitch(9200);
  pressure[31:16]=1000;
  expect_remote_pitch(13200);
  repeat(2048) @(negedge clk);
  if(monitored<80 || nonzero<10 || valid_returns<50 || !c.monitor_online)
   $fatal(1,"integration did not exercise audio path: %d %d %d",monitored,nonzero,valid_returns);
  $display("PASS pressure A -> live protocol -> OLED C synth -> A final I2S -> OLED C monitor: up/down/release, %d samples, %d nonzero, %d valid C returns",monitored,nonzero,valid_returns);
  $finish;
 end
 initial begin #3000000;$fatal(1,"pressure/OLED integration timeout");end
endmodule
