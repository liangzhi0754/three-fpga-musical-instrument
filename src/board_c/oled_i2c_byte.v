// Transaction byte engine: open drain SCL/SDA, ACK sampling and stretch timeout.
// HALF=34 gives ~397kHz, excluding start/stop and local handshakes.
module oled_i2c_byte #(
 parameter integer HALF=34,parameter integer STRETCH_TIMEOUT=270000
)(
 input wire clk,input wire start,input wire [7:0] data,
 input wire first,input wire last,
 output reg busy=0,output reg done=0,output reg ack=0,
 inout wire scl,inout wire sda
);
 reg scl_low=0,sda_low=0;
 assign scl=scl_low?1'b0:1'bz;
 assign sda=sda_low?1'b0:1'bz;
 reg [2:0] sc=3'b111,sd=3'b111;
 reg [3:0] state=0;
 reg [7:0] shift=0;
 reg [3:0] bitno=0;
 reg end_byte=0;
 reg [18:0] timer=0,stretch=0;
 always @(posedge clk) begin
  sc<={sc[1:0],scl};sd<={sd[1:0],sda};done<=0;
  if(state==0) begin
   if(start) begin
    busy<=1;ack<=1;shift<=data;bitno<=0;end_byte<=last;
    timer<=0;stretch<=0;
    if(first) begin scl_low<=0;sda_low<=0;state<=1;end
    else begin scl_low<=1;sda_low<=!data[7];state<=3;end
   end
  end else if((state==1 || state==4 || state==7 || state==10) && !sc[2]) begin
   timer<=0;
   if(stretch==STRETCH_TIMEOUT-1) begin
    scl_low<=0;sda_low<=0;state<=0;busy<=0;done<=1;ack<=0;
   end else stretch<=stretch+1'b1;
  end else if(timer<HALF-1) timer<=timer+1'b1;
  else begin
   timer<=0;stretch<=0;
   case(state)
    1:begin sda_low<=1;state<=2;end // START: SDA falls while SCL high
    2:begin scl_low<=1;sda_low<=!shift[7];state<=3;end
    3:begin scl_low<=0;state<=4;end
    4:begin
     scl_low<=1;
     if(bitno==7) begin sda_low<=0;state<=6;end
     else begin bitno<=bitno+1'b1;shift<={shift[6:0],1'b0};
      sda_low<=!shift[6];state<=3;end
    end
    6:begin scl_low<=0;state<=7;end
    7:begin
     ack<=!sd[2];scl_low<=1;
     if(end_byte || sd[2]) begin sda_low<=1;state<=9;end
     else begin state<=0;busy<=0;done<=1;end
    end
    9:begin scl_low<=0;state<=10;end
    10:begin sda_low<=0;state<=11;end // STOP
    11:begin state<=0;busy<=0;done<=1;end
    default:state<=0;
   endcase
  end
 end
endmodule
