// Synchronize the serial clock as data in local clk. No external-clock FFs.
module audio_link_slave(
 input wire clk,input wire audio_sck, input wire audio_cs_n,
 input wire signed [23:0] sample_value,
 input wire [7:0] sequence, input wire [7:0] control_version,
 output wire audio_data
);
 reg [2:0] sck_sync=0,cs_sync=7;
 wire rise=sck_sync[1]&&!sck_sync[2];
 reg [39:0] payload=0;
 reg [47:0] snapshot=0,shift=0;
 reg [5:0] count=0;
 function [7:0] crc8;
  input [39:0] data;
  integer i; reg [7:0] c;
  begin
   c=0;
   for(i=39;i>=0;i=i-1)
    if(c[7]^data[i]) c=(c<<1)^8'h07; else c=c<<1;
   crc8=c;
  end
 endfunction
 assign audio_data=shift[47];
 always @(posedge clk) begin
  sck_sync<={sck_sync[1:0],audio_sck};
  cs_sync<={cs_sync[1:0],audio_cs_n};
  payload<={sample_value,sequence,control_version};
  snapshot<={payload,crc8(payload)};
  if(cs_sync[2]) begin count<=0;shift<=0;end
  else if(rise) begin
   if(count==0) begin shift<=snapshot;count<=1;end
   else begin shift<={shift[46:0],1'b0};if(count<48) count<=count+1'b1;end
  end
 end
endmodule
