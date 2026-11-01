// Wide unscaled partial sum. Final division by two is done once on Board A.
module normal_reference_additive16 #(
 parameter integer START_HARMONIC=1
)(
 input wire clk,input wire reset,input wire sample_tick,
 input wire gate,input wire [31:0] phase_step,
 output wire signed [23:0] sample
);
 wire [383:0] terms;
 genvar k;
 generate for(k=0;k<16;k=k+1) begin: component
  localparam integer H=START_HARMONIC+k;
  localparam integer SHIFT=(H==1)?2:(H<=3)?3:(H<=6)?4:
                           (H<=8)?5:(H<=12)?6:(H<=16)?7:(H<=24)?8:9;
  wire [31:0] step=phase_step*H;
  wire signed [15:0] raw;
  additive_component osc(clk,reset,sample_tick,gate,step,raw);
  assign terms[k*24+:24]=$signed({{8{raw[15]}},raw}) >>> SHIFT;
 end endgenerate
 integer j;
 reg signed [23:0] sum;
 always @* begin
  sum=0;
  for(j=0;j<16;j=j+1) sum=sum+$signed(terms[j*24+:24]);
 end
 assign sample=sum;
endmodule
