// Fixed 64-byte control snapshot, MSB first, 27 MHz / 26 serial clock.
// Start only at a known offset within the source sample frame.
module ctrl_packet_tx(
 input wire clk, input wire start, input wire [511:0] packet,
 output reg sck=0, output reg mosi=0, output reg cs_n=1,
 output reg busy=0, output reg done=0
);
 reg [511:0] shift=0;
 reg [8:0] bits=0;
 reg [3:0] divider=0;
 reg [15:0] crc=16'hffff;
 always @(posedge clk) begin
  done<=0;
  if(!busy) begin
   sck<=0; cs_n<=1; divider<=0;
   if(start) begin
    shift<=packet; mosi<=packet[511]; cs_n<=0;
    busy<=1; bits<=0;crc<=16'hffff;
   end
  end else if(divider==12) begin
   divider<=0;
   if(!sck) begin
    sck<=1;
    if(bits>=16 && bits<496)
     crc<=crc[15]^mosi?(crc<<1)^16'h1021:crc<<1;
   end
   else begin
    sck<=0;
    if(bits==511) begin busy<=0; cs_n<=1; done<=1; end
    else if(bits==495) begin shift<={crc,496'd0};mosi<=crc[15];bits<=bits+1'b1;end
    else begin shift<={shift[510:0],1'b0}; mosi<=shift[510]; bits<=bits+1'b1; end
   end
  end else divider<=divider+1'b1;
 end
endmodule
