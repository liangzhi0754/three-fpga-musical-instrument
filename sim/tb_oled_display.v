`timescale 1ns/1ps
module tb_oled_display;
 reg clk=0;always #5 clk=~clk;
 tri1 scl,sda;
 reg slave_low=0;
 assign sda=slave_low?1'b0:1'bz;
 reg available=0,active=0;
 reg [7:0] shift=0;
 integer count=0,byte_index=0,transactions=0,frames=0,fb=0,cmds=0;
 reg [7:0] control=0;
 reg [7:0] framebuffer [0:1023];
 wire [9:0] x;
 wire [7:0] input_byte=x[7:0]^8'hA5;
 wire done;
 reg ready=1;
 // Flat line at centre, not a preset sine: verifies raster and page order.
 oled_ssd1306 #(.BOOT_WAIT(100),.I2C_HALF(8)) dut(clk,ready,1'b1,x,input_byte,done,scl,sda);
 always @(negedge sda) if(scl===1'b1) begin active=1;count=0;byte_index=0;transactions=transactions+1;end
 always @(posedge sda) if(scl===1'b1) begin active=0;slave_low=0;end
 always @(posedge scl) if(active) begin
  if(count<8) begin shift={shift[6:0],sda};count=count+1;end
  else begin
   if(available) begin
    if(byte_index==0 && shift!==8'h7A) $fatal(1,"wrong detected address %h",shift);
    if(byte_index==1) control=shift;
    if(byte_index>=2 && control==8'h00) begin
     if(shift!==dut.init_byte(cmds)) $fatal(1,"wrong initialization byte %d: %h",cmds,shift);
     cmds=cmds+1;
    end
    if(byte_index>=2 && control==8'h40) begin
     framebuffer[fb]=shift;fb=fb+1;
    end
   end
   byte_index=byte_index+1;count=0;
  end
 end
 always @(negedge scl) if(active) begin
  if(count==8) slave_low=available;
  else slave_low=0;
 end
 integer i;
 initial begin
  // No display at 0x3C: NACK and STOP, then accept the next probe at 0x3D.
  wait(transactions==1);wait(!active);available=1;
  wait(done);#1;
  if(fb!=1024||cmds!=31) $fatal(1,"wrong byte counts %d %d",fb,cmds);
  for(i=0;i<1024;i=i+1) begin
   if(framebuffer[i] !== ((i%256)^8'hA5)) $fatal(1,"framebuffer transfer %d",i);
  end
  $display("PASS SSD1306 wire-level I2C: NACK, 0x3D retry, 31 init bytes, 1024 pixel bytes, external framebuffer byte order");$finish;
 end
 initial begin #10000000;$fatal(1,"display timeout state=%d bytes=%d commands=%d",dut.state,fb,cmds);end
endmodule
