// Network byte order. CRC16/CCITT-FALSE covers bytes 2..61.
// b3 revision; b4..5 activation frame; b6..7 send frame;
// b8 flags (pressure,distance,gesture,bit7 reset);
// b9 gate; b10 timbre; b11 reserved; b12..13 raw pitch;
// b14..15 raw volume; b16..29 seven unsigned Q8 gains;
// b30..33 signed vibrato Q20 fraction; b34..35 distance;
// b36 gesture; b37..61 reserved; b62..63 CRC.
module control_pack(
 input wire [7:0] revision, input wire [15:0] activation_frame,
 input wire [15:0] origin_frame, input wire [7:0] flags,
 input wire [6:0] gates, input wire [2:0] timbre,
 input wire [15:0] pitch, input wire [15:0] volume,
 input wire [111:0] gains, input wire signed [31:0] vibrato,
 input wire [15:0] distance, input wire [7:0] gesture,
 output reg [511:0] packet
);
 function [15:0] crc16;
  input [479:0] data;
  integer i; reg [15:0] c;
  begin
   c=16'hffff;
   for(i=479;i>=0;i=i-1)
    if(c[15]^data[i]) c=(c<<1)^16'h1021; else c=c<<1;
   crc16=c;
  end
 endfunction
 integer j;
 always @* begin
  packet=0;
  packet[511-0*8-:16]=16'ha55a;
  packet[511-2*8-:8]=1;
  packet[511-3*8-:8]=revision;
  packet[511-4*8-:16]=activation_frame;
  packet[511-6*8-:16]=origin_frame;
  packet[511-8*8-:8]=flags;
  packet[511-9*8-:8]={1'b0,gates};
  packet[511-10*8-:8]={5'd0,timbre};
  packet[511-12*8-:16]=pitch;
  packet[511-14*8-:16]=volume;
  for(j=0;j<7;j=j+1) packet[511-(16+j*2)*8-:16]=gains[j*16+:16];
  packet[511-30*8-:32]=vibrato;
  packet[511-34*8-:16]=distance;
  packet[511-36*8-:8]=gesture;
  // CRC is inserted bit-serially by ctrl_packet_tx, avoiding a long XOR path.
  packet[15:0]=0;
 end
endmodule
