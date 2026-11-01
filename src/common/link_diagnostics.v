// Read-only status indicators. No diagnostic signal feeds the link or synth.
// LED0..5 are active low; startup walks all six LEDs to identify their order.
module link_diagnostics #(
 parameter integer HALF_SECOND_CYCLES=13500000,
 parameter integer RECENT_CYCLES=27000000,
 parameter integer ERROR_CYCLES=54000000
)(
 input wire clk,input wire ctrl_sck,input wire frame_toggle,
 input wire packet_valid,input wire packet_error,input wire locked,
 output wire [5:0] led_n
);
 reg [2:0] sck_sync=0,frame_sync=0;
 wire sck_edge=sck_sync[2]^sck_sync[1];
 wire frame_edge=frame_sync[2]^frame_sync[1];
 reg [25:0] sck_recent=0,frame_recent=0,valid_recent=0,error_recent=0;
 reg [23:0] half_second=0;
 reg heartbeat=0;
 reg walking=1;
 reg [2:0] walk_index=0;
 wire [5:0] live={error_recent!=0,locked,valid_recent!=0,
                  frame_recent!=0,sck_recent!=0,heartbeat};
 assign led_n=walking ? ~(6'b000001<<walk_index) : ~live;
 always @(posedge clk) begin
  sck_sync<={sck_sync[1:0],ctrl_sck};
  frame_sync<={frame_sync[1:0],frame_toggle};
  if(half_second==HALF_SECOND_CYCLES-1) begin
   half_second<=0;heartbeat<=~heartbeat;
   if(walking) begin
    if(walk_index==5) walking<=0;else walk_index<=walk_index+1'b1;
   end
  end else half_second<=half_second+1'b1;
  if(sck_edge) sck_recent<=RECENT_CYCLES;
  else if(sck_recent!=0) sck_recent<=sck_recent-1'b1;
  if(frame_edge) frame_recent<=RECENT_CYCLES;
  else if(frame_recent!=0) frame_recent<=frame_recent-1'b1;
  if(packet_valid) valid_recent<=RECENT_CYCLES;
  else if(valid_recent!=0) valid_recent<=valid_recent-1'b1;
  if(packet_error) error_recent<=ERROR_CYCLES;
  else if(error_recent!=0) error_recent<=error_recent-1'b1;
 end
endmodule
