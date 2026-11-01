`timescale 1ns/1ps
module tb_spectrum_center;
 reg clk=0;always #5 clk=~clk;
 wire ready,online;wire [1:0] mode;wire [7:0] data;
 oled_visualizer dut(clk,16'sd0,1'b0,1'b1,2'd2,1'b0,10'd0,data,ready,online,mode,7'd0);
 integer i,x,y,h,shift,maxv,first,last,offset,expected,actual,scenario;
 integer magnitudes[0:63];
 task check;
 input integer id;
 begin
  // Isolate raster stage using synthetic DFT magnitudes, exercise negative
  // offsets, both edges, wide spectra, weak tails and silence explicitly.
  @(negedge clk);
  maxv=0;first=-1;last=-1;
  for(i=0;i<64;i=i+1) begin
   magnitudes[i]=0;
   case(id)
    0:if(i==3) magnitudes[i]=4096;
    1:if(i==60) magnitudes[i]=4096;
    2:if(i==0 || i==63) magnitudes[i]=4096;
    3:begin
      if(i==2) magnitudes[i]=4096;
      if(i==10) magnitudes[i]=2048;
      if(i==63) magnitudes[i]=200;
     end
    4:begin
      if(i==52) magnitudes[i]=4096;
      if(i==60) magnitudes[i]=2048;
      if(i==0) magnitudes[i]=200;
     end
    default: magnitudes[i]=0;
   endcase
   dut.magnitudes[i]=magnitudes[i];
   if(magnitudes[i]>maxv) maxv=magnitudes[i];
  end
  for(i=0;i<64;i=i+1) if(maxv!=0 && magnitudes[i]>(maxv>>4)) begin
   if(first<0) first=i;last=i;
  end
  offset=(first<0)?0:63-first-last;
  shift=0;while((maxv>>shift)>48) shift=shift+1;
  for(i=0;i<1024;i=i+1) dut.pixels[i]=0;
  dut.captured_mode=3;dut.ready=0;dut.max_magnitude=maxv;dut.state=24;
  wait(ready);#1;
  if($signed(dut.spectrum_offset)!=offset) $fatal(1,"wrong offset scenario %d",id);
  for(y=8;y<64;y=y+1) for(x=0;x<128;x=x+1) begin
   expected=0;
   for(i=0;i<64;i=i+1) begin
    h=magnitudes[i]>>shift;
    if((x==i*2+offset || x==i*2+1+offset) && y>62-h && y<=62) expected=1;
   end
   actual=(dut.pixels[(y/8)*128+x]>>(y%8))&1;
   if(actual!==expected) $fatal(1,"wrong spectrum raster id=%d x=%d y=%d",id,x,y);
  end
 end endtask
 initial begin
  wait(ready);
  for(scenario=0;scenario<6;scenario=scenario+1) check(scenario);
  $display("PASS centered spectrum: low/high peaks, positive/negative shift, full-width band, clipped weak tails without wrap, silence; exact raster");
  $finish;
 end
 initial begin #10000000;$fatal(1,"spectrum center timeout");end
endmodule
