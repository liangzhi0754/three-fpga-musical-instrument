`timescale 1ns/1ps
// Digital I2C slave, not an optical/analog model. Exercise first-contact NACKs,
// STOP between pointer write and read, ID checks and actual enable registers.
module i2c_paj_model #(parameter integer WAKE_NACKS=2)(
 inout wire scl,inout wire sda,input wire present,input wire bad_id,
 input wire reject_mask,input wire [7:0] injected_gesture);
 reg drive_low=0;
 assign sda=drive_low?1'b0:1'bz;
 reg [7:0] received=0,reg_pointer=0,bank=0;
 reg [7:0] regs[0:511];
 integer i,contacts=0,reads=0,writes=0,missing_stop=0;
 reg active=0,ack_pending=0,ack_cycle=0,ack_seen=0,read_end=0;
 reg pointer_received=0,pointer_committed=0;
 integer mode=0,next_mode=0,bit_count=0;
 reg [7:0] sending=0;
 initial for(i=0;i<512;i=i+1) regs[i]=0;
 function [7:0] read_reg;
  input [7:0] address;
  begin
   if(bank==0 && address==0) read_reg=bad_id?8'h21:8'h20;
   else if(bank==0 && address==1) read_reg=8'h76;
   else if(bank==0 && address==8'h43)
    read_reg=(regs[9'h172][0] && regs[9'h041]==255)?injected_gesture:0;
   else read_reg=regs[{bank[0],address}];
  end
 endfunction
 always @(negedge sda) if(scl===1'b1&&!drive_low) begin
  active=1;mode=0;bit_count=0;received=0;pointer_received=0;
  ack_pending=0;ack_cycle=0;ack_seen=0;read_end=0;
 end
 always @(posedge sda) if(scl===1'b1&&!drive_low) begin
  if(active&&pointer_received) pointer_committed=1;
  active=0;
 end
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
     if(present&&received[7:1]==7'h73) begin
      contacts=contacts+1;
      if(contacts<=WAKE_NACKS) active=0;
      else if(received[0]&&!pointer_committed) begin
       missing_stop=missing_stop+1;active=0;
      end else begin
       ack_pending=1;next_mode=received[0]?3:1;
       if(!received[0]) pointer_committed=0;
       else reads=reads+1;
      end
     end else active=0;
    end else if(mode==1) begin
     reg_pointer=received;pointer_received=1;ack_pending=1;next_mode=2;
    end else begin
     pointer_received=0;pointer_committed=0;
     if(reject_mask&&bank==0&&reg_pointer==8'h41) active=0;
     else begin
      if(reg_pointer==8'hef) bank=received;
      else regs[{bank[0],reg_pointer}]=received;
      writes=writes+1;ack_pending=1;next_mode=2;
     end
    end
   end else bit_count=bit_count+1;
  end
 end
 always @(negedge scl) begin
  // Small response delay prevents an ideal zero-delay model masking edge bugs.
  if(!active) drive_low<=#1 0;
  else if(ack_pending) begin drive_low<=#1 1;ack_pending=0;ack_cycle=1;end
  else if(ack_seen) begin
   ack_seen=0;ack_cycle=0;mode=next_mode;bit_count=0;received=0;
   if(mode==3) begin sending=read_reg(reg_pointer);drive_low<=#1 !sending[7];end
   else drive_low<=#1 0;
  end else if(mode==3) begin
   if(read_end) begin read_end=0;mode=4;drive_low<=#1 0;end
   else drive_low<=#1 !sending[7-bit_count];
  end
 end
endmodule
