`timescale 1ns/1ps
module tb_dual_control;
 reg clk=0;always #5 clk=~clk;
 reg phone_rx=1,pc_rx=1;
 tri1 touch_scl,touch_sda,adc_scl,adc_sda,aux_scl,aux_sda;
 wire phone_tx,pc_tx;
 board_a_top dut(.clk(clk),.timbre_key(1'b1),.rec_key(1'b1),.play_key(1'b1),
 .stop_key(1'b1),.uart_rx(phone_rx),.uart_tx(phone_tx),
 .pc_uart_rx(pc_rx),.pc_uart_tx(pc_tx),
 .touch_scl(touch_scl),.touch_sda(touch_sda),.adc_scl(adc_scl),.adc_sda(adc_sda),
 .aux_scl(aux_scl),.aux_sda(aux_sda),.encoder_a(1'b1),.encoder_b(1'b1),
 .audio_data_b(1'b1),.audio_data_c(1'b1),.flash_miso(1'b1));
 integer phone_count=0,pc_count=0;
 always @(posedge clk) if(dut.cmd_valid) begin
  if(dut.cmd_source_pc) pc_count=pc_count+1;else phone_count=phone_count+1;
 end
 task phone_byte;input [7:0] b;integer k;
 begin
  @(negedge clk);phone_rx=0;repeat(234) @(negedge clk);
  for(k=0;k<8;k=k+1) begin phone_rx=b[k];repeat(234) @(negedge clk);end
  phone_rx=1;repeat(234) @(negedge clk);
 end endtask
 task pc_byte;input [7:0] b;integer k;
 begin
  @(negedge clk);pc_rx=0;repeat(234) @(negedge clk);
  for(k=0;k<8;k=k+1) begin pc_rx=b[k];repeat(234) @(negedge clk);end
  pc_rx=1;repeat(234) @(negedge clk);
 end endtask
 task phone_cmd;input [7:0] seq,op;input [15:0] arg;input bad;
 begin
  phone_byte(8'h43);phone_byte(8'h4d);phone_byte(seq);phone_byte(op);
  phone_byte(arg[7:0]);phone_byte(arg[15:8]);
  phone_byte((seq+op+arg[7:0]+arg[15:8])^(bad?8'h01:8'h00));phone_byte(13);
  repeat(20) @(negedge clk);
 end endtask
 task pc_cmd;input [7:0] seq,op;input [15:0] arg;
 begin
  pc_byte(8'h43);pc_byte(8'h4d);pc_byte(seq);pc_byte(op);
  pc_byte(arg[7:0]);pc_byte(arg[15:8]);
  pc_byte(seq+op+arg[7:0]+arg[15:8]);pc_byte(13);
  repeat(20) @(negedge clk);
 end endtask
 initial begin
  // Stale Flash restoration and physical touch are isolated in this test.
  force dut.restore_cal=0;force dut.mpr_online=1;force dut.gates=7'h40;
  repeat(30) @(negedge clk);
  fork phone_cmd(8'h11,8'h02,16'h0004,0);pc_cmd(8'h11,8'h01,16'h0002);join
  if(phone_count!=1||pc_count!=1||dut.features!=4||dut.timbre!=2)
   $fatal(1,"simultaneous complete frames lost/corrupted");
  if(dut.cmd_seq!=17||dut.pc_cmd_seq!=17) $fatal(1,"same sequence independent receipts");
  pc_cmd(8'h12,8'h03,16'h0202);
  if(dut.features!=6) $fatal(1,"masked toggle destroyed phone gesture setting");
  fork phone_cmd(8'h22,8'h20,16'h0001,0);pc_cmd(8'h23,8'h20,16'h0004);join
  if(dut.effective_gates!=7'h45) $fatal(1,"phone/PC/copper keys not ORed");
  pc_cmd(8'h24,8'h20,0);
  if(dut.effective_gates!=7'h41) $fatal(1,"PC release killed phone/copper note");
  phone_cmd(8'h25,8'h20,0,0);
  if(dut.effective_gates!=7'h40) $fatal(1,"phone release killed copper");
  fork phone_cmd(8'h33,8'h01,0,1);pc_cmd(8'h34,8'h01,1);join
  if(dut.timbre!=1||dut.cmd_seq!=8'h25||dut.pc_cmd_seq!=8'h34)
   $fatal(1,"invalid phone frame affected PC/receipt");
  // Latest processed absolute command wins for a shared setting.
  phone_cmd(8'h35,8'h01,3,0);
  if(dut.timbre!=3||dut.pc_cmd_seq!=8'h34) $fatal(1,"last writer / independent PC ack");
  // Isolate only the failsafe counter for a short integration timeout test.
  phone_cmd(8'h36,8'h20,1,0);
  force dut.remote_gate_inst.timeout=24'd13499999;
  repeat(3) @(negedge clk);release dut.remote_gate_inst.timeout;
  repeat(3) @(negedge clk);
  if(dut.effective_gates!=7'h40) $fatal(1,"phone timeout killed copper or stuck");
  // Installed two pressure pads must follow bit0 from the real PC protocol.
  force dut.pitch=16'd13200;force dut.pitch_valid=1;
  force dut.pressure_valid=7'b0000011;
  force dut.pressure=112'd0;
  repeat(10) @(negedge clk);
  force dut.pressure=112'd16128;
  repeat(10) @(negedge clk);
  pc_cmd(8'h40,8'h03,16'h0100);
  if(dut.pitch_live!=13200) $fatal(1,"pressure OFF still bends pitch");
  pc_cmd(8'h41,8'h03,16'h0101);
  if(dut.pitch_live!=17200) $fatal(1,"pressure ON did not bend pitch");
  if(dut.gains!={7{16'd256}}) $fatal(1,"obsolete per-key pressure gain active");
  pc_cmd(8'h42,8'h03,16'h0100);
  if(dut.pitch_live!=13200) $fatal(1,"pressure OFF did not restore pitch");
  pc_cmd(8'h43,8'h01,16'd4);
  if(dut.timbre!=4 || dut.settings[242]!=1 || dut.settings[247:246]!=0)
   $fatal(1,"fifth sound command/settings truncated to2bits");
  pc_cmd(8'h44,8'h01,16'd7);
  if(dut.timbre!=4) $fatal(1,"invalid sound accepted");
  force dut.timbre_press=1;@(negedge clk);release dut.timbre_press;
  @(negedge clk);
  if(dut.timbre!=0) $fatal(1,"physical sound button did not wrap violin->sine");
  // Filter events must retain existing direction actions and feature bypass.
  pc_cmd(8'h45,8'h03,16'h0404);
  force dut.gesture=8'h02;force dut.gesture_event=1;
  @(negedge clk);release dut.gesture_event;repeat(2) @(negedge clk);
  if(dut.timbre!=4) $fatal(1,"left gesture did not wrap sine->flute");
  force dut.gesture=8'h01;force dut.gesture_event=1;
  @(negedge clk);release dut.gesture_event;repeat(2) @(negedge clk);
  if(dut.timbre!=0) $fatal(1,"right gesture did not wrap flute->sine");
  force dut.gesture=8'h08;force dut.gesture_event=1;
  @(negedge clk);release dut.gesture_event;repeat(2) @(negedge clk);
  if(dut.features[1]) $fatal(1,"down gesture did not disable vibrato");
  force dut.gesture=8'h04;force dut.gesture_event=1;
  @(negedge clk);release dut.gesture_event;repeat(2) @(negedge clk);
  if(!dut.features[1]) $fatal(1,"up gesture did not enable vibrato");
  pc_cmd(8'h46,8'h03,16'h0400);
  force dut.gesture=8'h01;force dut.gesture_event=1;
  @(negedge clk);release dut.gesture_event;repeat(2) @(negedge clk);
  if(dut.timbre!=0) $fatal(1,"gesture bypass ignored");
  release dut.gesture;
  $display("PASS full A top: dual UART, pressure, fifth flute/settings, five-sound wrap, gesture left/right/up/down and bypass");
  $finish;
 end
 initial begin #10000000;$fatal(1,"dual top timeout");end
endmodule
