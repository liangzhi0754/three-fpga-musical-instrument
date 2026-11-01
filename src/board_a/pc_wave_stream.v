// PC-only status/wave multiplexing. Phone UART and audio timing are unchanged.
// AA5A v1: 10-byte header, 128 signed8 points, checksum and CR (140 bytes).
// Header: AA 5A seq 01 flags decimation peak_lo peak_hi shift 00.
// 256 four-sample averages, positive zero-cross trigger, first 128 displayed.
module pc_wave_stream #(
 parameter integer FRAME_PERIOD=2700000, TRIGGER_WAIT=540000
)(
 input wire clk,input wire status_valid,input wire [863:0] status_packet,
 input wire sample_valid,input wire signed [15:0] sample,
 output wire tx
);
 reg [863:0] sending_packet=0;
 reg [7:0] pending_gates=0;
 reg status_pending=0;
 reg signed [15:0] samples[0:255];
 reg [2:0] capture_state=0;
 reg [21:0] timer=0;
 reg [19:0] trigger_timer=0;
 reg negative=0;
 reg [1:0] decimate=0;
 reg signed [17:0] box_sum=0;
 wire signed [18:0] total=$signed(box_sum)+$signed(sample);
 wire signed [18:0] average=total>>>2;
 wire [15:0] absolute=average[15]?(~average[15:0]+16'd1):average[15:0];
 reg [7:0] point=0;
 reg [15:0] peak=0;
 reg [3:0] gain_shift=0;
 reg wave_ready=0;
 reg [7:0] wave_seq=0;
 function [3:0] scale_shift;
  input [15:0] p;
  begin
   if(p>=32768) scale_shift=9;else if(p>=16384) scale_shift=8;
   else if(p>=8192) scale_shift=7;else if(p>=4096) scale_shift=6;
   else if(p>=2048) scale_shift=5;else if(p>=1024) scale_shift=4;
   else if(p>=512) scale_shift=3;else if(p>=256) scale_shift=2;
   else if(p>=128) scale_shift=1;else scale_shift=0;
  end
 endfunction
 reg sending=0,wave_packet=0,waiting=0,start=0;
 reg [7:0] index=0,checksum=0;
 wire busy;
 reg [7:0] data;
 wire [7:0] address=index-8'd10;
 reg signed [15:0] sample_read=0;
 always @(posedge clk) sample_read<=samples[address];
 wire signed [15:0] scaled=$signed(sample_read)>>>gain_shift;
 always @* begin
  data=0;
  if(!wave_packet) data=sending_packet[863:856];
  else case(index)
   0:data=8'haa;1:data=8'h5a;2:data=wave_seq;3:data=1;
   4:data=1;5:data=4;6:data=peak[7:0];7:data=peak[15:8];
   8:data={4'd0,gain_shift};9:data=0;
   138:data=checksum;139:data=13;
   default:data=peak<32?8'd0:scaled[7:0];
  endcase
 end
 uart_tx transmitter(clk,start,data,busy,tx);
 always @(posedge clk) begin
  start<=0;
  if(timer<FRAME_PERIOD) timer<=timer+1'b1;
  if(capture_state==0 && timer>=FRAME_PERIOD && !wave_ready) begin
   capture_state<=1;trigger_timer<=0;
  end
  if(capture_state==1) begin
   if(trigger_timer<TRIGGER_WAIT) trigger_timer<=trigger_timer+1'b1;
   if(sample_valid) begin
    negative<=sample[15];
    if((negative&&!sample[15])||trigger_timer>=TRIGGER_WAIT) begin
     capture_state<=2;point<=0;decimate<=0;box_sum<=0;peak<=0;
    end
   end
  end
  if(capture_state==2 && sample_valid) begin
   if(decimate==3) begin
    decimate<=0;box_sum<=0;samples[point]<=average[15:0];
    if(absolute>peak) peak<=absolute;
    if(point==255) capture_state<=3;else point<=point+1'b1;
   end else begin decimate<=decimate+1'b1;box_sum<=total[17:0];end
  end
  if(capture_state==3) begin
   gain_shift<=scale_shift(peak);wave_ready<=1;capture_state<=4;
  end
  if(!sending) begin
   if(wave_ready) begin
    sending<=1;wave_packet<=1;waiting<=0;index<=0;checksum<=0;
    wave_seq<=wave_seq+1'b1;
   end else if(status_pending) begin
    sending_packet<=status_packet;status_pending<=0;pending_gates<=0;
    sending_packet[863-4*8-:8]<=status_packet[863-4*8-:8]|pending_gates;
    sending_packet[15:8]<=status_packet[15:8]-status_packet[863-4*8-:8]+
                         (status_packet[863-4*8-:8]|pending_gates);
    sending<=1;wave_packet<=0;waiting<=0;index<=0;
   end
  end else if(waiting) begin
   if(busy) begin
    waiting<=0;
    if(!wave_packet) sending_packet<=sending_packet<<8;
    if(index==(wave_packet?139:107)) begin
     sending<=0;
     if(wave_packet) begin wave_ready<=0;capture_state<=0;timer<=0;end
    end else index<=index+1'b1;
   end
  end else if(!busy) begin
   start<=1;waiting<=1;
   if(wave_packet && index>=2 && index<138) checksum<=checksum+data;
  end
  // Preserve quick touches while coalescing status during a wave transfer.
  // Do not merge a pending frame that is being consumed on this clock.
  if(status_valid) begin
   status_pending<=1;
   pending_gates<=(status_pending && (sending||wave_ready))?
     pending_gates|status_packet[863-4*8-:8]:status_packet[863-4*8-:8];
  end
 end
endmodule
