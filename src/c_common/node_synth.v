module node_synth #(
 parameter integer FIRST_KEY=0, parameter integer KEY_COUNT=3,
 parameter integer FIRST_HARMONIC=1,
 parameter integer PIPELINE_PITCH=0
)(
 input wire clk, input wire reset, input wire sample_tick,
 input wire [6:0] gates, input wire [2:0] timbre,
 input wire [15:0] pitch, input wire [111:0] gains,
 input wire signed [31:0] vibrato,
 output wire signed [23:0] partial_sum
);
 wire [15:0] limited=(pitch>26400)?16'd26400:pitch;
 wire signed [31:0] offset=($signed({1'b0,limited})-17'sd13200)*32'sd1024;
 wire [223:0] steps;
 function [31:0] base;
  input integer k;
  begin case(k)
   0:base=21308210; 1:base=23917636; 2:base=26846653;
   3:base=28442981; 4:base=31926153; 5:base=35835935;
   default:base=40224452;
  endcase end
 endfunction
 genvar n;
 generate for(n=0;n<7;n=n+1) begin: pitch_calc
  wire signed [31:0] v=$signed(base(n))+offset;
  // The bounded +/-30-cent control fits signed 16 bits. Avoid inferring
  // seven unnecessary full 32x32 multipliers on each synthesis node.
  wire signed [15:0] bounded_vibrato=vibrato>32767?16'sd32767:
                                    vibrato< -32768?-16'sd32768:vibrato[15:0];
  if(PIPELINE_PITCH) begin: pipelined
   reg signed [31:0] base_step=base(n),delayed_base=base(n);
   reg signed [15:0] depth=0;
   reg signed [47:0] product=0;
   reg signed [63:0] modulated=base(n);
   reg [31:0] result=base(n);
   always @(posedge clk) begin
    base_step<=v;depth<=bounded_vibrato;
    product<=base_step*depth;delayed_base<=base_step;
    modulated<=$signed({{32{delayed_base[31]}},delayed_base})+
               ($signed({{16{product[47]}},product})>>>20);
    result<=(modulated<1)?32'd1:modulated[31:0];
   end
   assign steps[n*32+:32]=result;
  end else begin: original
   wire signed [47:0] product=v*bounded_vibrato;
   wire signed [63:0] modulated=v+(product>>>20);
   assign steps[n*32+:32]=(modulated<1)?32'd1:modulated[31:0];
  end
 end endgenerate
 wire [KEY_COUNT*24-1:0] voice_terms;
 generate for(n=0;n<KEY_COUNT;n=n+1) begin: ordinary
  localparam integer K=FIRST_KEY+n;
  wire signed [15:0] raw;
  reg [8:0] held_gain=256;
  reg signed [25:0] scaled=0;
  always @(posedge clk) begin
   if(reset) held_gain<=256;
   else if(sample_tick&&gates[K]) held_gain<=gains[K*16+:9];
   scaled<=raw*$signed({1'b0,held_gain});
  end
  synth_voice voice(clk,reset,sample_tick,gates[K],timbre[1:0],steps[K*32+:32],raw);
  assign voice_terms[n*24+:24]=scaled>>>8;
 end endgenerate
 wire signed [23:0] string_sum;
 poly_string_bank #(FIRST_HARMONIC) strings(clk,reset,sample_tick,gates,timbre,
                                          steps,gains,string_sum);
 integer j; reg signed [23:0] ordinary_sum;
 always @* begin
  ordinary_sum=0;
  for(j=0;j<KEY_COUNT;j=j+1) ordinary_sum=ordinary_sum+$signed(voice_terms[j*24+:24]);
 end
 assign partial_sum=(timbre>=3)?string_sum:ordinary_sum;
endmodule
