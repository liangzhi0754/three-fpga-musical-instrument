// Retains the verified electrode mapping and three-successful-poll debounce.
module touch_controller(
 input wire clk,inout wire scl,inout wire sda,
 output reg [6:0] gates=0,output reg online=0
);
 reg [2:0] state=0;
 reg [5:0] index=0;
 reg [23:0] wait_count=0;
 reg [7:0] regaddr,value;
 wire busy,done,ok;
 wire [7:0] r0,r1;
 wire [6:0] selected={r0[0],r0[2],r0[4],r0[6],r1[0],r1[2],r1[3]};
 reg [1:0] debounce[0:6];
 integer k;
 initial for(k=0;k<7;k=k+1) debounce[k]=0;
 always @* begin
  regaddr=0; value=0;
  if(index>=9&&index<=32) begin
   regaddr=8'h41+(index-9); value=index[0]?6:3;
  end else case(index)
   0:begin regaddr=8'h5e;value=0;end
   1:begin regaddr=8'h2b;value=1;end
   2:begin regaddr=8'h2c;value=1;end
   3:begin regaddr=8'h2d;value=0;end
   4:begin regaddr=8'h2e;value=0;end
   5:begin regaddr=8'h2f;value=1;end
   6:begin regaddr=8'h30;value=1;end
   7:begin regaddr=8'h31;value=8'hff;end
   8:begin regaddr=8'h32;value=2;end
   33:begin regaddr=8'h5b;value=0;end
   34:begin regaddr=8'h5c;value=8'h10;end
   35:begin regaddr=8'h5d;value=8'h20;end
   default:begin regaddr=8'h5e;value=8'h8c;end
  endcase
 end
 i2c_transaction bus(clk,state==1||state==3,state==3?2'd2:2'd0,
     7'h5a,state==3?8'h00:regaddr,value,8'd0,busy,done,ok,r0,r1,scl,sda);
 always @(posedge clk) case(state)
  0:begin
   if(wait_count==539999) begin wait_count<=0;index<=0;state<=1;end
   else wait_count<=wait_count+1'b1;
  end
  1:if(busy) state<=2;
  2:if(done) begin
   if(!ok) begin online<=0;gates<=0;state<=0;end
   else if(index==36) begin online<=1;state<=3;end
   else begin index<=index+1'b1;state<=1;end
  end
  3:if(busy) state<=4;
  4:if(done) begin
   if(ok) begin
    online<=1;
    for(k=0;k<7;k=k+1)
     if(selected[k]==gates[k]) debounce[k]<=0;
     else if(debounce[k]==2) begin gates[k]<=selected[k];debounce[k]<=0;end
     else debounce[k]<=debounce[k]+1'b1;
    state<=3;
   end else begin
    online<=0;gates<=0;state<=0;wait_count<=0;
    for(k=0;k<7;k=k+1) debounce[k]<=0;
   end
  end
  default:state<=0;
 endcase
endmodule
