// Active-low momentary key. Synchronization + 10ms debounce; one step/press.
module oled_mode_key #(parameter integer DEBOUNCE=270000)(
 input wire clk,input wire key_n,output reg [1:0] mode=0
);
 reg [2:0] sync=3'b111;
 reg stable=1;
 reg [18:0] count=0;
 always @(posedge clk) begin
  sync<={sync[1:0],key_n};
  if(sync[2]==stable) count<=0;
  else if(count==DEBOUNCE-1) begin
   stable<=sync[2];count<=0;
   if(!sync[2]) mode<=(mode==2'd3)?2'd0:mode+2'd1;
  end else count<=count+1'b1;
 end
endmodule
