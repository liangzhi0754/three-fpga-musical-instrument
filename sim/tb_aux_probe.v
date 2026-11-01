`timescale 1ns/1ps
module tb_aux_probe;
 reg clk=0;always #5 clk=~clk;
 reg start=0,present=0,scl_stuck=0,sda_stuck=0,bridge=0;
 tri1 scl,sda;
 assign scl=scl_stuck?1'b0:1'bz;
 assign sda=sda_stuck?1'b0:1'bz;
 tranif1 short_lines(scl,sda,bridge);
 wire busy,done;
 wire [159:0] diag;
 aux_probe #(.HALF_PERIOD(5),.HOLD_CLOCKS(20),.RISE_TIMEOUT(40))
  dut(clk,start,scl,sda,busy,done,diag);
 i2c_vl53_model sensor(scl,sda,present,1'b0,1'b0);
 integer samples=0;
 task run_scan;
  begin @(negedge clk);start=1;@(negedge clk);start=0;wait(done);@(negedge clk);end
 endtask
 // The register model accepts addresses but a probe must never send a
 // register address or a data byte (mode 2 follows a register byte).
 always @(posedge clk) if(sensor.mode==2) $fatal(1,"Probe wrote a register byte");
 initial begin
  run_scan;
  if(diag[7:0]!=255||diag[15:8]!=127||diag[31:24]!=0||diag[159:32]!=0)
   $fatal(1,"empty bus %h",diag);
  present=1;run_scan;
  if(diag[31:24]!=1||!diag[32+41]||diag[159:32]!=(128'd1<<41))
   $fatal(1,"address scan %h",diag);
  scl_stuck=1;run_scan;
  if(diag[7:0]!=254||diag[8]!=0) $fatal(1,"stuck SCL %h",diag);
  scl_stuck=0;sda_stuck=1;run_scan;
  if(diag[7:0]!=254||diag[9]!=0) $fatal(1,"stuck SDA %h",diag);
  sda_stuck=0;bridge=1;run_scan;
  if(diag[7:0]!=254||diag[11]!=0||diag[13]!=0) $fatal(1,"cross bridge %h",diag);
  $display("PASS empty bus, 0x29 address, no register writes, SCL/SDA stuck and crossed-line diagnosis");$finish;
 end
 initial begin #4000000;$fatal(1,"probe timeout phase %d",diag[7:0]);end
endmodule
