module uart_rx #(parameter integer DIV=234)(
 input wire clk,input wire rx,output reg [7:0] data=0,
 output reg valid=0,output reg framing_error=0
);
 reg [2:0] sync=7;
 reg [1:0] state=0;
 reg [8:0] timer=0;
 reg [2:0] bit_count=0;
 reg [7:0] shift=0;
 always @(posedge clk) begin
  sync<={sync[1:0],rx};valid<=0;framing_error<=0;
  case(state)
   0:if(!sync[2]) begin timer<=DIV/2;state<=1;end
   1:if(timer!=0) timer<=timer-1'b1;
     else if(!sync[2]) begin timer<=DIV-1;bit_count<=0;state<=2;end
     else state<=0;
   2:if(timer!=0) timer<=timer-1'b1;
     else begin
      shift[bit_count]<=sync[2];timer<=DIV-1;
      if(bit_count==7) state<=3;else bit_count<=bit_count+1'b1;
     end
   3:if(timer!=0) timer<=timer-1'b1;
     else begin
      if(sync[2]) begin data<=shift;valid<=1;end else framing_error<=1;
      state<=0;
     end
  endcase
 end
endmodule
