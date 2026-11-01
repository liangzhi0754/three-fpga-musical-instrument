// 48 bits at 3.375MHz. Sample late in the low phase, after node/return sync.
module audio_link_master(
 input wire clk, input wire frame_start,
 input wire [7:0] expected_sequence, input wire [7:0] expected_version,
 input wire data_b, input wire data_c,
 output reg audio_sck=0, output reg audio_cs_n=1,
 output reg busy=0, output reg frame_done=0,
 output reg signed [23:0] sample_b=0, output reg signed [23:0] sample_c=0,
 output reg link_b_ok=0, output reg link_c_ok=0,
 output reg [2:0] error_b=0,output reg [2:0] error_c=0
);
 reg [1:0] b_sync=0,c_sync=0;
 reg [2:0] div_count=0;
 reg [5:0] bit_count=0;
 reg [47:0] b=0,c=0;
 reg [7:0] seq=0,ver=0;
 reg clocked=0;
 wire [47:0] nb={b[46:0],b_sync[1]}, nc={c[46:0],c_sync[1]};
 function [7:0] crc8;
  input [39:0] data;
  integer i; reg [7:0] z;
  begin
   z=0;
   for(i=39;i>=0;i=i-1)
    if(z[7]^data[i]) z=(z<<1)^8'h07; else z=z<<1;
   crc8=z;
  end
 endfunction
 wire [2:0] b_error={ver==0||nb[15:8]!=ver,nb[23:16]!=seq,crc8(nb[47:8])!=nb[7:0]};
 wire [2:0] c_error={ver==0||nc[15:8]!=ver,nc[23:16]!=seq,crc8(nc[47:8])!=nc[7:0]};
 always @(posedge clk) begin
  b_sync<={b_sync[0],data_b};c_sync<={c_sync[0],data_c};
  frame_done<=0;
  if(!busy) begin
   audio_sck<=0; audio_cs_n<=1; div_count<=0;clocked<=0;
   if(frame_start) begin
    busy<=1; audio_cs_n<=0; bit_count<=0; b<=0; c<=0;
    seq<=expected_sequence; ver<=expected_version;
   end
  end else begin
   div_count<=div_count+1'b1;
   if(div_count==3) begin audio_sck<=1;clocked<=1;end
   if(div_count==7) audio_sck<=0;
   if(div_count==2&&clocked) begin
    b<=nb;c<=nc;
    if(bit_count==47) begin
     sample_b<=nb[47:24]; sample_c<=nc[47:24];
     link_b_ok<=b_error==0;link_c_ok<=c_error==0;
     error_b<=b_error;error_c<=c_error;
     audio_cs_n<=1;audio_sck<=0; busy<=0; frame_done<=1;
    end else bit_count<=bit_count+1'b1;
   end
  end
 end
endmodule
