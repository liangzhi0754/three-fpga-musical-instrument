`timescale 1ns/1ps
// Digital protocol model only: register-level boot, SPAD and calibration responses.
// This does not model optical accuracy or certify the vendor tuning sequence.
module i2c_vl53_model(inout wire scl,inout wire sda,
 input wire present,input wire bad_id,input wire poll_stuck);
 reg drive_low=0;
 assign sda=drive_low?1'b0:1'bz;
 reg [7:0] received=0,reg_pointer=0,bank=0,value=0;
 reg [7:0] regs[0:511];
 integer i,transactions=0;
 reg active=0,ack_pending=0,ack_cycle=0,ack_seen=0,read_end=0;
 integer mode=0,next_mode=0,bit_count=0;
 reg [7:0] sending=0;
 initial for(i=0;i<512;i=i+1) regs[i]=0;
 function [7:0] read_reg;
  input [7:0] address;
  begin
   if(bank==0&&address==8'hc0) read_reg=bad_id?8'hea:8'hee;
   else if(bank==7&&address==8'h83) read_reg=poll_stuck?0:1;
   else if(bank==7&&address==8'h92) read_reg=8'h85;
   else if(bank==0&&address>=8'hb0&&address<=8'hb5) read_reg=8'hff;
   else if(bank==0&&address==8'h13) read_reg=poll_stuck?0:7;
   else if(bank==0&&address==8'h14) read_reg=8'h58;
   else if(bank==0&&address==8'h1e) read_reg=0;
   else if(bank==0&&address==8'h1f) read_reg=200;
   else read_reg=regs[{bank[0],address}];
  end
 endfunction
 always @(negedge sda) if(scl===1'b1&&!drive_low) begin
  active=1;mode=0;bit_count=0;received=0;
  ack_pending=0;ack_cycle=0;ack_seen=0;read_end=0;
 end
 always @(posedge sda) if(scl===1'b1&&!drive_low) active=0;
 always @(posedge scl) if(active) begin
  if(ack_cycle) ack_seen=1;
  else if(mode==3) begin
   if(bit_count==7) read_end=1;else bit_count=bit_count+1;
  end else if(mode==4) begin
   if(sda) active=0;
   else begin reg_pointer=reg_pointer+1'b1;next_mode=3;ack_seen=1;end
  end else begin
   received={received[6:0],sda};
   if(bit_count==7) begin
    bit_count=0;
    if(mode==0) begin
     if(present&&received[7:1]==7'h29) begin
      transactions=transactions+1;ack_pending=1;next_mode=received[0]?3:1;
     end else active=0;
    end else if(mode==1) begin
     reg_pointer=received;ack_pending=1;next_mode=2;
    end else begin
     if(reg_pointer==8'hff) bank=received;
     else regs[{bank[0],reg_pointer}]=received;
     ack_pending=1;next_mode=2;
    end
   end else bit_count=bit_count+1;
  end
 end
 always @(negedge scl) begin
  if(!active) drive_low=0;
  else if(ack_pending) begin drive_low=1;ack_pending=0;ack_cycle=1;end
  else if(ack_seen) begin
   ack_seen=0;ack_cycle=0;mode=next_mode;bit_count=0;received=0;
   if(mode==3) begin sending=read_reg(reg_pointer);drive_low=!sending[7];end
   else drive_low=0;
  end else if(mode==3) begin
   if(read_end) begin read_end=0;mode=4;drive_low=0;end
   else drive_low=!sending[7-bit_count];
  end
 end
endmodule
