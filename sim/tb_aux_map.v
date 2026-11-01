`timescale 1ns/1ps
module tb_aux_map;
 reg clk=0;
 always #5 clk=~clk;
 tri1 scl,sda;
 aux_sensors dut(
  .clk(clk), .scl(scl), .sda(sda),
  .distance(), .distance_valid(), .gesture(),
  .gesture_event(), .online(), .retry(1'b0), .diagnostic(), .probe_diagnostic()
 );
 integer j;
 reg [47:0] result;
 initial begin
  @(negedge clk);dut.boot_probe=0;
  dut.pc=46;dut.state=0;dut.slots[1]=8'h85;
  for(j=2;j<8;j=j+1) dut.slots[j]=255;
  wait(dut.pc==47);@(negedge clk);
  result={dut.slots[7],dut.slots[6],dut.slots[5],dut.slots[4],dut.slots[3],dut.slots[2]};
  if(result!=48'h00000001f000) begin $display("FAIL SPAD aperture map %h",result);$finish;end
  dut.pc=46;dut.state=0;dut.slots[1]=3;
  for(j=2;j<8;j=j+1) dut.slots[j]=0;
  dut.slots[2]=8'h55;
  wait(dut.pc==47);@(negedge clk);
  result={dut.slots[7],dut.slots[6],dut.slots[5],dut.slots[4],dut.slots[3],dut.slots[2]};
  if(result!=48'h15) begin $display("FAIL sparse SPAD map %h",result);$finish;end
  $display("PASS sequential VL53L0X SPAD mask, aperture and sparse cases");$finish;
 end
 initial begin #100000;$display("FAIL SPAD map timeout");$finish;end
endmodule
