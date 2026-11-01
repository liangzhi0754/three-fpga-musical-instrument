module debounced_button #(parameter integer DEBOUNCE=540000)(
 input wire clk,input wire pin_n,output reg pressed=0,
 output reg held=0,output reg long_press=0
);
 reg [1:0] sync=3;
 reg stable=1;
 reg [19:0] count=0;
 reg [25:0] held_count=0;
 always @(posedge clk) begin
  sync<={sync[0],pin_n};pressed<=0;long_press<=0;
  if(sync[1]==stable) count<=0;
  else if(count==DEBOUNCE-1) begin
   stable<=sync[1];count<=0;held<=!sync[1];
   if(!sync[1]) pressed<=1;
  end else count<=count+1'b1;
  if(!held) held_count<=0;
  else if(held_count<27000000) held_count<=held_count+1'b1;
  else if(held_count==27000000) begin long_press<=1;held_count<=held_count+1'b1;end
 end
endmodule
