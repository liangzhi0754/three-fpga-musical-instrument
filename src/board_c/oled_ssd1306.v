// SSD1306 128x64, horizontal addressing. Probe 0x3C/0x3D on NACK.
// Top row: WAVE + audio-link square; plot area: true audio + dotted centre.
module oled_ssd1306 #(
 parameter integer BOOT_WAIT=2700000,parameter integer I2C_HALF=34
)(
 input wire clk,input wire ready,input wire captured_online,
 output wire [9:0] read_addr,input wire [7:0] read_data,
 output reg frame_done=0,inout wire scl,inout wire sda
);
 reg [3:0] state=0;
 reg [21:0] delay_count=0;
 reg address=0;
 reg [5:0] ci=0;
 reg [9:0] pixel=0;
 reg [7:0] data=0;
 reg first=0,last=0,start=0;
 wire busy,done,ack;
 oled_i2c_byte #(.HALF(I2C_HALF)) bus(clk,start,data,first,last,busy,done,ack,scl,sda);
 assign read_addr=pixel;
 function [7:0] init_byte;
  input [5:0] index;
  begin case(index)
   0:init_byte=8'hAE; 1:init_byte=8'hD5; 2:init_byte=8'h80;
   3:init_byte=8'hA8; 4:init_byte=8'h3F; 5:init_byte=8'hD3;
   6:init_byte=0; 7:init_byte=8'h40; 8:init_byte=8'h8D;
   9:init_byte=8'h14; 10:init_byte=8'h20; 11:init_byte=0;
   12:init_byte=8'hA1; 13:init_byte=8'hC8; 14:init_byte=8'hDA;
   15:init_byte=8'h12; 16:init_byte=8'h81; 17:init_byte=8'h7F;
   18:init_byte=8'hD9; 19:init_byte=8'hF1; 20:init_byte=8'hDB;
   21:init_byte=8'h40; 22:init_byte=8'hA4; 23:init_byte=8'hA6;
   24:init_byte=8'h21; 25:init_byte=0; 26:init_byte=8'h7F;
   27:init_byte=8'h22; 28:init_byte=0; 29:init_byte=7;
   default:init_byte=8'hAF;
  endcase end
 endfunction
 always @(posedge clk) begin
  start<=0;frame_done<=0;
  case(state)
   0:if(delay_count==BOOT_WAIT-1) begin delay_count<=0;state<=1;end
     else delay_count<=delay_count+1'b1;
   1:begin data<=address?8'h7A:8'h78;first<=1;last<=0;start<=1;state<=2;end
   2:if(done) begin
    if(!ack) begin address<=!address;delay_count<=0;state<=0;end
    else begin data<=0;first<=0;start<=1;state<=3;ci<=0;end
   end
   3:if(done) begin
    if(!ack) begin state<=0;delay_count<=0;end
    else begin data<=init_byte(ci);last<=(ci==30);start<=1;state<=4;end
   end
   4:if(done) begin
    if(!ack) begin state<=0;delay_count<=0;end
    else if(ci==30) state<=5;
    else begin ci<=ci+1'b1;state<=12;end
   end
   // Next command byte; keep the same command-stream transaction open.
   12:begin data<=init_byte(ci);last<=(ci==30);start<=1;state<=4;end
   5:if(ready) begin
    data<=address?8'h7A:8'h78;first<=1;last<=0;start<=1;state<=6;
   end
   6:if(done) begin
    if(!ack) begin state<=0;delay_count<=0;end
    else begin data<=8'h40;first<=0;start<=1;state<=7;pixel<=0;end
   end
   7:if(done) begin
    if(!ack) begin state<=0;delay_count<=0;end
    else state<=8;
   end
   8:begin data<=read_data;last<=(pixel==1023);start<=1;state<=9;end
   9:if(done) begin
    if(!ack) begin state<=0;delay_count<=0;end
    else if(pixel==1023) begin frame_done<=1;state<=11;end
    else begin pixel<=pixel+1'b1;state<=8;end
   end
   11:if(!ready) state<=5;
   default:state<=0;
  endcase
 end
endmodule
