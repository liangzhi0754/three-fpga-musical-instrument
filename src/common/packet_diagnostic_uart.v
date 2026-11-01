// Independent, read-only packet statistics at 4 Hz; 115200 baud, 8N1.
// Binary 40-byte packet AA D2 02 [board] ... XOR(bytes 2..36) 0D 0A.
module packet_diagnostic_uart #(
 parameter [7:0] BOARD_ID=8'h42,
 parameter integer REPORT_CYCLES=6750000,
 parameter integer RECENT_CYCLES=27000000
)(
 input wire clk,input wire ctrl_sck,input wire ctrl_cs_n,input wire ctrl_mosi,
 input wire frame_toggle,input wire locked,input wire debug_done,
 input wire [3:0] debug_reason,input wire [9:0] debug_count,
 input wire [23:0] debug_prefix,input wire [15:0] debug_crc_calc,
 input wire [15:0] debug_crc_wire,output wire tx
);
 reg [2:0] sck_sync=0,cs_sync=7,mosi_sync=0,frame_sync=0;
 wire sck_edge=sck_sync[2]^sck_sync[1];
 wire cs_edge=cs_sync[2]^cs_sync[1];
 wire mosi_edge=mosi_sync[2]^mosi_sync[1];
 wire frame_edge=frame_sync[2]^frame_sync[1];
 reg [24:0] sck_recent=0,cs_recent=0,mosi_recent=0,frame_recent=0;
 reg [31:0] total=0,good=0,bad=0,sck_count=0,frame_count=0;
 reg [3:0] last_reason=0;
 reg [9:0] last_count=0;
 reg [23:0] last_prefix=0;
 reg [15:0] last_calc=0,last_wire=0,sequence=0;
 reg [22:0] timer=0;
 reg [319:0] packet=0;
 reg [5:0] index=0;
 reg sending=0,waiting=0,start=0;
 wire busy;
 wire [7:0] data=packet[319-index*8-:8];
 wire [7:0] status={3'd0,locked,cs_recent!=0,mosi_recent!=0,
                    frame_recent!=0,sck_recent!=0};
 reg [319:0] next_packet;
 reg [7:0] checksum;
 integer j;
 always @* begin
  next_packet=0;
  next_packet[319-:32]={16'haad2,8'd2,BOARD_ID};
  next_packet[319-4*8-:16]={sequence[7:0],sequence[15:8]};
  next_packet[319-6*8-:8]=status;
  next_packet[319-7*8-:8]={4'd0,last_reason};
  next_packet[319-8*8-:32]={total[7:0],total[15:8],total[23:16],total[31:24]};
  next_packet[319-12*8-:32]={good[7:0],good[15:8],good[23:16],good[31:24]};
  next_packet[319-16*8-:32]={bad[7:0],bad[15:8],bad[23:16],bad[31:24]};
  next_packet[319-20*8-:16]={last_count[7:0],6'd0,last_count[9:8]};
  next_packet[319-22*8-:24]=last_prefix;
  next_packet[319-25*8-:16]=last_calc;
  next_packet[319-27*8-:16]=last_wire;
  next_packet[319-29*8-:32]={frame_count[7:0],frame_count[15:8],frame_count[23:16],frame_count[31:24]};
  next_packet[319-33*8-:32]={sck_count[7:0],sck_count[15:8],sck_count[23:16],sck_count[31:24]};
  checksum=0;
  for(j=2;j<=36;j=j+1) checksum=checksum^next_packet[319-j*8-:8];
  next_packet[23:0]={checksum,16'h0d0a};
 end
 uart_tx transmitter(clk,start,data,busy,tx);
 always @(posedge clk) begin
  sck_sync<={sck_sync[1:0],ctrl_sck};cs_sync<={cs_sync[1:0],ctrl_cs_n};
  mosi_sync<={mosi_sync[1:0],ctrl_mosi};frame_sync<={frame_sync[1:0],frame_toggle};
  if(sck_edge) begin sck_recent<=RECENT_CYCLES;sck_count<=sck_count+1'b1;end
  else if(sck_recent!=0) sck_recent<=sck_recent-1'b1;
  if(cs_edge) cs_recent<=RECENT_CYCLES;else if(cs_recent!=0) cs_recent<=cs_recent-1'b1;
  if(mosi_edge) mosi_recent<=RECENT_CYCLES;else if(mosi_recent!=0) mosi_recent<=mosi_recent-1'b1;
  if(frame_edge) begin frame_recent<=RECENT_CYCLES;frame_count<=frame_count+1'b1;end
  else if(frame_recent!=0) frame_recent<=frame_recent-1'b1;
  if(debug_done) begin
   total<=total+1'b1;
   if(debug_reason==0) good<=good+1'b1;else bad<=bad+1'b1;
   last_reason<=debug_reason;last_count<=debug_count;last_prefix<=debug_prefix;
   last_calc<=debug_crc_calc;last_wire<=debug_crc_wire;
  end
  start<=0;
  if(timer<REPORT_CYCLES) timer<=timer+1'b1;
  if(!sending) begin
   if(timer>=REPORT_CYCLES) begin
    packet<=next_packet;sequence<=sequence+1'b1;index<=0;
    sending<=1;waiting<=0;timer<=0;
   end
  end else if(waiting) begin
   if(busy) begin waiting<=0;if(index==39) sending<=0;else index<=index+1'b1;end
  end else if(!busy) begin start<=1;waiting<=1;end
 end
endmodule
