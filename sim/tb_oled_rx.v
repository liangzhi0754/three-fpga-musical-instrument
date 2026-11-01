`timescale 1ns/1ps
module tb_oled_rx;
 reg aclk=0,clk=0;
 always #18.5185 aclk=~aclk;
 initial begin #7;forever #18.521 clk=~clk;end
 reg [8:0] phase=0;reg din=0;
 reg [15:0] frame_sample=0;
 wire [5:0] bit_index=phase[8:3];
 wire bclk=phase[2],lrck=bit_index[5];
 integer n=0,received=0;
 reg connected=1;
 wire signed [15:0] sample;
 wire valid,online;
 oled_i2s_rx #(.TIMEOUT(2000)) dut(clk,connected?bclk:1'b0,
  connected?lrck:1'b0,din,sample,valid,online);
 // Bit-for-bit copy of the current A output logic, with distinct test samples.
 function [15:0] pattern;input integer i;
  begin case(i%7)
   0:pattern=16'h0000;1:pattern=16'h7FFF;2:pattern=16'h8000;
   3:pattern=16'hA55A;4:pattern=16'h5AA5;5:pattern=16'hFFFF;
   default:pattern=16'h0001;
  endcase end
 endfunction
 always @(posedge aclk) begin
  phase<=phase+1'b1;
  if(phase==0) begin frame_sample<=pattern(n);n<=n+1;end
  if(phase[2:0]==7) begin
   if(bit_index<16) din<=frame_sample[15-bit_index];
   else if(bit_index>=32&&bit_index<48) din<=frame_sample[47-bit_index];
   else din<=0;
  end
 end
 always @(negedge clk) if(valid) begin
  if(sample!==frame_sample) $fatal(1,"I2S mismatch got %h expected %h",sample,frame_sample);
  received=received+1;
 end
 initial begin
  wait(received==100);connected=0;
  repeat(2200) @(negedge clk);
  if(online) $fatal(1,"missing I2S timeout");
  connected=1;wait(received==120);
  $display("PASS exact A I2S generator, 120 signed samples, asynchronous clocks, loss/reconnect");$finish;
 end
 initial begin #5000000;$fatal(1,"timeout");end
endmodule
