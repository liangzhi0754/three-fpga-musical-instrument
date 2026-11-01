`timescale 1ns/1ps
module tb_pc_wave_stream;
 reg clk=0;always #5 clk=~clk;
 reg status_valid=0;reg [863:0] packet=0;
 reg [4:0] divider=0;
 reg signed [15:0] sample=16'sd1024;
 wire sample_valid=(divider==0);
 always @(posedge clk) divider<=divider+1'b1;
 wire tx;wire [7:0] rx;wire valid,error;
 pc_wave_stream #(.FRAME_PERIOD(5000),.TRIGGER_WAIT(50)) dut(
  clk,status_valid,packet,sample_valid,sample,tx);
 uart_rx receiver(clk,tx,rx,valid,error);
 reg [7:0] bytes[0:139];integer n=0,total=0,statuses=0,waves=0,i,sum,fd;
 initial fd=$fopen("validation/wave_uart.hex","w");
 always @(negedge clk) if(valid) begin
  if(error) $fatal(1,"framing");
  $fdisplay(fd,"%02x",rx);
  bytes[n]=rx;n=n+1;
  if(n==2) total=(bytes[1]==8'h59)?108:140;
  if(n==total && total!=0) begin
   sum=0;for(i=2;i<total-2;i=i+1) sum=(sum+bytes[i])&255;
   if(bytes[0]!=8'haa || bytes[total-1]!=13 || bytes[total-2]!=sum) $fatal(1,"packet integrity");
   if(total==140) begin
    if(bytes[3]!=1||bytes[5]!=4||bytes[6]!=0||bytes[7]!=(waves==2?0:4)||bytes[8]!=(waves==2?0:4)) $fatal(1,"capture header");
    for(i=10;i<138;i=i+1)
     if(bytes[i]!=(waves==0?64:waves==1?192:0)) $fatal(1,"sample %d=%d",i,bytes[i]);
    waves=waves+1;
    sample=waves==1?-16'sd1024:16'sd0;
   end else begin
    statuses=statuses+1;
    if(waves>0 && bytes[4]!=7'h45) $fatal(1,"quick touch lost %h",bytes[4]);
   end
   n=0;total=0;
   if(waves>=3 && statuses>=2) begin
    $fclose(fd);$display("PASS actual samples, AGC, CRC, interleaved status and quick touch preservation");$finish;
   end
  end
 end
 task send_status;
 input [6:0] gates;
 begin
  @(negedge clk);packet=0;packet[863-:16]=16'haa59;packet[863-3*8-:8]=1;
  packet[863-4*8-:8]=gates;packet[15:8]=1+gates;packet[7:0]=13;
  status_valid=1;@(negedge clk);status_valid=0;
 end endtask
 initial begin
  send_status(7'h41);
  wait(dut.wave_packet && dut.sending);
  send_status(7'h04);send_status(7'h41);
 end
 initial begin #25000000;$fatal(1,"timeout");end
endmodule
