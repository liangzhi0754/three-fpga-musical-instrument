module unsigned_divider(
 input wire clk,input wire start,input wire [31:0] numerator,
 input wire [31:0] denominator,output reg [31:0] quotient=0,
 output reg busy=0,output reg done=0
);
 reg [31:0] q=0,d=1;
 reg [32:0] rem=0;
 reg [5:0] count=0;
 wire [32:0] nextrem={rem[31:0],q[31]};
 always @(posedge clk) begin
  done<=0;
  if(!busy) begin
   if(start) begin q<=numerator;d<=denominator;rem<=0;count<=0;busy<=1;end
  end else begin
   if(nextrem>={1'b0,d}) begin rem<=nextrem-d;q<={q[30:0],1'b1};end
   else begin rem<=nextrem;q<={q[30:0],1'b0};end
   if(count==31) begin
    quotient<=d==0?32'hffffffff:{q[30:0],nextrem>={1'b0,d}};
    busy<=0;done<=1;
   end else count<=count+1'b1;
  end
 end
endmodule
