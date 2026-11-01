module board_a_top(
 input wire clk,input wire timbre_key,input wire rec_key,input wire play_key,
 input wire stop_key,input wire uart_rx,output wire uart_tx,output wire led,
 input wire pc_uart_rx,output wire pc_uart_tx,
 inout wire touch_scl,inout wire touch_sda,inout wire adc_scl,inout wire adc_sda,
 inout wire aux_scl,inout wire aux_sda,
 input wire encoder_a,input wire encoder_b,
 output wire ctrl_sck,output wire ctrl_mosi,output wire ctrl_cs_n,
 output reg frame_toggle=0,output wire audio_sck,output wire audio_cs_n,
 input wire audio_data_b,input wire audio_data_c,
 output wire i2s_bclk,output wire i2s_lrck,output reg i2s_din=0,
 output wire flash_sck,output wire flash_mosi,output wire flash_cs_n,
 input wire flash_miso,output wire onboard_pa_enable
);
 assign onboard_pa_enable=0;
 reg [8:0] phase=0;
 reg [15:0] frame=0;
 reg [31:0] sample_time=0;
 wire sample_tick=phase==511;
 always @(posedge clk) begin
  phase<=phase+1'b1;
  if(sample_tick) begin frame<=frame+1'b1;frame_toggle<=~frame_toggle;sample_time<=sample_time+1'b1;end
 end
 wire [6:0] gates;
 wire mpr_online;
 touch_controller touch(clk,touch_scl,touch_sda,gates,mpr_online);
 wire [15:0] pitch,volume;
 wire [111:0] pressure;
 wire [2:0] adc_online;
 wire pitch_valid,volume_valid;
 wire [6:0] pressure_valid;
 adc_scanner adc(clk,adc_scl,adc_sda,pitch,volume,pressure,adc_online,
                  pitch_valid,volume_valid,pressure_valid);
 wire [15:0] distance;
 wire distance_valid,gesture_event;
 wire [7:0] gesture;
 wire [1:0] aux_online;
 wire aux_retry;
 wire [111:0] aux_diagnostic;
 wire [159:0] probe_diagnostic;
 aux_sensors aux(clk,aux_scl,aux_sda,distance,distance_valid,gesture,gesture_event,
   aux_online,aux_retry,aux_diagnostic,probe_diagnostic);
 wire cmd_valid;
 wire [7:0] command,cmd_seq,pc_cmd_seq;
 wire cmd_source_pc;
 wire [15:0] argument;
 dual_host_commands host(clk,uart_rx,pc_uart_rx,cmd_valid,command,argument,
                         cmd_source_pc,cmd_seq,pc_cmd_seq);
 wire [15:0] pitch_base = pitch_valid ? pitch : 16'd13200;
 wire [15:0] pitch_bent;
 wire [15:0] pitch_live;
 // Pressure ADS 0x49 A0 raises pitch; A1 lowers pitch.
 pressure_pitch_bend bend(clk,pitch_base,pressure[15:0],pressure_valid[0],
   pressure[31:16],pressure_valid[1],cmd_valid&&command==8'h30,pitch_bent);
 // Phone remote gate: 0x20 MASK[6:0], OR with copper touch; 500 ms fail-safe.
 wire [6:0] effective_gates;
 wire [6:0] remote_gates_dbg,pc_gates_dbg,phone_effective;
 remote_gate remote_gate_inst(
  .clk(clk),
  .cmd_valid(cmd_valid&&!cmd_source_pc),
  .command(command),
  .argument(argument),
  .physical_gate(mpr_online?gates:7'd0),
  .effective_gate(phone_effective),
  .remote_gate(remote_gates_dbg)
 );
 remote_gate pc_gate_inst(clk,cmd_valid&&cmd_source_pc,command,argument,
                         phone_effective,effective_gates,pc_gates_dbg);
 assign aux_retry=cmd_valid&&command==8'h40;
 wire timbre_press,rec_held,rec_long,play_press,stop_press,stop_long;
 debounced_button tb(clk,timbre_key,timbre_press,,);
 debounced_button rb(clk,rec_key,,rec_held,rec_long);
 debounced_button pb(clk,play_key,play_press,,);
 debounced_button sb(clk,stop_key,stop_press,,stop_long);
 reg was_rec_held=0,rec_was_long=0;
 wire rec_release=was_rec_held&&!rec_held&&!rec_was_long;
 always @(posedge clk) begin
  was_rec_held<=rec_held;
  if(!was_rec_held&&rec_held) rec_was_long<=0;
  if(rec_long) rec_was_long<=1;
 end
 reg [2:0] timbre=0;
 // Encoder vibrato is enabled by default; the host can still turn it off
 // with the existing feature command (bit1).
 reg [2:0] features=3'b010;
 // The existing PC/phone bit0 now controls the installed two-pad pitch bend.
 // Continue zero tracking/calibration even when bypassed.
 assign pitch_live=features[0]?pitch_bent:pitch_base;
 wire restored;
 wire [255:0] restored_settings;
 wire [223:0] calibration;
 wire [111:0] gains;
 wire restore_cal=restored&&restored_settings[255:248]==1;
 // Keep calibration/settings format, bypass the obsolete per-note gain map.
 pressure_mapper pm(clk,1'b0,pressure,pressure_valid,
   cmd_valid&&command==8'h30,cmd_valid&&command==8'h31,
   argument[6:0],
   restore_cal,restored_settings[223:0],gains,calibration);
 wire encoder_active,encoder_direction;
 wire [13:0] encoder_depth;
 wire [13:0] encoder_diagnostic;
 wire signed [31:0] modulation;
 rotary_encoder encoder(clk,sample_tick,features[1],encoder_a,encoder_b,
   encoder_active,encoder_direction,encoder_depth,modulation,encoder_diagnostic);
 // Keep the 16-bit telemetry slot and the B/C packet layout stable.  Its
 // meaning in v10 is encoder status: bit15 active, bit14 direction, bits13:0
 // vibrato depth.  The distance sensor is no longer used by the audio path.
 wire [15:0] encoder_status={encoder_active,encoder_direction,encoder_depth};
 always @(posedge clk) begin
  if(timbre_press) timbre<=timbre==4?0:timbre+1'b1;
  if(features[2]&&gesture_event) case(gesture)
   8'h01:timbre<=timbre==4?0:timbre+1'b1;
   8'h02:timbre<=timbre==0?4:timbre-1'b1;
   8'h04:features[1]<=1;
   8'h08:features[1]<=0;
   default:;
  endcase
  if(cmd_valid) case(command)
   8'h01:if(argument<=4) timbre<=argument[2:0];
   8'h02:features<=argument[2:0];
   // Masked feature update: upper byte is mask, lower byte is new bits.
   // PC toggles only the clicked feature so it preserves concurrent phone edits.
   8'h03:features<=(features&~argument[10:8])|(argument[2:0]&argument[10:8]);
   default:;
  endcase
  if(restore_cal) begin timbre<={restored_settings[242],restored_settings[247:246]}<=4?{restored_settings[242],restored_settings[247:246]}:3'd0;features<=restored_settings[245:243];end
 end
 wire [511:0] replay_packet,event_packet;
 wire replay_valid,event_valid,recording,playing,prepared,store_fault;
 wire [3:0] store_status,store_fault_code;
 wire [23:0] jedec;
 wire [255:0] settings={8'd1,timbre[1:0],features,timbre[2],18'd0,calibration};
 event_store store(clk,sample_time,
  (rec_long&&!recording&&!playing)||(cmd_valid&&command==8'h10),
  rec_release||(cmd_valid&&command==8'h11),
  stop_press||(cmd_valid&&command==8'h12),
  play_press||(cmd_valid&&command==8'h13),
  stop_long||(cmd_valid&&command==8'h14),settings,event_valid,event_packet,
  restored,restored_settings,replay_valid,replay_packet,
  recording,playing,prepared,store_status,store_fault,jedec,
  flash_miso,flash_sck,flash_mosi,flash_cs_n,store_fault_code);
 wire [7:0] active_revision;
 wire [2:0] active_timbre;
 wire [15:0] active_volume;
 control_scheduler control(clk,phase,frame,effective_gates,timbre,
  pitch_live,volume_valid?volume:16'd0,
  gains,modulation,{5'd0,features},16'd0,gesture,
  cmd_valid&&command==8'h7f,playing,replay_valid,replay_packet,
  ctrl_sck,ctrl_mosi,ctrl_cs_n,active_revision,active_timbre,active_volume,
  event_valid,event_packet);
 wire signed [23:0] partial_b,partial_c;
 wire b_ok,c_ok,link_done,link_busy;
 wire [2:0] error_b,error_c;
 audio_link_master link(clk,phase==80,frame[7:0],active_revision,
  audio_data_b,audio_data_c,audio_sck,audio_cs_n,link_busy,link_done,
  partial_b,partial_c,b_ok,c_ok,error_b,error_c);
 wire signed [23:0] continuous_b,continuous_c;
 audio_continuity cb(clk,link_done,b_ok,partial_b,continuous_b);
 audio_continuity cc(clk,link_done,c_ok,partial_c,continuous_c);
 wire signed [24:0] wide_sum=$signed({continuous_b[23],continuous_b})+
                            $signed({continuous_c[23],continuous_c});
 wire signed [24:0] normalized=active_timbre>=3?(wide_sum>>>1):(wide_sum>>>3);
 reg signed [15:0] mixed=0;
 wire signed [15:0] volume_sample;
 master_volume vol(clk,sample_tick,active_volume,volume_valid,mixed,volume_sample);
 reg [15:0] frame_sample=0;
 reg [3:0] stable_frames=0;
 reg mix_pending=0;
 reg [31:0] total_frames=0,bad_b=0,bad_c=0;
 reg [31:0] crc_b=0,crc_c=0,seq_b=0,seq_c=0,ver_b=0,ver_c=0;
 wire [287:0] link_counters={ver_c,ver_b,seq_c,seq_b,crc_c,crc_b,bad_c,bad_b,total_frames};
 always @(posedge clk) begin
  mix_pending<=link_done;
  if(link_done) begin
   total_frames<=total_frames+1'b1;
   if(!b_ok) bad_b<=bad_b+1'b1;
   if(!c_ok) bad_c<=bad_c+1'b1;
   if(error_b[0]) crc_b<=crc_b+1'b1;
   if(error_c[0]) crc_c<=crc_c+1'b1;
   if(error_b[1]) seq_b<=seq_b+1'b1;
   if(error_c[1]) seq_c<=seq_c+1'b1;
   if(error_b[2]) ver_b<=ver_b+1'b1;
   if(error_c[2]) ver_c<=ver_c+1'b1;
   if(b_ok&&c_ok) begin
    if(stable_frames!=15) stable_frames<=stable_frames+1'b1;
   end else stable_frames<=0;
  end
  if(mix_pending) mixed<=normalized>32767?16'sd32767:normalized< -32768?-16'sd32768:normalized[15:0];
  if(sample_tick) frame_sample<=volume_sample;
 end
 assign i2s_bclk=phase[2];
 wire [5:0] bit_index=phase[8:3];
 assign i2s_lrck=bit_index[5];
 always @(posedge clk) if(phase[2:0]==3'd7) begin
  if(bit_index<16) i2s_din<=frame_sample[15-bit_index];
  else if(bit_index>=32&&bit_index<48) i2s_din<=frame_sample[47-bit_index];
  else i2s_din<=0;
 end
 assign led=!(stable_frames>=3);
 status_dual status(clk,effective_gates,timbre,pitch,volume,
  {volume_valid,pitch_valid,adc_online[0],mpr_online},features,adc_online,aux_online,
  {c_ok,b_ok},store_status,{store_fault,prepared,playing,recording},cmd_seq,
  encoder_status,gesture,pressure_valid,pressure,link_counters,aux_diagnostic,probe_diagnostic,
  pc_cmd_seq,uart_tx,pc_uart_tx,encoder_diagnostic,store_fault_code,
  sample_tick,$signed(frame_sample));
endmodule

