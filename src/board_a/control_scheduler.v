// Transmit one coherent snapshot every 29 samples. Both nodes activate it at
// origin+28, after the 26-sample transfer plus conservative receive margin.
module control_scheduler(
 input wire clk,input wire [8:0] phase,input wire [15:0] frame,
 input wire [6:0] gates,input wire [2:0] timbre,input wire [15:0] pitch,
 input wire [15:0] volume,input wire [111:0] gains,
 input wire signed [31:0] modulation,input wire [7:0] flags,
 input wire [15:0] distance,input wire [7:0] gesture,
 input wire reset_request,input wire playing,input wire replay_valid,
 input wire [511:0] replay_packet,
 output wire ctrl_sck,output wire ctrl_mosi,output wire ctrl_cs_n,
 output reg [7:0] active_revision=0,output reg [2:0] active_timbre=0,
 output reg [15:0] active_volume=0,
 output reg event_valid=0,output reg [511:0] event_packet=0
);
 reg [4:0] interval=0;
 reg [7:0] revision=0;
 reg [15:0] origin=0,activation=0;
 reg pending=0,tx_start=0,reset_pending=1;
 reg [6:0] l_gates=0;
 reg [2:0] l_timbre=0;
 reg [15:0] l_pitch=13200,l_volume=0;
 reg [111:0] l_gains={7{16'd256}};
 reg signed [31:0] l_modulation=0;
 reg [7:0] l_flags=0,l_gesture=0;
 reg [15:0] l_distance=0;
 reg [511:0] playback=0;
 reg playback_tail=0,was_playing=0;
 reg [6:0] playback_gates=0;
 wire [511:0] packed;
 wire busy,done;
 control_pack pack(revision,activation,origin,l_flags,l_gates,l_timbre,
                   l_pitch,l_volume,l_gains,l_modulation,l_distance,l_gesture,packed);
 ctrl_packet_tx tx(clk,tx_start,packed,ctrl_sck,ctrl_mosi,ctrl_cs_n,busy,done);
 reg start_pending=0;
 reg [511:0] previous_event=0;
 integer j;
 always @(posedge clk) begin
  tx_start<=0;event_valid<=0;
  was_playing<=playing;
  if(reset_request) reset_pending<=1;
  if(playing&&!was_playing) begin
   playback<=0;playback_gates<=0;reset_pending<=1;
  end
  if(was_playing&&!playing) begin
   playback_tail<=1;playback_gates<=0;
  end
  if(replay_valid) begin
   playback<=replay_packet;playback_gates<=replay_packet[438:432];
  end
  if(phase==0) begin
   if(interval==28) interval<=0;else interval<=interval+1'b1;
   if(pending&&frame==activation) begin
    pending<=0;active_revision<=revision;active_timbre<=l_timbre;active_volume<=l_volume;
    event_packet<=packed;
    // Record the state when it becomes audible, not when transmission starts.
    if(packed[439:240]!=previous_event[439:240]) begin
     event_valid<=1;previous_event<=packed;
    end
   end
  end
  if(phase==128&&interval==0&&!busy&&!pending) begin
   origin<=frame;activation<=frame+16'd28;
   revision<=revision==255?1:revision+1'b1;
   l_gates<=(playing||playback_tail)?playback_gates:gates;
   l_timbre<=(playing||playback_tail)?playback[426:424]:timbre;
   l_pitch<=(playing||playback_tail)?playback[415:400]:pitch;
   l_volume<=(playing||playback_tail)?playback[399:384]:volume;
   for(j=0;j<7;j=j+1) l_gains[j*16+:16]<=(playing||playback_tail)?playback[511-(16+j*2)*8-:16]:gains[j*16+:16];
   l_modulation<=(playing||playback_tail)?playback[271:240]:modulation;
   l_distance<=distance;l_gesture<=gesture;
   l_flags<={reset_pending,4'd0,flags[2:0]};reset_pending<=0;
   pending<=1;start_pending<=1;
   if(playback_tail&&!playing) playback_tail<=0;
  end
  if(start_pending) begin tx_start<=1;start_pending<=0;end
 end
endmodule
