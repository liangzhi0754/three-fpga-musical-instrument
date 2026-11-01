`timescale 1ns/1ps
module tb_remote_uart_control;
 reg clk=0;always #5 clk=~clk;
 reg rx=1;
 wire cmd_valid;
 wire [7:0] opcode,seq;
 wire [15:0] arg;
 reg [6:0] physical=0;
 wire [6:0] effective,remote;
 integer accepted=0;
 host_commands host(clk,rx,cmd_valid,opcode,arg,seq);
 remote_gate #(.TIMEOUT_CYCLES(60000)) gate(clk,cmd_valid,opcode,arg,physical,effective,remote);
 always @(posedge clk) if(cmd_valid) accepted=accepted+1;
 reg [8:0] phase=0;
 reg [15:0] frame=0;
 always @(posedge clk) begin phase<=phase+1'b1;if(phase==511) frame<=frame+1'b1;end
 wire [511:0] event_packet;
 wire event_valid;
 control_scheduler scheduler(.clk(clk),.phase(phase),.frame(frame),.gates(effective),
  .timbre(2'd0),.pitch(16'd13200),.volume(16'd10000),.gains({7{16'd256}}),
  .modulation(32'd0),.flags(8'd0),.distance(16'd0),.gesture(8'd0),
  .reset_request(1'b0),.playing(1'b0),.replay_valid(1'b0),.replay_packet(512'd0),
  .ctrl_sck(),.ctrl_mosi(),.ctrl_cs_n(),.active_revision(),.active_timbre(),
  .active_volume(),.event_valid(event_valid),.event_packet(event_packet));
 reg saw_remote_event=0,saw_release_event=0;
 always @(negedge clk) if(event_valid) begin
  if(event_packet[438:432]==7'h05) saw_remote_event=1;
  if(saw_remote_event&&event_packet[438:432]==0) saw_release_event=1;
 end
 task byte_out;
  input [7:0] b;integer k;
  begin
   @(negedge clk);rx=0;repeat(234) @(negedge clk);
   for(k=0;k<8;k=k+1) begin rx=b[k];repeat(234) @(negedge clk);end
   rx=1;repeat(234) @(negedge clk);
  end
 endtask
 task packet;
  input [7:0] s,op,mask,checksum;
  begin
   byte_out(8'h43);byte_out(8'h4d);byte_out(s);byte_out(op);
   byte_out(mask);byte_out(8'h00);byte_out(checksum);byte_out(8'h0d);
   repeat(10) @(negedge clk);
  end
 endtask
 initial begin
  repeat(100) @(negedge clk);
  packet(8'h10,8'h20,8'h05,8'h34);
  if(accepted!=0||remote!==0) $fatal(1,"bad checksum accepted");
  packet(8'h10,8'h20,8'h05,8'h35);
  if(accepted!=1||seq!=8'h10||remote!==7'h05) $fatal(1,"valid DoMi command");
  wait(saw_remote_event);
  repeat(65000) @(negedge clk);
  if(remote!==0) $fatal(1,"UART remote timeout");
  wait(saw_release_event);
  physical=7'h10;packet(8'h11,8'h20,8'h00,8'h31);
  if(accepted!=2||effective!==7'h10) $fatal(1,"explicit release affected copper");
  $display("PASS UART checksum/sequence, remote DoMi control+record-event packet and timeout release event, copper preservation");
  $finish;
 end
 initial begin #5000000;$fatal(1,"remote integration timeout accepted=%d remote=%h",accepted,remote);end
endmodule
