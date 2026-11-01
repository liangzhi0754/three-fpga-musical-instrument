// One coherent 128-column trace, frozen while SSD1306 is being refreshed.
// 2 input samples/column: 128 columns span about 4.85ms at 52734.375Hz.
module oled_wave_capture #(parameter integer TRIGGER_TIMEOUT=540000)(
 input wire clk,input wire signed [15:0] sample,input wire sample_valid,
 input wire online,input wire frame_done,
 input wire [6:0] read_x,output wire [5:0] read_y,
 output reg ready=0,output reg captured_online=0
);
 reg [5:0] trace [0:127];
 reg [1:0] state=0;
 reg [6:0] x=0;
 reg decimate=0,previous_negative=0;
 reg [19:0] wait_cycles=0;
 reg [8:0] fallback=0;
 wire tick=online?sample_valid:(fallback==511);
 wire signed [15:0] value=online?sample:16'sd0;
 wire signed [16:0] scaled=value>>>10;
 wire signed [17:0] mapped=18'sd36-scaled;
 wire [5:0] y=(mapped<9)?6'd9:(mapped>62)?6'd62:mapped[5:0];
 assign read_y=trace[read_x];
 always @(posedge clk) begin
  fallback<=fallback+1'b1;
  if(state==0) begin
   ready<=0;
   if(wait_cycles<TRIGGER_TIMEOUT) wait_cycles<=wait_cycles+1'b1;
   if(tick) begin
    previous_negative<=value[15];
    if((previous_negative && !value[15]) || wait_cycles>=TRIGGER_TIMEOUT) begin
     state<=1;x<=0;decimate<=0;wait_cycles<=0;
     captured_online<=online;
    end
   end
  end else if(state==1) begin
   if(tick) begin
    decimate<=!decimate;
    if(!decimate) begin
     trace[x]<=y;
     if(x==127) begin ready<=1;state<=2;end
     else x<=x+1'b1;
    end
   end
  end else if(frame_done) begin
   state<=0;ready<=0;wait_cycles<=0;
  end
 end
endmodule
