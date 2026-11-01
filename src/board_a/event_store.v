// Alternating settings sectors, CRC verified event pages and a commit header.
// Version 2 stores one timestamp/control snapshot per page, never PCM audio.
module event_store #(parameter integer LOG_PAGES=32720, FIFO_BITS=6)(
 input wire clk,input wire [31:0] sample_time,
 input wire prepare,input wire record_start,input wire stop,input wire play,
 input wire save_settings,input wire [255:0] settings,
 input wire event_valid,input wire [511:0] event_packet,
 output reg restore_settings=0,output reg [255:0] restored_settings=0,
 output reg replay_valid=0,output reg [511:0] replay_packet=0,
 output reg recording=0,output reg playing=0,output reg prepared=0,
 output reg [3:0] status=0,output reg fault=0,output wire [23:0] jedec_id,
 input wire miso,output wire sck,output wire mosi,output wire cs_n,
 output reg [3:0] fault_code=0
);
 reg fs_start=0;
 reg [1:0] fs_op=0;
 reg [23:0] fs_addr=0;
 reg [7:0] ram_addr=0,ram_data=0;
 reg ram_write=0;
 wire [7:0] ram_q;
 wire fs_busy,fs_done,fs_error;
 flash_page device(clk,fs_start,fs_op,fs_addr,ram_addr,ram_write,ram_data,
   ram_q,miso,sck,mosi,cs_n,jedec_id,fs_busy,fs_done,fs_error);
 reg [7:0] state=0,after_flash=0,after_crc=0;
 reg [1:0] page_kind=0;
 reg [7:0] byte_index=0;
 reg [15:0] crc=16'hffff,stored_crc=0,expected_crc=0;
 reg crc_ok=0;
 function [15:0] crc_byte;
  input [15:0] current;input [7:0] data;
  reg [15:0] c;integer b;
  begin c=current^{data,8'd0};
   for(b=0;b<8;b=b+1) c=c[15]?(c<<1)^16'h1021:c<<1;
   crc_byte=c;
  end
 endfunction
 reg [31:0] settings_seq=0,seq_a=0,page_sequence=0,magic=0;
 reg valid_a=0,settings_sector=0;
 reg [255:0] settings_a=0,latched_settings=0,page_settings=0,build_settings=0;
 reg [31:0] record_epoch=0,play_epoch=0,event_count=0,read_count=0,total_events=0;
 reg [15:0] page_index=0,erase_index=0;
 reg [15:0] erased_sectors=0;
 localparam integer FIFO_DEPTH=(1<<FIFO_BITS);
 reg [31:0] event_time=0,tail_time=0,replay_end_time=0;
 reg [511:0] packet=0,last_recorded=0;
 reg [31:0] last_record_time=0;
 reg pending_save=0,pending_prepare=0,pending_record=0,pending_play=0;
 reg stopping=0,abort_request=0;
 reg final_capture_pending=0;
 reg [511:0] stop_packet=0;
 reg [31:0] fifo_words[0:(FIFO_DEPTH*32)-1];
 reg [543:0] write_shift=0,read_shift=0;
 reg [4:0] write_word=0,read_word=0;
 reg [FIFO_BITS:0] used=0;
 reg [FIFO_BITS-1:0] wp=0,rp=0;
 reg enqueue_busy=0;
 reg [31:0] fifo_q=0;
 wire [FIFO_BITS+4:0] write_address={wp,5'd0}+write_word;
 wire [FIFO_BITS+4:0] read_address={rp,5'd0}+read_word;
 wire [511:0] capture_packet=final_capture_pending?stop_packet:event_packet;
 wire changed=capture_packet[439:240]!=last_recorded[439:240];
 wire urgent={event_packet[438:432],event_packet[426:424]}!=
             {last_recorded[438:432],last_recorded[426:424]};
 // Note edges have priority. Recorded continuous controls coalesce to 20 Hz;
 // live audio/control timing is unchanged. This bounds sector-erase traffic.
 // The held event_packet retains updates after the event_valid pulse ends.
 wire capture=!enqueue_busy&&changed&&(event_count+used<LOG_PAGES)&&(final_capture_pending||
              (recording&&!stopping&&!stop&&(urgent||(used<FIFO_DEPTH-2&&sample_time-last_record_time>=2640))));
 wire signed [31:0] due=$signed(sample_time-play_epoch)-$signed(event_time);
 always @(posedge clk) begin
  if(enqueue_busy) fifo_words[write_address]<=write_shift[543:512];
  fifo_q<=fifo_words[read_address];
 end
 // Abort failed recording cleanly: no stuck recording/prepared or stale FIFO.
 task fail_store;
  input [3:0] code;
  begin
   fault<=1;fault_code<=code;recording<=0;stopping<=0;prepared<=0;
   final_capture_pending<=0;used<=0;enqueue_busy<=0;pending_record<=0;
   pending_play<=0;pending_save<=0;pending_prepare<=0;abort_request<=0;
   total_events<=0;state<=playing?55:40;
  end
 endtask
 task flash;
  input [1:0] operation;input [23:0] address;input [7:0] resume;
  begin fs_op<=operation;fs_addr<=address;fs_start<=1;after_flash<=resume;state<=240;end
 endtask
 task scan;
  input [7:0] resume;
  begin ram_addr<=0;byte_index<=0;crc<=16'hffff;magic<=0;
   stored_crc<=0;after_crc<=resume;state<=210;end
 endtask
 task build_page;
  input [1:0] kind;input [7:0] resume;
  begin page_kind<=kind;build_settings<=latched_settings;byte_index<=0;crc<=16'hffff;after_crc<=resume;state<=200;end
 endtask
 reg [7:0] build_byte;
 always @* begin
  build_byte=8'hff;
  if(byte_index<4) begin
   case(page_kind)
    0:case(byte_index) 0:build_byte="S";1:build_byte="E";2:build_byte="T";3:build_byte="2";endcase
    1:case(byte_index) 0:build_byte="E";1:build_byte="V";2:build_byte="T";3:build_byte="2";endcase
    2:case(byte_index) 0:build_byte="L";1:build_byte="O";2:build_byte="G";3:build_byte="2";endcase
   endcase
  end else if(byte_index<8) begin
   case(page_kind)
    0:build_byte=(settings_seq+32'd1)>>((7-byte_index)*8);
    1:build_byte=event_time>>((7-byte_index)*8);
    2:build_byte=event_count>>((7-byte_index)*8);
   endcase
  end else if(page_kind==0&&byte_index<40) build_byte=build_settings[255:248];
  else if(page_kind==1&&byte_index<72) build_byte=packet[511:504];
  else if(page_kind==2&&byte_index<12) build_byte=tail_time>>((11-byte_index)*8);
  else if(byte_index==254) build_byte=crc[15:8];
  else if(byte_index==255) build_byte=crc[7:0];
 end
 always @(posedge clk) begin
  fs_start<=0;ram_write<=0;restore_settings<=0;replay_valid<=0;
  if(save_settings) begin pending_save<=1;latched_settings<=settings;end
  if(prepare&&!recording&&!playing&&!stopping) pending_prepare<=1;
  if(record_start&&!recording&&!playing&&!stopping) pending_record<=1;
  if(play&&!recording&&!playing&&!stopping) pending_play<=1;
  if(capture) begin
   final_capture_pending<=0;
   if(used==FIFO_DEPTH) fail_store(4'd4);
   else begin
    write_shift<={final_capture_pending?tail_time:sample_time-record_epoch,capture_packet};write_word<=0;
    enqueue_busy<=1;used<=used+1'b1;last_recorded<=capture_packet;last_record_time<=sample_time;
   end
  end
  if(final_capture_pending&&!enqueue_busy&&(!changed||event_count+used>=LOG_PAGES)) final_capture_pending<=0;
  if(stop) begin
   pending_record<=0;pending_play<=0;pending_prepare<=0;
   if(recording) begin
    recording<=0;stopping<=1;status<=6;tail_time<=sample_time-record_epoch;
    stop_packet<=event_packet;final_capture_pending<=(event_count+used<LOG_PAGES);
   end
   if(playing||status==2) abort_request<=1;
  end
  case(state)
   0:begin status<=1;flash(3,0,1);end
   // Enable only verified Winbond IDs until the supplied chip is identified.
   1:if(jedec_id[23:16]!=8'hef||jedec_id[7:0]!=8'h17) begin fault<=1;fault_code<=1;state<=250;end
     else flash(0,0,2);
   2:scan(3);
   3:begin
    valid_a<=crc_ok&&magic==32'h53455432;
    seq_a<=page_sequence;settings_a<=page_settings;flash(0,24'h001000,4);
   end
   4:scan(5);
   5:begin
    if(crc_ok&&magic==32'h53455432&&(!valid_a||$signed(page_sequence-seq_a)>0)) begin
     restored_settings<=page_settings;restore_settings<=1;settings_seq<=page_sequence;settings_sector<=1;
    end else if(valid_a) begin
     restored_settings<=settings_a;restore_settings<=1;settings_seq<=seq_a;settings_sector<=0;
    end
    flash(0,24'h002000,6);
   end
   6:scan(7);
   7:begin
    if(crc_ok&&magic==32'h4c4f4732&&page_sequence<=LOG_PAGES) begin
     total_events<=page_sequence;replay_end_time<=event_time;
    end
    state<=40;
   end
   20:build_page(0,21);
   21:flash(1,settings_sector?24'd0:24'h001000,22);
   22:flash(0,settings_sector?24'd0:24'h001000,23);
   23:scan(24);
   24:begin
    if(!crc_ok||crc!=expected_crc) begin fault<=1;fault_code<=2;end
    else begin settings_seq<=settings_seq+1'b1;settings_sector<=!settings_sector;end
    state<=40;
   end
   30:begin
    if(abort_request) begin abort_request<=0;state<=40;end
    // Prepare only header + first 16 event pages. Remaining sectors are erased on demand.
    else if(erase_index<2) flash(2,24'h002000+{erase_index,12'd0},31);
    else begin prepared<=1;erased_sectors<=1;state<=40;status<=0;end
   end
   31:begin erase_index<=erase_index+1'b1;state<=30;end
   40:begin
    status<=stopping?6:playing?4:recording?3:0;
    if(pending_prepare&&!recording&&!playing&&!stopping&&!stop) begin
     pending_prepare<=0;pending_record<=0;pending_play<=0;prepared<=0;
     total_events<=0;erase_index<=0;fault<=0;fault_code<=0;abort_request<=0;
     used<=0;wp<=0;rp<=0;enqueue_busy<=0;final_capture_pending<=0;
     state<=30;status<=2;
    end else if(pending_save&&!recording&&!playing&&!stopping&&!stop) begin
     pending_save<=0;status<=5;flash(2,settings_sector?24'd0:24'h001000,20);
    end else if(pending_record&&!recording&&!playing&&!stopping&&!stop) begin
     pending_record<=0;
     if(prepared) begin
      recording<=1;record_epoch<=sample_time;event_count<=0;page_index<=0;
      used<=1;rp<=0;wp<=0;prepared<=0;total_events<=0;
      write_shift<={32'd0,event_packet};write_word<=0;enqueue_busy<=1;
      last_recorded<=event_packet;last_record_time<=sample_time;status<=3;
      fault<=0;fault_code<=0;abort_request<=0;final_capture_pending<=0;
     end else begin fault<=1;fault_code<=6;end
    end else if((recording||stopping)&&used!=0&&!capture&&!enqueue_busy) begin
     read_word<=0;read_shift<=0;state<=60;
    end else if(stopping&&used==0&&!enqueue_busy&&!final_capture_pending) state<=45;
    else if(pending_play&&!recording&&!stopping&&!stop) begin
     pending_play<=0;
     if(total_events!=0) begin
      page_index<=0;read_count<=0;playing<=1;status<=4;abort_request<=0;
      flash(0,24'h003000,50);
     end else begin fault<=1;fault_code<=7;end
    end
   end
   41:build_page(1,42);
   42:if((page_index>>4)>=erased_sectors)
       flash(2,24'h003000+{page_index[15:4],12'd0},32);
      else flash(1,24'h003000+{page_index,8'd0},43);
   32:begin erased_sectors<=erased_sectors+1'b1;state<=42;end
   43:flash(0,24'h003000+{page_index,8'd0},44);
   44:scan(46);
   46:begin
    if(!crc_ok||crc!=expected_crc) fail_store(4'd2);
    else if(page_index==LOG_PAGES-1) begin
     recording<=0;stopping<=1;status<=6;tail_time<=sample_time-record_epoch;
     final_capture_pending<=0;state<=40;
    end
    else begin page_index<=page_index+1'b1;state<=40;end
   end
   45:build_page(2,47);
   47:flash(1,24'h002000,48);
   48:flash(0,24'h002000,49);
   49:scan(57);
   57:begin
    if(!crc_ok||crc!=expected_crc) begin fault<=1;fault_code<=3;end
    else begin total_events<=event_count;replay_end_time<=tail_time;end
    stopping<=0;state<=40;
   end
   50:scan(51);
   51:begin
    if(!crc_ok||magic!=32'h45565432) begin fault<=1;fault_code<=8;state<=55;end
    else begin if(read_count==0) play_epoch<=sample_time;state<=53;end
   end
   53:if(abort_request) state<=55;
      else if(due>=0) begin
       replay_packet<=packet;replay_valid<=1;read_count<=read_count+1'b1;
       if(read_count+1>=total_events) state<=54;
       else begin page_index<=page_index+1'b1;state<=52;end
      end
   52:flash(0,24'h003000+{page_index,8'd0},50);
   54:if(abort_request||sample_time-play_epoch>=replay_end_time) state<=55;
   55:begin replay_packet[438:432]<=0;replay_valid<=1;state<=56;end
   56:begin playing<=0;abort_request<=0;state<=40;end
   60:state<=61;
   61:begin
    read_shift<={read_shift[511:0],fifo_q};
    if(read_word==16) state<=62;
    else begin read_word<=read_word+1'b1;state<=60;end
   end
   62:if(!capture&&!enqueue_busy) begin
    event_time<=read_shift[543:512];packet<=read_shift[511:0];
    rp<=rp+1'b1;used<=used-1'b1;event_count<=event_count+1'b1;state<=41;
   end
   200:begin
    ram_addr<=byte_index;ram_data<=build_byte;ram_write<=1;
    if(byte_index<254) crc<=crc_byte(crc,build_byte);
    if(page_kind==0&&byte_index>=8&&byte_index<40) build_settings<={build_settings[247:0],build_settings[255:248]};
    if(page_kind==1&&byte_index>=8&&byte_index<72) packet<={packet[503:0],packet[511:504]};
    if(byte_index==255) begin expected_crc<=crc;state<=201;end
    else byte_index<=byte_index+1'b1;
   end
   201:state<=after_crc;
   // Address is registered; wait one cycle before consuming synchronous RAM.
   210:state<=211;
   211:begin
    if(byte_index<254) crc<=crc_byte(crc,ram_q);
    if(byte_index<4) magic<={magic[23:0],ram_q};
    if(byte_index>=4&&byte_index<8) begin
     page_sequence<={page_sequence[23:0],ram_q};
     if(playing) event_time<={event_time[23:0],ram_q};
    end
    if(byte_index>=8&&byte_index<12&&!playing) event_time<={event_time[23:0],ram_q};
    if(byte_index>=8&&byte_index<40) page_settings<={page_settings[247:0],ram_q};
    if(byte_index>=8&&byte_index<72&&playing) packet<={packet[503:0],ram_q};
    if(byte_index==254) stored_crc[15:8]<=ram_q;
    if(byte_index==255) begin crc_ok<=crc=={stored_crc[15:8],ram_q};state<=after_crc;end
    else begin byte_index<=byte_index+1'b1;ram_addr<=byte_index+1'b1;state<=210;end
   end
   240:if(fs_busy) state<=241;
   241:if(fs_done) begin
    if(fs_error) fail_store(4'd5);
    else state<=after_flash;
   end
   250:begin status<=15;pending_save<=0;pending_prepare<=0;pending_record<=0;pending_play<=0;end
   default:state<=0;
  endcase
  if(enqueue_busy) begin
   write_shift<={write_shift[511:0],32'd0};
   if(write_word==16) begin enqueue_busy<=0;wp<=wp+1'b1;end
   else write_word<=write_word+1'b1;
  end
  // Error has final priority over concurrent queue/state assignments.
  if(capture&&used==FIFO_DEPTH) fail_store(4'd4);
  // Complete any active SPI transaction before ending playback.
  if(playing&&abort_request&&!fs_busy&&state!=240&&state!=241&&state!=55&&state!=56) state<=55;
 end
endmodule
