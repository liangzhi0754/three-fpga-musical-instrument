`timescale 1ns/1ps
module tb_encoder_short_states;
 reg clk=0,enc_a=1,enc_b=1;
 reg [8:0] div=0;
 always #5 clk=~clk;
 always @(posedge clk) div<=div+1'b1;
 wire active,direction;
 wire [13:0] depth;
 wire signed [31:0] modulation;
 wire [13:0] diagnostic;
 rotary_encoder dut(.clk(clk),.sample_tick(div==511),.enable(1'b1),
 .enc_a(enc_a),.enc_b(enc_b),.active(active),.direction(direction),.depth(depth),
 .modulation(modulation),.diagnostic(diagnostic));
 task state;input a,b;input integer clocks;
 begin @(negedge clk);enc_a=a;enc_b=b;repeat(clocks) @(negedge clk);end endtask
 initial begin
  state(1,1,15000);
  // Clean, complete quadrature cycle; each state lasts 100 us at 27 MHz.
  // A debouncer that requires the AB pair to settle for 500 us drops it all.
  state(1,0,2700);state(0,0,2700);state(0,1,2700);state(1,1,2700);
  repeat(1024) @(negedge clk);
  if(!active) $fatal(1,"clean 100us AB states completely missed");
  if(diagnostic[13:8]!=1||!direction) begin $display("diag=%h dir=%b active=%b",diagnostic,direction,active); $fatal(1,"full cycle count/direction"); end
  if(diagnostic[3:2]!=3||!diagnostic[6]) $fatal(1,"input evidence missing");
  // One half cycle in reverse must work without requiring four new edges.
  state(0,1,2700);state(0,0,2700);
  if(diagnostic[13:8]!=2||direction) $fatal(1,"half-step detent missed");
  // Repeated bounce on only one phase never adds a motion, even when it
  // lasts beyond the short filter. Short glitches are filtered as well.
  state(1,0,2700);state(0,0,2700);
  state(1,0,100);state(0,0,1000);
  if(diagnostic[13:8]!=2) $fatal(1,"single phase bounce became motion");
  repeat(2400000) @(negedge clk);
  if(depth==0) $fatal(1,"clean cycle produced no effect");
  $display("PASS 100us states, half-step/reverse, single-phase bounce, short glitch, diagnostic counts, real sample cadence vibrato");$finish;
 end
 initial begin #40000000;$fatal(1,"short state timeout");end
endmodule
