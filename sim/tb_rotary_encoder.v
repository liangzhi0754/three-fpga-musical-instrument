`timescale 1ns/1ps
module tb_rotary_encoder;
  reg clk=0, enable=1, enc_a=1, enc_b=1;
  reg [8:0] divider=0;
  wire sample_tick=divider==511;
  wire active, direction;
  wire [13:0] depth;
  wire signed [31:0] modulation;

  rotary_encoder dut(
    .clk(clk), .sample_tick(sample_tick), .enable(enable),
    .enc_a(enc_a), .enc_b(enc_b), .active(active), .direction(direction),
    .depth(depth), .modulation(modulation));

  always #5 clk=~clk;
  always @(posedge clk) divider<=divider+1'b1;
  task state;
    input a; input b;
    begin @(negedge clk); enc_a=a; enc_b=b; repeat(14000) @(negedge clk); end
  endtask
  task samples;
    input integer n;
    integer k;
    begin for(k=0;k<n;k=k+1) begin @(posedge sample_tick); @(negedge clk); end end
  endtask
  task cw;
    begin state(1,0); state(0,0); state(0,1); state(1,1); end
  endtask
  task ccw;
    begin state(0,1); state(0,0); state(1,0); state(1,1); end
  endtask
  integer i;
  integer last_mod;
  reg changed=0;
  initial begin
    state(1,1); samples(20);
    if(active || depth!=0 || modulation!=0) $fatal(1,"boot ghost motion");
    // Short noise pulses, and a stable forward/back bounce: no complete cycle.
    enc_b=0; repeat(100) @(negedge clk); enc_b=1;
    state(1,0); state(1,1); samples(20);
    if(active) $fatal(1,"bounce counted as motion");
    // Illegal two-bit jump and return: no complete cycle.
    state(0,0); state(1,1); samples(20);
    if(active) $fatal(1,"illegal transition counted");
    cw(); samples(20);
    if(!active || !direction) $fatal(1,"CW/hold missing after 20 samples");
    // Old STOP_SAMPLES=16 fails the preceding check. Actual effect must exist.
    samples(2000);
    if(depth<8000 || modulation==0) $fatal(1,"no vibrato after CW");
    last_mod=modulation;
    for(i=0;i<100;i=i+1) begin
        samples(1);
        if(modulation!=last_mod) changed=1;
        if(modulation>30000 || modulation< -30000) $fatal(1,"unbounded modulation");
    end
    if(!changed) $fatal(1,"LFO not moving");
    // Check the actual default timeout, in sample units at 27MHz/512.
    while(dut.age>2) samples(1);
    if(!active) $fatal(1,"motion expired before 300ms");
    samples(5);
    if(active) $fatal(1,"motion failed to expire");
    samples(1300);
    if(depth!=0 || modulation!=0) $fatal(1,"pitch effect persists after stop");
    enable=0; ccw(); samples(20);
    if(!active || direction || modulation!=0) $fatal(1,"disabled physical monitor/CCW");
    enable=1; samples(5000);
    if(depth<8000) $fatal(1,"reenabled motion not audible");
    $display("PASS default-rate hold300ms, CW/CCW, bounce, illegal jump, LFO, stop, disable monitor");
    $finish;
  end
  initial begin #200000000; $fatal(1,"simulation timeout"); end
endmodule
