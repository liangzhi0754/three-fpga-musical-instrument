module spi_byte #(parameter integer HALF_PERIOD=4)(
 input wire clk,input wire start,input wire [7:0] data,input wire miso,
 output reg sck=0,output reg mosi=0,output reg [7:0] received=0,
 output reg busy=0,output reg done=0
);
 reg [7:0] shift=0,rx=0;
 reg [2:0] bitnum=0;
 reg [7:0] count=0;
 always @(posedge clk) begin
  done<=0;
  if(!busy) begin
   sck<=0;count<=0;
   if(start) begin busy<=1;shift<=data;rx<=0;mosi<=data[7];bitnum<=0;end
  end else if(count==HALF_PERIOD-1) begin
   count<=0;
   if(!sck) begin sck<=1;rx<={rx[6:0],miso};end
   else begin
    sck<=0;
    if(bitnum==7) begin received<=rx;busy<=0;done<=1;end
    else begin bitnum<=bitnum+1'b1;shift<={shift[6:0],1'b0};mosi<=shift[6];end
   end
  end else count<=count+1'b1;
 end
endmodule
