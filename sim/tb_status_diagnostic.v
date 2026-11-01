`timescale 1ns/1ps
module tb_status_diagnostic;
 reg clk=0;always #5 clk=~clk;
 wire tx;
 wire [7:0] rx;
 wire valid,err;
 reg [111:0] diagnostic=0;
 reg [287:0] counters=0;
 reg [111:0] pressure=0;
 reg [7:0] sum=0,expected;
 integer i,n=0,fd;
 status_extended dut(.clk(clk),.gates(7'h41),.timbre(2'd3),
  .pitch(16'h1234),.volume(16'h5678),.sensor_flags(4'hf),.features(3'd2),
  .ads_online(3'd7),.aux_online(2'd1),.link_ok(2'd3),.store_status(4'd0),
  .store_flags(4'd4),.command_sequence(8'h99),.distance(16'd200),.gesture(8'h02),
  .pressure_valid(7'h7f),.pressure(pressure),.link_counters(counters),
  .aux_diagnostic(diagnostic),.probe_diagnostic(160'h0102030405060708090a0b0c0d0e0f1011121314),.tx(tx));
 uart_rx receiver(clk,tx,rx,valid,err);
 initial begin
  for(i=0;i<14;i=i+1) diagnostic[i*8+:8]=8'h80+i;
  for(i=0;i<36;i=i+1) counters[i*8+:8]=i;
  for(i=0;i<7;i=i+1) pressure[i*16+:16]=100+i;
  fd=$fopen("validation/uart_fixture.hex","w");
 end
 always @(posedge clk) begin
  if(err) $fatal(1,"UART framing");
  if(valid) begin
   $fwrite(fd,"%02x\n",rx);
   if(n==0&&rx!=8'haa) $fatal(1,"header A");
   if(n==1&&rx!=8'h59) $fatal(1,"header 59");
   if(n>=2&&n<106) sum=sum+rx;
   if(n==4&&rx!=8'h41) $fatal(1,"touch compatibility");
   if(n==17&&rx!=8'h99) $fatal(1,"command ack compatibility");
   if(n>=36&&n<72&&rx!=n-36) $fatal(1,"audio counters compatibility");
   if(n>=72&&n<86&&rx!=8'h80+n-72) $fatal(1,"diagnostic field %d %h",n,rx);
   if(n>=86&&n<106&&rx!=8'h14-(n-86)) $fatal(1,"probe field %d %h",n,rx);
   if(n==106&&rx!=sum) $fatal(1,"checksum");
   if(n==107) begin
    if(rx!=13) $fatal(1,"terminator");
    $fclose(fd);$display("PASS 108-byte AA59 UART, audio counters, diagnostic fields and checksum");$finish;
   end
   n=n+1;
  end
 end
 initial begin #5000000;$fatal(1,"status timeout");end
endmodule
