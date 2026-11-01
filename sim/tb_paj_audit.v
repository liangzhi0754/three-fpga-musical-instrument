`timescale 1ns/1ps
module tb_paj_audit;
 reg clk=0;always #5 clk=~clk;
 tri1 scl,sda;
 reg present=1,bad_id=0,reject_mask=0,retry=0;
 reg [7:0] injected=0;
 wire [15:0] distance;
 wire valid,event_pulse;
 wire [7:0] gesture;
 wire [1:0] online;
 wire [111:0] diag;
 wire [159:0] probe_diag;
 integer events=0;
 aux_sensors #(.I2C_HALF_PERIOD(6),.DELAY_CLOCKS_PER_MS(3),
  .POLL_LIMIT(3),.PROBE_HALF_PERIOD(6),.PROBE_HOLD(25),
  .PROBE_RISE_TIMEOUT(60),.BOOT_WAIT(2),.GESTURE_RETRY_LIMIT(3)) dut(
  clk,scl,sda,distance,valid,gesture,event_pulse,online,retry,diag,probe_diag);
 i2c_paj_model #(.WAKE_NACKS(2)) sensor(scl,sda,present,bad_id,reject_mask,injected);
 always @(posedge clk) if(event_pulse) events=events+1;
 task restart;
  begin
   @(negedge clk);retry=1;@(negedge clk);retry=0;
   wait(dut.probe_busy);wait(!dut.probe_busy);
   wait(dut.pc==160);
  end
 endtask
 initial begin
  wait(online[1]);@(negedge clk);
  if(online[0]||dut.gesture_retries<1||sensor.missing_stop!=0)
   $fatal(1,"wake/read compatibility failed online=%b retries=%d missing_stop=%d",
      online,dut.gesture_retries,sensor.missing_stop);
  if(sensor.regs[9'h041]!=255||sensor.regs[9'h172]!=1||sensor.regs[9'h165]!=18)
   $fatal(1,"gesture enable/mask/report rate missing");
  injected=1;wait(gesture==1);wait(events==1);
  // Actual I2C polling must not repeat a continuously asserted result.
  repeat(2000) @(negedge clk);
  if(events!=1) $fatal(1,"persistent I2C gesture retriggered");
  @(negedge clk);injected=2;
  wait(gesture==2);wait(events==2);injected=0;
  // After wake, the next scan must see address0x73.
  restart;wait(online[1]);@(negedge clk);
  if(!probe_diag[32+115]||probe_diag[31:24]!=1)
   $fatal(1,"0x73 scan wrong %h",probe_diag);
  bad_id=1;restart;wait(dut.pc==218);@(negedge clk);
  if(online[1]||diag[23:16]!=3||!diag[33]||diag[63:56]!=8'h21)
   $fatal(1,"gesture ID fault hidden by missing distance %h",diag);
  bad_id=0;reject_mask=1;restart;wait(dut.pc==218);@(negedge clk);
  if(online[1]||diag[23:16]!=1||diag[47:40]!=8'h41||!diag[33])
   $fatal(1,"gesture init write fault hidden %h",diag);
  reject_mask=0;present=0;restart;wait(dut.pc==218);@(negedge clk);
  if(online!=0||probe_diag[31:24]!=0||probe_diag[7:0]!=255)
   $fatal(1,"absent PAJ diagnosis %h",probe_diag);
  present=1;restart;wait(online[1]);@(negedge clk);
  $display("PASS PAJ wake retry, STOP/read, enable/mask/rate, I2C persistent-result suppression and direction change,0x73 scan, ID/init faults and reconnect");
  $finish;
 end
 initial begin #16000000;$fatal(1,"PAJ timeout pc=%d state=%d contacts=%d missing_stop=%d diag=%h",dut.pc,dut.state,sensor.contacts,sensor.missing_stop,diag);end
endmodule
