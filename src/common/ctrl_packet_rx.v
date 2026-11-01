// All receive logic runs on the node's local 27 MHz clock.
// A packet is committed atomically only after length, sync and CRC checks.
module ctrl_packet_rx(
 input wire clk, input wire sck, input wire cs_n, input wire mosi,
 output reg [511:0] packet=0, output reg valid=0,
 output reg begin_packet=0, output reg error=0,
 output reg debug_done=0,output reg [3:0] debug_reason=0,
 output reg [9:0] debug_count=0,output reg [23:0] debug_prefix=0,
 output reg [15:0] debug_crc_calc=0,output reg [15:0] debug_crc_wire=0
);
 reg [2:0] sc=0, cs=7, sd=0;
 reg [511:0] shift=0;
 reg [9:0] count=0;
 reg [15:0] crc=16'hffff;
 reg [23:0] first_bits=0;
 wire rise=sc[1]&&!sc[2];
 wire selected=!cs[1];
 wire selected_start=!cs[1]&&cs[2];
 wire selected_end=cs[1]&&!cs[2];
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
 always @(posedge clk) begin
  sc<={sc[1:0],sck}; cs<={cs[1:0],cs_n}; sd<={sd[1:0],mosi};
  valid<=0; begin_packet<=0; error<=0;debug_done<=0;
  if(selected_start) begin count<=0; shift<=0; begin_packet<=1;crc<=16'hffff;first_bits<=0;end
  else if(selected&&rise) begin
   if(count<512) begin
    shift<={shift[510:0],sd[1]}; count<=count+1'b1;
    if(count<24) first_bits<={first_bits[22:0],sd[1]};
    if(count>=16&&count<496) crc<=crc[15]^sd[1]?(crc<<1)^16'h1021:crc<<1;
   end
   else count<=513;
  end
  if(selected_end) begin
   debug_done<=1;debug_count<=count;debug_prefix<=first_bits;
   debug_crc_calc<=crc;debug_crc_wire<=shift[15:0];
   debug_reason<={crc!=shift[15:0],first_bits[7:0]!=8'd1,
                   first_bits[23:8]!=16'ha55a,count!=512};
   if(count==512 && shift[511:496]==16'ha55a &&
      shift[495:488]==8'd1 && crc==shift[15:0]) begin
    packet<=shift; valid<=1;
   end else error<=1;
  end
 end
endmodule
