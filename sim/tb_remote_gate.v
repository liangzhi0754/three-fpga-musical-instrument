`timescale 1ns/1ps
module tb_remote_gate;
 reg clk=0;always #5 clk=~clk;
 reg cmd_valid=0;
 reg [7:0] command=0;
 reg [15:0] argument=0;
 reg [6:0] physical=0;
 wire [6:0] effective,remote;
 remote_gate #(.TIMEOUT_CYCLES(40)) dut(clk,cmd_valid,command,argument,physical,effective,remote);
 remote_gate defaults(.clk(clk),.cmd_valid(1'b0),.command(8'd0),
  .argument(16'd0),.physical_gate(7'd0),.effective_gate(),.remote_gate());
 task send;
  input [7:0] op;input [15:0] arg;
  begin
   @(negedge clk);command=op;argument=arg;cmd_valid=1;
   @(negedge clk);cmd_valid=0;
  end
 endtask
 initial begin
  if(defaults.TIMEOUT_CYCLES!=13500000) $fatal(1,"default timeout must be500ms at27MHz");
  repeat(2) @(negedge clk);
  if(effective!==0||remote!==0) $fatal(1,"startup gates");
  physical=7'h10;
  send(8'h20,16'h0005);
  if(remote!==7'h05||effective!==7'h15) $fatal(1,"DoMi OR physicalSol");
  repeat(30) @(negedge clk);send(8'h20,16'h0005);
  repeat(30) @(negedge clk);
  if(remote!==7'h05) $fatal(1,"keepalive failed");
  send(8'h20,16'h0000);
  if(remote!==0||effective!==7'h10) $fatal(1,"remote release must keep physical note");
  physical=0;send(8'h20,16'h007f);
  if(effective!==7'h7f) $fatal(1,"seven-note mask");
  repeat(30) @(negedge clk);send(8'h01,16'h007f);
  repeat(12) @(negedge clk);
  if(remote!==0||effective!==0) $fatal(1,"other commands must not refresh timeout");
  send(8'h20,16'hff40);
  if(effective!==7'h40) $fatal(1,"only low7 bits are keys");
  repeat(45) @(negedge clk);
  if(effective!==0) $fatal(1,"timeout release");
  $display("PASS remote masks, copper OR, release, keepalive, timeout, opcode isolation and500ms default");
  $finish;
 end
endmodule
