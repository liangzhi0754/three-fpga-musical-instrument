`timescale 1ns/1ps
module tb_aux_diagnostic;
 reg clk=0;always #5 clk=~clk;
 tri1 scl,sda;
 reg present=0,bad_id=0,poll_stuck=0,retry=0,scl_stuck=0;
 assign scl=scl_stuck?1'b0:1'bz;
 wire [15:0] distance;
 wire valid;
 wire [1:0] online;
 wire [111:0] diag;
 aux_sensors #(.I2C_HALF_PERIOD(4),.DELAY_CLOCKS_PER_MS(1),.POLL_LIMIT(3),.PROBE_HALF_PERIOD(4),.PROBE_HOLD(20),
 .PROBE_RISE_TIMEOUT(40),.BOOT_WAIT(1)) dut(
  clk,scl,sda,distance,valid,,,online,retry,diag,);
 i2c_vl53_model sensor(scl,sda,present,bad_id,poll_stuck);
 task restart;
  begin @(negedge clk);retry=1;@(negedge clk);retry=0;wait(dut.pc==0);end
 endtask
 initial begin
  wait(dut.pc==218);@(negedge clk);
  if(diag[23:16]!=1||diag[31:24]!=1||diag[47:40]!=8'hc0||diag[111:104]!=1)
   $fatal(1,"missing device diagnostic %h",diag);
  present=1;bad_id=1;restart;
  wait(dut.pc==218);@(negedge clk);
  if(diag[23:16]!=3||diag[55:48]!=8'hea||diag[63:56]!=8'hea)
   $fatal(1,"wrong model diagnostic %h",diag);
  bad_id=0;poll_stuck=1;restart;
  wait(dut.pc==218);@(negedge clk);
  if(diag[23:16]!=2||diag[31:24]!=25||diag[47:40]!=8'h83)
   $fatal(1,"poll timeout diagnostic %h",diag);
  poll_stuck=0;restart;
  wait(valid);@(negedge clk);
  if(!online[0]||distance!=200||diag[55:48]!=8'hee)
   $fatal(1,"valid distance %h %d",diag,distance);
  // Retry during an active transfer must wait for a safe script boundary.
  wait(dut.busy);restart;wait(valid);@(negedge clk);
  if(distance!=200) $fatal(1,"retry did not recover");
  scl_stuck=1;@(negedge clk);retry=1;@(negedge clk);retry=0;
  wait(dut.fail_code==1&&dut.fail_bus==5);@(negedge clk);
  if(online[0]) $fatal(1,"stuck SCL must not stay online");
  $display("PASS missing sensor, ID mismatch, poll timeout, 200mm range, safe retry and SCL watchdog over real I2C");
  $finish;
 end
 initial begin #12000000;$fatal(1,"aux timeout PC=%d state=%d diag=%h",dut.pc,dut.state,diag);end
endmodule
