// Shared synchronous page RAM. Host may write only while the SPI engine is idle.
module flash_page(
 input wire clk,input wire start,input wire [1:0] operation,
 input wire [23:0] address,input wire [7:0] host_address,
 input wire host_write,input wire [7:0] host_data,output reg [7:0] host_q=0,
 input wire miso,output wire sck,output wire mosi,output reg cs_n=1,
 output reg [23:0] jedec_id=0,output reg busy=0,output reg done=0,output reg error=0
);
 reg [7:0] memory[0:255];
 reg [7:0] spi_q=0;
 reg [1:0] op=0;
 reg [23:0] addr=0;
 reg [3:0] state=0,resume=0;
 reg [7:0] index=0,command=0,tx=0;
 reg launch=0;
 wire byte_busy,byte_done;
 wire [7:0] rx;
 reg [26:0] watchdog=0;
 reg [9:0] gap=0;
 // 1.6875 MHz at 27 MHz; more margin for external module jumper wires.
 spi_byte #(.HALF_PERIOD(8)) byte_engine(clk,launch,tx,miso,sck,mosi,rx,byte_busy,byte_done);
 always @(posedge clk) begin
  if(host_write&&!busy) begin memory[host_address]<=host_data;host_q<=host_data;end
  else host_q<=memory[host_address];
  if(state==9&&op==0) begin memory[index]<=rx;spi_q<=rx;end
  else spi_q<=memory[index];
 end
 task transfer;
  input [7:0] value;input [3:0] nextstate;
  begin tx<=value;launch<=1;resume<=nextstate;state<=14;end
 endtask
 always @(posedge clk) begin
  done<=0;launch<=0;
  if(busy) watchdog<=watchdog+1'b1;else watchdog<=0;
  case(state)
   0:if(start) begin op<=operation;addr<=address;busy<=1;error<=0;gap<=16;state<=1;end
   1:if(gap!=0) gap<=gap-1'b1;
     else begin
      cs_n<=0;index<=0;
      if(op==1||op==2) transfer(8'h06,2);
      else begin command<=op==3?8'h9f:8'h03;state<=4;end
     end
   2:begin cs_n<=1;gap<=16;state<=3;end
   3:if(gap!=0) gap<=gap-1'b1;
     else begin cs_n<=0;command<=op==1?8'h02:8'h20;state<=4;end
   4:begin transfer(command,5);index<=0;end
   5:if(op==3) transfer(8'hff,8);else transfer(addr[23:16],6);
   6:if(index==0) begin transfer(addr[15:8],6);index<=1;end
     else begin transfer(addr[7:0],7);index<=0;end
   7:if(op==2) begin cs_n<=1;gap<=270;state<=10;end
     else transfer(op==1?spi_q:8'hff,9);
   8:begin
    jedec_id<={jedec_id[15:0],rx};
    if(index==2) begin cs_n<=1;busy<=0;done<=1;state<=0;end
    else begin index<=index+1'b1;transfer(8'hff,8);end
   end
   9:if(index==255) begin
      cs_n<=1;
      if(op==0) begin busy<=0;done<=1;state<=0;end
      else begin gap<=270;state<=10;end
     end else begin index<=index+1'b1;state<=13;end
   13:state<=7;
   10:if(gap!=0) gap<=gap-1'b1;else begin cs_n<=0;transfer(8'h05,11);end
   11:transfer(8'hff,12);
   12:begin cs_n<=1;
    if(rx[0]) begin gap<=270;state<=10;end
    else begin busy<=0;done<=1;state<=0;end
   end
   14:if(byte_busy) state<=15;
   15:if(byte_done) state<=resume;
   default:state<=0;
  endcase
  if(busy&&watchdog==27'd53999999) begin cs_n<=1;state<=0;busy<=0;done<=1;error<=1;end
 end
endmodule
