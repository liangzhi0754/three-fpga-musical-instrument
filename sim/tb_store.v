`timescale 1ns/1ps
module tb_store;
 reg clk=0;
 always #5 clk=~clk;
 reg [31:0] time_count=0;
 reg [3:0] divider=0;
 always @(posedge clk) begin
  divider<=divider+1'b1;
  if(divider==15) time_count<=time_count+1'b1;
 end
 reg prepare=0,record_start=0,stop=0,play=0,save=0,event_valid=0;
 reg [511:0] packet=0;
 wire restored,replay_valid,recording,playing,prepared,fault;
 wire [255:0] settings;
 wire [511:0] replay;
 wire [3:0] status;
 wire [23:0] jedec;
 wire miso,sck,mosi,cs_n;
 event_store #(16) dut(clk,time_count,prepare,record_start,stop,play,save,
    256'h12345678,event_valid,packet,restored,settings,replay_valid,replay,
    recording,playing,prepared,status,fault,jedec,miso,sck,mosi,cs_n,);
 spi_flash_model chip(sck,cs_n,mosi,miso);
 integer seen=0;
 reg saw_initial=0,saw_second=0,saw_off=0,saw_final_volume=0;
 reg saw_violin=0;
 always @(posedge clk) if(replay_valid) begin
  seen=seen+1;
  if(replay[438:432]==1) saw_initial=1;
  if(replay[438:432]==4) saw_second=1;
  if(replay[438:432]==0) saw_off=1;
  if(replay[399:384]==12345) saw_final_volume=1;
  if(replay[426:424]==4) saw_violin=1;
 end
 task pulse;
  input integer which;
  begin
   @(negedge clk);
   case(which) 0:prepare=1;1:record_start=1;2:stop=1;3:play=1;4:save=1;5:event_valid=1;endcase
   @(negedge clk);prepare=0;record_start=0;stop=0;play=0;save=0;event_valid=0;
  end
 endtask
 initial begin
  wait(dut.state==40);pulse(4);
  wait(dut.settings_seq==1);
  pulse(0);wait(prepared);
  packet[438:432]=1;packet[425:424]=2;pulse(1);wait(recording);
  repeat(100) @(negedge clk);
  packet[438:432]=4;packet[426:424]=4;pulse(5);
  // Stop during a page operation, before the 10-ms analog coalescing window.
  wait(dut.state==200);@(negedge clk);
  packet[399:384]=12345;
  pulse(2);
  wait(dut.total_events==3&&!dut.stopping&&dut.state==40);
  pulse(3);wait(playing);wait(!playing);
  if(fault||!saw_initial||!saw_second||!saw_off||!saw_final_volume||!saw_violin||seen!=4)
   $display("FAIL store fault=%b initial=%b second=%b off=%b seen=%0d",fault,saw_initial,saw_second,saw_off,seen);
  else $display("PASS settings readback, initial snapshot, STOP while busy, final analog capture, replay and note-off");
  $finish;
 end
 initial begin #20000000;$display("FAIL storage timeout state=%d used=%d total=%d fault=%b jedec=%h",dut.state,dut.used,dut.total_events,fault,jedec);$finish;end
endmodule
