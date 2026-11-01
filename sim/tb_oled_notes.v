`timescale 1ns/1ps
module tb_oled_notes;
 reg clk=0;always #5 clk=~clk;
 reg done=0,online=1;
 reg [6:0] gates=0;
 wire ready,co;wire [1:0] cm;wire [7:0] data;
 reg [9:0] addr=0;
 integer k,x,y,a,bitn,expected,fd,t;
 reg [8*100-1:0] filename;
 oled_visualizer dut(clk,16'sd0,1'b0,online,2'd2,done,addr,data,ready,co,cm,gates);
 task check;
 input [6:0] mask;input integer id;
 begin
  wait(ready);#1;
  if(cm!=2 || dut.captured_notes!==mask) $fatal(1,"wrong note snapshot");
  // Exact body bitmap independent of RTL note_pixels function.
  for(y=8;y<56;y=y+1) for(x=0;x<128;x=x+1) begin
   expected=0;
   for(k=0;k<7;k=k+1)
    if(mask[k] && x>=4+k*18 && x<16+k*18 && y>=16 && y<54) expected=1;
   a=(y/8)*128+x;bitn=y%8;
   if(((dut.pixels[a]>>bitn)&1)!==expected) $fatal(1,"wrong bar at x=%d y=%d mask=%h",x,y,mask);
  end
  $sformat(filename,"validation/notes_%0d.hex",id);fd=$fopen(filename,"w");
  for(a=0;a<1024;a=a+1) $fdisplay(fd,"%h",dut.pixels[a]);
  $fclose(fd);
 end endtask
 task next;
 input [6:0] mask;
 begin
  @(negedge clk);gates=mask;done=1;
  @(negedge clk);done=0;wait(!ready);
 end endtask
 initial begin
  check(0,0);
  for(t=0;t<7;t=t+1) begin next(1<<t);check(1<<t,t+1);end
  next(7'b1010101);check(7'b1010101,8);
  // Changing a command while a frame is being transmitted cannot tear it.
  gates=7'h7F;#100;check(7'b1010101,9);
  next(7'h7F);check(7'h7F,10);
  next(0);check(0,11);
  online=0;next(7'h7F);check(0,12);
  $display("PASS seven columns: all seven single notes, chord, release, silence, offline, coherent frame snapshot");
  $finish;
 end
 initial begin #10000000;$fatal(1,"notes timeout");end
endmodule
