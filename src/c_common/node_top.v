// CTRL and frame timing are sampled in local clk. Source frame numbering is
// recovered from the packet origin plus frame edges observed during transfer.
module node_top #(
 parameter integer FIRST_KEY=0, parameter integer KEY_COUNT=3,
 parameter integer FIRST_HARMONIC=1,
 parameter integer FRAME_FILTER_CYCLES=1,
 parameter integer PIPELINE_PITCH=0
)(
 input wire clk,input wire ctrl_sck,input wire ctrl_mosi,input wire ctrl_cs_n,
 input wire frame_toggle,input wire audio_sck,input wire audio_cs_n,
 output wire audio_data,output wire led,
 output wire debug_packet_valid,output wire debug_packet_error,
 output wire debug_locked,output wire debug_done,
 output wire [3:0] debug_reason,output wire [9:0] debug_count,
 output wire [23:0] debug_prefix,
 output wire [15:0] debug_crc_calc,output wire [15:0] debug_crc_wire,
 output wire [6:0] display_notes,
 output wire [6:0] control_notes
);
 wire [511:0] received;
 wire valid,begin_packet,packet_error;
 ctrl_packet_rx rx(.clk(clk),.sck(ctrl_sck),.cs_n(ctrl_cs_n),.mosi(ctrl_mosi),
  .packet(received),.valid(valid),.begin_packet(begin_packet),.error(packet_error),
  .debug_done(debug_done),.debug_reason(debug_reason),.debug_count(debug_count),
  .debug_prefix(debug_prefix),.debug_crc_calc(debug_crc_calc),.debug_crc_wire(debug_crc_wire));
 reg [2:0] frame_sync=0;
 // Two-flop synchronization alone does not reject a narrow wire pulse. In
 // filtered nodes, commit one level transition only after it stays stable.
 reg filtered_level=0,filtered_tick=0;
 reg [3:0] frame_stable=0;
 wire tick=(FRAME_FILTER_CYCLES>1)?filtered_tick:(frame_sync[2]^frame_sync[1]);
 reg [15:0] frames_during_rx=0,source_frame=0;
 reg [511:0] pending=0,active=0;
 reg have_pending=0,locked=0;
 reg [7:0] version=0,sequence=0;
 reg synth_tick=0,synth_reset=0;
 reg [7:0] synth_tick_pipe=0,synth_reset_pipe=0;
 wire engine_tick=PIPELINE_PITCH?synth_tick_pipe[7]:synth_tick;
 wire engine_reset=PIPELINE_PITCH?synth_reset_pipe[7]:synth_reset;
 reg [19:0] timeout=0;
 wire [15:0] activation=pending[511-4*8-:16];
 wire [7:0] pending_flags=pending[511-8*8-:8];
 wire signed [23:0] partial_sum;
 wire [111:0] gains;
 genvar k;
 generate for(k=0;k<7;k=k+1) begin: gain_unpack
  assign gains[k*16+:16]=active[511-(16+k*2)*8-:16];
 end endgenerate
 node_synth #(FIRST_KEY,KEY_COUNT,FIRST_HARMONIC,PIPELINE_PITCH) engine(
  clk,engine_reset,engine_tick,active[438:432],active[426:424],
  active[511-12*8-:16],gains,active[511-30*8-:32],partial_sum);
 audio_link_slave ret(clk,audio_sck,audio_cs_n,partial_sum,sequence,version,audio_data);
 // Display command activity only. Additive mode actually sounds the lowest
 // held note; ordinary modes sound every held note. Release tails are not bars.
 wire [6:0] gates_for_display=active[438:432];
 wire [6:0] lowest_gate=gates_for_display & (~gates_for_display+7'd1);
 assign display_notes=(!locked || active[399:384]<=16'd64)?7'd0:
                      gates_for_display;
 assign control_notes=locked?gates_for_display:7'd0;
 assign led=~locked;
 assign debug_packet_valid=valid;
 assign debug_packet_error=packet_error;
 assign debug_locked=locked;
 always @(posedge clk) begin
  frame_sync<={frame_sync[1:0],frame_toggle};
  filtered_tick<=0;
  if(frame_sync[2]==filtered_level) frame_stable<=0;
  else if(frame_stable==FRAME_FILTER_CYCLES-1) begin
   filtered_level<=frame_sync[2];frame_stable<=0;filtered_tick<=1;
  end else frame_stable<=frame_stable+1'b1;
  // Active packet changes before the pitch pipeline settles. Delay the engine
  // event by eight local clocks (0.30 us), well before A polls at frame+80.
  synth_tick_pipe<={synth_tick_pipe[6:0],synth_tick};
  synth_reset_pipe<={synth_reset_pipe[6:0],synth_reset};
  synth_tick<=0; synth_reset<=0;
  if(timeout<20'd810000) timeout<=timeout+1'b1;
  else begin locked<=0; version<=0; active<=0; end
  if(begin_packet) frames_during_rx<=0;
  else if(tick) frames_during_rx<=frames_during_rx+1'b1;
  if(tick) begin
   source_frame<=source_frame+1'b1;
   sequence<=source_frame[7:0]+1'b1;
   synth_tick<=locked;
   if(have_pending && source_frame+16'd1==activation) begin
    active<=pending; version<=pending[511-3*8-:8];
    have_pending<=0; locked<=1; synth_tick<=1;
    synth_reset<=pending_flags[7]||!locked;
   end
  end
  if(valid) begin
   pending<=received; have_pending<=1; timeout<=0;
   source_frame<=received[511-6*8-:16]+frames_during_rx;
  end
 end
endmodule
