// Three independent single-shot ADS1115 converters, interleaved on one bus.
// Ready is polled from OS before reading, avoiding stale MUX conversions.
module adc_scanner(
 input wire clk,inout wire scl,inout wire sda,
 output reg [15:0] pitch=13200,output reg [15:0] volume=0,
 output reg [111:0] pressure=0,output reg [2:0] online=0,
 output reg pitch_valid=0,output reg volume_valid=0,
 output reg [6:0] pressure_valid=0
);
 reg [1:0] chip=0;
 reg [1:0] channel[0:2];
 reg pending[0:2];
 reg [31:0] age[0:2];
 reg [2:0] state=0;
 wire req=(state==1||state==3||state==5);
 wire [1:0] op=(state==1)?2'd1:2'd2;
 wire [7:0] cfg=8'hc3+{2'd0,channel[chip],4'd0};
 wire busy,done,ok;
 wire [7:0] r0,r1;
 wire [15:0] raw=r0[7]?16'd0:{r0,r1};
 integer i,pidx;
 initial for(i=0;i<3;i=i+1) begin channel[i]=0;pending[i]=0;age[i]=0;end
 function [15:0] filtered;
  input [15:0] oldv,newv;
  begin
   if(newv>=oldv) filtered=oldv+((newv-oldv)>>1)+((newv-oldv)&1);
   else filtered=oldv-((oldv-newv)>>1)-((oldv-newv)&1);
  end
 endfunction
 i2c_transaction #(34) bus(clk,req,op,7'h48+chip,
       state==5?8'd0:8'd1,cfg,8'he3,busy,done,ok,r0,r1,scl,sda);
 task advance;
  begin chip<=chip==2?0:chip+1'b1;state<=0;end
 endtask
 task failed;
  begin
   online[chip]<=0;pending[chip]<=0;
   if(chip==0) begin pitch_valid<=0;volume_valid<=0;end
   else if(chip==1) pressure_valid[3:0]<=0;
   else pressure_valid[6:4]<=0;
   advance;
  end
 endtask
 always @(posedge clk) begin
  for(i=0;i<3;i=i+1) if(pending[i]&&age[i]<270000) age[i]<=age[i]+1'b1;
  case(state)
   0:begin
    if(!pending[chip]) state<=1;
    else if(age[chip]>=40500) state<=3;
    else advance;
   end
   1:if(busy) state<=2;
   2:if(done) begin
    if(!ok) failed;
    else begin pending[chip]<=1;age[chip]<=0;online[chip]<=1;advance;end
   end
   3:if(busy) state<=4;
   4:if(done) begin
    if(!ok || (!r0[7]&&age[chip]>=270000)) failed;
    else if(r0[7]) state<=5;
    else advance;
   end
   5:if(busy) state<=6;
   6:if(done) begin
    if(!ok) failed;
    else begin
     online[chip]<=1; pending[chip]<=0;
     if(chip==0) begin
      if(channel[chip]==0) begin pitch<=pitch_valid?filtered(pitch,raw):raw;pitch_valid<=1;end
      else begin volume<=volume_valid?filtered(volume,raw):raw;volume_valid<=1;end
      channel[chip]<=channel[chip]==1?0:1;
     end else begin
      pidx=(chip==1)?channel[chip]:4+channel[chip];
      pressure[pidx*16+:16]<=pressure_valid[pidx]?filtered(pressure[pidx*16+:16],raw):raw;
      pressure_valid[pidx]<=1;
      channel[chip]<=(channel[chip]==(chip==1?3:2))?0:channel[chip]+1'b1;
     end
     advance;
    end
   end
   default:state<=0;
  endcase
 end
endmodule
