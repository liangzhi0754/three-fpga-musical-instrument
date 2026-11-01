// Per-key calibration is live and can be saved as part of the settings blob.
// Capture zero with all pads released, then full with each pad firmly pressed.
module pressure_mapper(
 input wire clk,input wire enable,input wire [111:0] raw,
 input wire [6:0] valid,input wire capture_zero,input wire capture_full,
 input wire [6:0] capture_mask,
 input wire restore,input wire [223:0] restored_calibration,
 output reg [111:0] gains={7{16'd256}},output wire [223:0] calibration
);
 reg [15:0] zero[0:6],full[0:6];
 reg [2:0] key=0;
 reg [1:0] state=0;
 reg [31:0] num=0,den=1;
 reg start=0;
 wire [31:0] ratio;
 wire busy,done;
 integer j;
 initial for(j=0;j<7;j=j+1) begin zero[j]=0;full[j]=26400;end
 genvar k;
 generate for(k=0;k<7;k=k+1) begin: export_cal
  assign calibration[k*32+:32]={full[k],zero[k]};
 end endgenerate
 unsigned_divider div(clk,start,num,den,ratio,busy,done);
 wire [15:0] value=raw[key*16+:16];
 wire increasing=full[key]>=zero[key];
 wire [15:0] span=increasing?full[key]-zero[key]:zero[key]-full[key];
 wire [15:0] delta=increasing?(value>zero[key]?value-zero[key]:16'd0):
                                 (value<zero[key]?zero[key]-value:16'd0);
 wire [15:0] target=(!enable||!valid[key]||span<128)?16'd256:
                         (ratio>=128)?16'd256:16'd128+ratio[15:0];
 reg [14:0] wait_count=0;
 always @(posedge clk) begin
  start<=0;
  if(restore) for(j=0;j<7;j=j+1) begin
   zero[j]<=restored_calibration[j*32+:16];full[j]<=restored_calibration[j*32+16+:16];
  end
  else begin
   if(capture_zero) for(j=0;j<7;j=j+1) if(valid[j]) zero[j]<=raw[j*16+:16];
   if(capture_full) for(j=0;j<7;j=j+1) if(valid[j]&&capture_mask[j]) full[j]<=raw[j*16+:16];
  end
  case(state)
   0:if(wait_count==2700) begin
    wait_count<=0;num<={9'd0,delta,7'd0};den<=span==0?32'd1:{16'd0,span};state<=1;
   end else wait_count<=wait_count+1'b1;
   1:begin start<=1;state<=2;end
   2:if(done) begin
    if(!enable||!valid[key]) gains[key*16+:16]<=256;
    else if(target>gains[key*16+:16])
     gains[key*16+:16]<=gains[key*16+:16]+((target-gains[key*16+:16]+3)>>2);
    else gains[key*16+:16]<=gains[key*16+:16]-((gains[key*16+:16]-target+3)>>2);
    key<=key==6?0:key+1'b1;state<=0;
   end
   default:state<=0;
  endcase
 end
endmodule
