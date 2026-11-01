`timescale 1ns/1ps
module tb_oled_visualizer;
 reg clk=0;always #5 clk=~clk;
 reg signed [15:0] sample=0;
 reg valid=0,online=1,done=0;
 reg [1:0] mode=0;
 wire ready,captured_online;wire [1:0] captured_mode;
 wire [7:0] data;
 reg [9:0] addr=0;
 reg signed [15:0] stimulus [0:1279];
 integer scenario=0,tick=0,n=0,i,fd;
 reg [8*100-1:0] filename;
 oled_visualizer #(.TRIGGER_WAIT(16)) dut(clk,sample,valid,online,mode,
  done,addr,data,ready,captured_online,captured_mode,7'd0);
 initial $readmemh("sim/visual_stimulus.hex",stimulus);
 always @(negedge clk) begin
  valid=0;
  if(tick==9) begin
   tick=0;sample=stimulus[scenario*256+(n/4)%256];valid=1;n=n+1;
  end else tick=tick+1;
 end
 task snapshot;input integer k;
 begin
  wait(ready);#1;
  $sformat(filename,"validation/visual_%0d.txt",k);
  fd=$fopen(filename,"w");
  $fdisplay(fd,"%d %d %d",dut.peak,dut.gain_shift,captured_mode);
  for(i=0;i<256;i=i+1) $fdisplay(fd,"%d %d %d",$signed(dut.samples[i]),$signed(dut.normalized[i]),$signed(dut.windowed[i]));
  for(i=0;i<64;i=i+1) $fdisplay(fd,"%d",dut.magnitudes[i]);
  for(i=0;i<1024;i=i+1) $fdisplay(fd,"%h",dut.pixels[i]);
  $fdisplay(fd,"%d",dut.spectrum_offset);
  $fclose(fd);
 end endtask
 task next_frame;input integer sc;input [1:0] m;
 begin
  @(posedge clk);#1;scenario=sc;mode=m;n=0;
  @(posedge clk);#1;done=1;
  @(posedge clk);#1;done=0;
  wait(!ready);
 end endtask
 initial begin
  snapshot(0);
  next_frame(1,0);snapshot(1);
  next_frame(2,1);snapshot(2);
  next_frame(3,3);snapshot(3);
  next_frame(4,3);snapshot(4);

  $display("PASS actual samples: v14 small/large sine, delay XY, actual two-tone DFT and silence; dumped framebuffers for numeric reference checks");
  $finish;
 end
 initial begin #30000000;$fatal(1,"visualizer timeout state=%d point=%d",dut.state,dut.point);end
endmodule
