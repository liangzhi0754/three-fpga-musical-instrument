// Non-destructive address-only I2C probe at about 16.7 kHz.
// SCL and SDA are exclusively open-drain. No register/data bytes are written.
// A short line test precedes scanning; do not run while another bus master is active.
module aux_probe #(parameter integer HALF_PERIOD=540,
 parameter integer HOLD_CLOCKS=270000, parameter integer RISE_TIMEOUT=270000)(
 input wire clk,input wire start,
 inout wire scl,inout wire sda,
 output reg busy=0,output reg done=0,
 output wire [159:0] diagnostic
);
 reg scl_low=0,sda_low=0;
 assign scl=scl_low?1'b0:1'bz;
 assign sda=sda_low?1'b0:1'bz;
 reg [1:0] scl_sync=3,sda_sync=3;
 reg [7:0] phase=0,flags=0,rounds=0,ack_count=0;
 reg [127:0] ack_map=0;
 reg [31:0] counter=0,stretch=0;
 reg [6:0] address=8;
 reg [3:0] bit_number=0;
 reg [7:0] address_byte=0;
 reg ack_seen=0,failed=0;
 assign diagnostic={ack_map,ack_count,rounds,flags,phase};
 always @(posedge clk) begin
  scl_sync<={scl_sync[0],scl};sda_sync<={sda_sync[0],sda};
  done<=0;
  if(!busy) begin
   scl_low<=0;sda_low<=0;
   if(start) begin
    busy<=1;phase<=1;counter<=0;stretch<=0;
    flags<=0;ack_map<=0;ack_count<=0;rounds<=rounds+1'b1;
    failed<=0;
   end
  end else case(phase)
   1:if(counter==HOLD_CLOCKS-1) begin
    flags[1:0]<={sda_sync[1],scl_sync[1]};counter<=0;
    if(!scl_sync[1]||!sda_sync[1]) begin failed<=1;phase<=40;end
    else begin scl_low<=1;phase<=2;end
   end else counter<=counter+1'b1;
   2:if(counter==HOLD_CLOCKS-1) begin
    flags[3:2]<={sda_sync[1],!scl_sync[1]};counter<=0;
    scl_low<=0;phase<=3;
   end else counter<=counter+1'b1;
   3:if(counter==HOLD_CLOCKS-1) begin
    counter<=0;sda_low<=1;phase<=4;
   end else counter<=counter+1'b1;
   4:if(counter==HOLD_CLOCKS-1) begin
    flags[5:4]<={scl_sync[1],!sda_sync[1]};counter<=0;
    sda_low<=0;phase<=5;
   end else counter<=counter+1'b1;
   5:if(counter==HOLD_CLOCKS-1) begin
    flags[6]<=scl_sync[1]&&sda_sync[1];counter<=0;
    if(flags[5:0]!=6'h3f||!scl_sync[1]||!sda_sync[1]) begin failed<=1;phase<=40;end
    else begin address<=8;phase<=10;end
   end else counter<=counter+1'b1;
   // Each numbered phase is a complete dwell period. Data changes occur well
   // after the falling SCL edge, not concurrently with it.
   10:if(counter==HALF_PERIOD-1) begin
    counter<=0;sda_low<=1;address_byte<={address,1'b0};phase<=11;
   end else counter<=counter+1'b1;
   11:if(counter==HALF_PERIOD-1) begin
    counter<=0;scl_low<=1;bit_number<=7;phase<=12;
   end else counter<=counter+1'b1;
   12:if(counter==HALF_PERIOD-1) begin
    counter<=0;sda_low<=!address_byte[bit_number];phase<=13;
   end else counter<=counter+1'b1;
   13:if(counter==HALF_PERIOD-1) begin
    counter<=0;scl_low<=0;stretch<=0;phase<=14;
   end else counter<=counter+1'b1;
   14:begin
    if(!scl_sync[1]) begin
     counter<=0;
     if(stretch==RISE_TIMEOUT-1) begin flags[7]<=1;failed<=1;phase<=40;end
     else stretch<=stretch+1'b1;
    end else if(counter==HALF_PERIOD-1) begin
     counter<=0;scl_low<=1;
     if(bit_number==0) phase<=15;
     else begin bit_number<=bit_number-1'b1;phase<=12;end
    end else counter<=counter+1'b1;
   end
   15:if(counter==HALF_PERIOD-1) begin
    counter<=0;sda_low<=0;phase<=16;
   end else counter<=counter+1'b1;
   16:if(counter==HALF_PERIOD-1) begin
    counter<=0;scl_low<=0;stretch<=0;phase<=17;
   end else counter<=counter+1'b1;
   17:begin
    if(!scl_sync[1]) begin
     counter<=0;
     if(stretch==RISE_TIMEOUT-1) begin flags[7]<=1;failed<=1;phase<=40;end
     else stretch<=stretch+1'b1;
    end else if(counter==HALF_PERIOD-1) begin
     counter<=0;ack_seen<=!sda_sync[1];scl_low<=1;phase<=18;
    end else counter<=counter+1'b1;
   end
   18:if(counter==HALF_PERIOD-1) begin
    counter<=0;sda_low<=1;phase<=19;
   end else counter<=counter+1'b1;
   19:if(counter==HALF_PERIOD-1) begin
    counter<=0;scl_low<=0;stretch<=0;phase<=20;
   end else counter<=counter+1'b1;
   20:begin
    if(!scl_sync[1]) begin
     counter<=0;
     if(stretch==RISE_TIMEOUT-1) begin flags[7]<=1;failed<=1;phase<=40;end
     else stretch<=stretch+1'b1;
    end else if(counter==HALF_PERIOD-1) begin
     counter<=0;sda_low<=0;phase<=21;
    end else counter<=counter+1'b1;
   end
   21:if(counter==HALF_PERIOD-1) begin
    counter<=0;
    if(ack_seen) begin ack_map[address]<=1;ack_count<=ack_count+1'b1;end
    if(address==7'h77) phase<=40;
    else begin address<=address+1'b1;phase<=10;end
   end else counter<=counter+1'b1;
   40:begin busy<=0;done<=1;scl_low<=0;sda_low<=0;phase<=failed?8'd254:8'd255;end
   default:begin failed<=1;phase<=40;end
  endcase
 end
endmodule
