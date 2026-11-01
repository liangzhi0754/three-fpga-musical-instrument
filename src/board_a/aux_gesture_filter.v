// Poll results are events, not switches: require a quiet gap before repeating
// the same result. A different direction only waits the short inter-event guard.
module aux_gesture_filter #(
 parameter integer CLOCKS_PER_MS=27000,
 parameter integer CHANGE_MS=60,
 parameter integer REPEAT_MS=180,
 parameter integer QUIET_MS=40
)(
 input wire clk,input wire reset,input wire poll_valid,input wire [7:0] raw,
 output reg [7:0] gesture=0,output reg event_pulse=0
);
 reg [31:0] change_left=0,repeat_left=0,quiet_count=0;
 reg neutral=0,armed=1,seen=0;
 wire single_bit=raw!=0 && (raw & (raw-8'd1))==0;
 always @(posedge clk) begin
  event_pulse<=0;
  if(reset) begin
   gesture<=0;change_left<=0;repeat_left<=0;quiet_count<=0;
   neutral<=0;armed<=1;seen<=0;
  end else begin
   if(change_left!=0) change_left<=change_left-1'b1;
   if(repeat_left!=0) repeat_left<=repeat_left-1'b1;
   if(neutral) begin
    if(quiet_count<QUIET_MS*CLOCKS_PER_MS) quiet_count<=quiet_count+1'b1;
    else armed<=1;
   end
   if(poll_valid) begin
    neutral<=raw==0;
    if(raw!=0) begin quiet_count<=0;armed<=0;end
    // Ambiguous multi-bit samples neither command an action nor consume guard.
    if(single_bit && (!seen ||
       ((raw!=gesture) ? change_left==0 : (armed && repeat_left==0)))) begin
     gesture<=raw;event_pulse<=1;seen<=1;armed<=0;
     change_left<=CHANGE_MS*CLOCKS_PER_MS;
     repeat_left<=REPEAT_MS*CLOCKS_PER_MS;
    end
   end
  end
 end
endmodule
