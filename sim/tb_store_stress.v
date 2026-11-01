`timescale 1ns/1ps
module tb_store_stress;
 reg clk=0;always #5 clk=~clk;
 reg [31:0] tm=0;always @(posedge clk) tm<=tm+1;
 reg prep=0,rec=0,stop=0,play=0,save=0;
 reg [511:0] packet=0;
 wire restored,rv,recording,playing,prepared,fault;
 wire [255:0] settings;wire [511:0] replay;wire [3:0] status,code;
 wire [23:0] id;
 event_store #(.LOG_PAGES(96)) dut(clk,tm,prep,rec,stop,play,save,
  256'h1234,1'b1,packet,restored,settings,rv,replay,recording,playing,
  prepared,status,fault,id,1'b0,,,,code);
 integer i,replayed=0,erases_before=0;
 always @(posedge clk) if(rv) replayed=replayed+1;
 task pulse;input integer op;begin
  @(negedge clk);
  case(op) 0:prep=1;1:rec=1;2:stop=1;3:play=1;4:save=1;endcase
  @(negedge clk);prep=0;rec=0;stop=0;play=0;save=0;
 end endtask
 task ready;begin wait(dut.state==40&&!dut.stopping&&!playing);@(negedge clk);end endtask
 initial begin
  ready;
  pulse(0);wait(prepared);ready;
  if(dut.device.erase_count!=2) $fatal(1,"prepare erased more than two sectors");
  packet[438:432]=1;pulse(1);wait(recording);
  for(i=0;i<39;i=i+1) begin
   repeat(60) @(negedge clk);
   packet[438:432]=packet[438:432]==1?2:1;
  end
  wait(dut.after_flash==32&&dut.state==241);
  // STOP during on-demand sector erase; queue must drain and commit.
  pulse(2);repeat(2) @(negedge clk);
  if(recording||!dut.stopping||status!=6) $fatal(1,"STOP not latched while erase busy");
  ready;
  if(fault||dut.total_events!=40||dut.used!=0) $fatal(1,"lost queued events or STOP commit %d code=%d",dut.total_events,code);
  if(dut.device.erase_count!=4) $fatal(1,"lazy erase boundaries wrong");
  pulse(3);wait(playing);wait(!playing);ready;
  if(fault||replayed!=41||replay[438:432]!=0) $fatal(1,"replay/tail release failed %d code=%d",replayed,code);
  // Interrupted prepare must not leave stale abort or prepared flags.
  pulse(0);wait(status==2);pulse(2);ready;
  if(prepared) $fatal(1,"aborted prepare marked ready");
  erases_before=dut.device.erase_count;
  pulse(0);wait(prepared);ready;
  if(dut.device.erase_count-erases_before!=2) $fatal(1,"new prepare inherited old abort");
  // Inject a real readback mismatch, then recover with prepare.
  packet[438:432]=4;pulse(1);wait(recording);
  dut.device.corrupt_read=1;
  wait(fault);ready;
  if(code!=2||recording||prepared||dut.used!=0||dut.final_capture_pending)
   $fatal(1,"write verification fault not cleaned up");
  dut.device.corrupt_read=0;
  pulse(0);wait(prepared);ready;
  if(fault||code!=0) $fatal(1,"prepare failed to clear recoverable error");
  pulse(1);wait(recording);pulse(2);ready;
  if(fault||dut.total_events!=1) $fatal(1,"record after recovery failed");
  // SPI error must exit recording and reject stale prepared state.
  pulse(0);wait(prepared);ready;
  dut.device.inject_error=1;pulse(1);wait(fault);ready;
  if(code!=5||recording||prepared||dut.stopping) $fatal(1,"SPI timeout cleanup failed");
  $display("PASS storage stress: prepare2, lazy erase4, 40 queued events, STOP during erase, commit/replay/release, prepare abort/retry, CRC/SPI fault cleanup and recovery");$finish;
 end
 initial begin #30000000;$fatal(1,"storage stress timeout state=%d used=%d stopping=%b code=%d",dut.state,dut.used,dut.stopping,code);end
endmodule
