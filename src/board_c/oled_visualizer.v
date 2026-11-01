// WAVE / delay XY / seven note indicators / actual 256-point DFT.
// No new DSP blocks: coefficient products use a shared shift/add pipeline.
// Four-sample boxcar + decimation, Fs=52734.375/4=13183.59375Hz.
// Spectrum bins k=1..64, 51.4984Hz/bin, through 3295.90Hz.
module oled_visualizer #(
 parameter integer TRIGGER_WAIT=540000
)(
 input wire clk,input wire signed [15:0] sample,input wire sample_valid,
 input wire online,input wire [1:0] mode,input wire frame_done,
 input wire [9:0] read_addr,output wire [7:0] read_data,
 output reg ready=0,output reg captured_online=0,
 output reg [1:0] captured_mode=0,
 input wire [6:0] note_gates
);
 reg [7:0] pixels [0:1023];
 reg [6:0] captured_notes=0;
 reg signed [15:0] samples [0:255];
 reg signed [7:0] normalized [0:255],windowed [0:255];
 reg [26:0] magnitudes [0:63];
 assign read_data=pixels[read_addr];
 reg [5:0] state=0;
 reg [9:0] address=0;
 reg [7:0] index=0;
 reg [1:0] decimate=0;
 reg signed [17:0] box_sum=0;
 reg [8:0] fallback=0;
 reg [19:0] trigger_timer=0;
 reg negative=0;
 reg [15:0] peak=0;
 reg [3:0] gain_shift=0;
 wire tick=online?sample_valid:(fallback==511);
 wire signed [15:0] value=online?sample:16'sd0;
 wire signed [18:0] box_total=$signed(box_sum)+$signed(value);
 wire signed [18:0] average_wide=box_total>>>2;
 wire signed [15:0] average=average_wide[15:0];
 wire [15:0] abs_average=average[15]?(~average+16'd1):average;
 function [3:0] scale_shift;
  input [15:0] p;
  begin
   // Keep the largest visible signal between 64 and 127 in signed 8 bits.
   if(p>=32768) scale_shift=9;
   else if(p>=16384) scale_shift=8;
   else if(p>=8192) scale_shift=7;
   else if(p>=4096) scale_shift=6;
   else if(p>=2048) scale_shift=5;
   else if(p>=1024) scale_shift=4;
   else if(p>=512) scale_shift=3;
   else if(p>=256) scale_shift=2;
   else if(p>=128) scale_shift=1;
   else scale_shift=0;
  end
 endfunction
 wire signed [15:0] scaled_sample=$signed(samples[index])>>>gain_shift;
 wire signed [7:0] norm_value=(peak<32)?8'sd0:scaled_sample[7:0];
 // A single serial multiplier computes a signed 8-bit sample times two Q9
 // coefficients, or a Bartlett window. Coefficient magnitudes <=511.
 reg [7:0] trig_phase=0;
 wire signed [9:0] cos_value,sin_value;
 oled_trig_lut coefficients(trig_phase,cos_value,sin_value);
 reg signed [7:0] mult_x=0;
 reg signed [9:0] mult_a=0,mult_b=0;
 reg [9:0] mag_a=0,mag_b=0;
 reg signed [18:0] term=0,prod_a=0,prod_b=0;
 reg sign_a=0,sign_b=0;
 reg [3:0] mul_bit=0;
 reg [5:0] return_state=0;
 wire signed [18:0] result_a=sign_a?-prod_a:prod_a;
 wire signed [18:0] result_b=sign_b?-prod_b:prod_b;
 wire signed [18:0] window_result=result_a>>>7;
 reg signed [26:0] accum_a=0,accum_b=0;
 reg [6:0] bin=1;
 reg [26:0] max_magnitude=0;
 reg [5:0] spectrum_shift=0;
 wire [26:0] abs_a=accum_a[26]?-accum_a:accum_a;
 wire [26:0] abs_b=accum_b[26]?-accum_b:accum_b;
 // L1 complex magnitude avoids square/root and retains actual spectral peaks.
 wire [26:0] magnitude=abs_a+abs_b;
 reg [6:0] plot_x=0,previous_x=0,target_x=0;
 reg [5:0] plot_y=36,previous_y=36,target_y=36;
 reg [7:0] point=0;
 reg signed [8:0] error=0;
 reg [7:0] dx=0,dy=0;
 reg step_x=0,step_y=0;
 reg [5:0] after_plot=0;
 wire signed [9:0] twice_error=$signed(error)<<<1;
 reg [5:0] bar_height=0,bar_y=0;
 // Centre the significant frequency band, preserving bin order and heights.
 reg [5:0] first_bin=0,last_bin=63;
 reg found_band=0;
 reg signed [8:0] spectrum_offset=0;
 wire [6:0] band_mid={1'b0,first_bin}+{1'b0,last_bin};
 wire [26:0] visible_threshold=max_magnitude>>4;
 wire signed [9:0] bar_x_wide=$signed({3'b000,bin[5:0],bar_column})+
                                      $signed(spectrum_offset);
 wire [6:0] bar_x=bar_x_wide[6:0];
 wire [26:0] scaled_magnitude=magnitudes[bin[5:0]]>>spectrum_shift;
 reg bar_column=0;
 wire signed [7:0] current_norm=normalized[point];
 wire signed [7:0] delayed_norm=normalized[point-8'd12];
 wire signed [9:0] xy_x=10'sd64+($signed(current_norm)>>>1);
 wire signed [9:0] xy_y=10'sd36-($signed(delayed_norm)>>>2);
 wire signed [9:0] wave_y=10'sd36-($signed(current_norm)>>>2);
 function [5:0] clamp_y;
  input signed [9:0] v;
  begin clamp_y=(v<9)?6'd9:(v>62)?6'd62:v[5:0];end
 endfunction
 function [6:0] clamp_x;
  input signed [9:0] v;
  begin clamp_x=(v<1)?7'd1:(v>126)?7'd126:v[6:0];end
 endfunction
 // Header glyphs generated in hardware. Labels make current mode explicit.
 function [7:0] glyph;
  input [7:0] letter;input [2:0] col;
  reg [39:0] bits;
  begin
   case(letter)
    "A":bits=40'h7E1111117E; "C":bits=40'h3E41414122;
    "D":bits=40'h7F4141221C; "E":bits=40'h7F49494941;
    "F":bits=40'h7F09090901; "I":bits=40'h00417F4100;
    "G":bits=40'h3E41415132; "N":bits=40'h7F0408107F;
    "O":bits=40'h3E4141413E; "R":bits=40'h7F09192946;
    "7":bits=40'h0109710907;
    "L":bits=40'h7F40404040; "M":bits=40'h7F020C027F;
    "P":bits=40'h7F09090906; "S":bits=40'h4649494931;
    "T":bits=40'h01017F0101; "V":bits=40'h1F2040201F;
    "W":bits=40'h3F4038403F; "X":bits=40'h6314081463;
    "Y":bits=40'h0304780403; "0":bits=40'h3E4549513E;
    "3":bits=40'h2241494936; ".":bits=40'h0060600000;
    "K":bits=40'h7F08142241;
    default:bits=0;
   endcase
   case(col)
    0:glyph=bits[39:32];1:glyph=bits[31:24];2:glyph=bits[23:16];
    3:glyph=bits[15:8];4:glyph=bits[7:0];default:glyph=0;
   endcase
  end
 endfunction
 function [7:0] label_letter;
  input [1:0] m;input [4:0] c;
  begin
   label_letter=" ";
   if(m==0) case(c) 0:label_letter="W";1:label_letter="A";
    2:label_letter="V";3:label_letter="E";5:label_letter="A";6:label_letter="G";
    7:label_letter="C";endcase
   else if(m==1) case(c) 0:label_letter="X";1:label_letter="Y";
    3:label_letter="D";4:label_letter="E";5:label_letter="L";
    6:label_letter="A";7:label_letter="Y";endcase
   else if(m==2) case(c) 0:label_letter="N";1:label_letter="O";
    2:label_letter="T";3:label_letter="E";4:label_letter="S";
    6:label_letter="7";endcase
   else case(c) 0:label_letter="S";1:label_letter="P";2:label_letter="E";
    3:label_letter="C";5:label_letter="C";6:label_letter="E";
    7:label_letter="N";8:label_letter="T";9:label_letter="E";10:label_letter="R";endcase
  end
 endfunction
 // Seven equal 18-pixel cells at x=1..126, fixed Do..Si order.
 // A column is a fixed-height note indicator, not estimated spectral energy.
 function [7:0] note_pixels;
  input [9:0] a;input [6:0] mask;
  integer k,x,local_x; reg [7:0] first,second;
  begin
   note_pixels=0;x=a%128;
   for(k=0;k<7;k=k+1) begin
    if(x>=1+k*18 && x<19+k*18) begin
     local_x=x-(1+k*18);
     case(k)
      0:begin first="D";second="O";end
      1:begin first="R";second="E";end
      2:begin first="M";second="I";end
      3:begin first="F";second="A";end
      4:begin first="S";second="O";end
   5:begin first="L";second="A";end
      default:begin first="S";second="I";end
     endcase
     if(a[9:7]==7) begin
      if(local_x>=3 && local_x<8) note_pixels=glyph(first,local_x-3);
      else if(local_x>=9 && local_x<14) note_pixels=glyph(second,local_x-9);
     end else if(mask[k] && local_x>=3 && local_x<15) begin
      if(a[9:7]>=2 && a[9:7]<=5) note_pixels=8'hFF;
      else if(a[9:7]==6) note_pixels=8'h3F;
     end
    end
   end
  end
 endfunction
 always @(posedge clk) begin
  fallback<=fallback+1'b1;
  case(state)
   0:begin
    ready<=0;
    if(trigger_timer<TRIGGER_WAIT) trigger_timer<=trigger_timer+1'b1;
    if(mode==2) begin
     captured_mode<=2;captured_online<=online;
     captured_notes<=online?note_gates:7'd0;address<=0;state<=5;
    end else if(tick) begin
     negative<=value[15];
     if((negative&&!value[15]) || trigger_timer>=TRIGGER_WAIT) begin
      captured_mode<=mode;captured_online<=online;trigger_timer<=0;
      decimate<=0;box_sum<=0;index<=0;peak<=0;state<=1;
     end
    end
   end
   1:if(tick) begin
    if(decimate==3) begin
     decimate<=0;box_sum<=0;samples[index]<=average;
     if(abs_average>peak) peak<=abs_average;
     if(index==255) state<=2;else index<=index+1'b1;
    end else begin decimate<=decimate+1'b1;box_sum<=box_total[17:0];end
   end
   2:begin gain_shift<=scale_shift(peak);index<=0;state<=3;end
   3:begin
    normalized[index]<=norm_value;
    mult_x<=norm_value;
    mult_a<=(index<128)?$signed({2'b00,index}):$signed({2'b00,(8'd255-index)});
    mult_b<=0;return_state<=4;state<=40;
   end
   4:begin
    windowed[index]<=window_result[7:0];
    if(index==255) begin address<=0;state<=5;end
    else begin index<=index+1'b1;state<=3;end
   end
   5:begin
    if(address<128) begin
     if(address>=118 && address<=123) pixels[address]<=captured_online?8'h7E:8'h42;
     else pixels[address]<=glyph(label_letter(captured_mode,address/6),address%6);
    end else pixels[address]<=(captured_mode==2)?note_pixels(address,captured_notes):0;
    if(address==1023) begin
     if(captured_mode==2) begin ready<=1;state<=50;end
     else begin point<=(captured_mode==1)?8'd12:8'd0;state<=6;end
    end else address<=address+1'b1;
   end
   6:begin
    if(captured_mode==3) begin bin<=1;max_magnitude<=0;state<=20;end
    else begin
     target_x<=(captured_mode==1)?clamp_x(xy_x):point[6:0];
     target_y<=clamp_y((captured_mode==1)?xy_y:wave_y);
     state<=7;
    end
   end
   7:begin // Connect consecutive real sample points with Bresenham lines.
    if(point==((captured_mode==1)?12:0)) begin
     plot_x<=target_x;plot_y<=target_y;dx<=0;dy<=0;error<=0;
    end else begin
     plot_x<=previous_x;plot_y<=previous_y;
     dx<=(target_x>previous_x)?target_x-previous_x:previous_x-target_x;
     dy<=(target_y>previous_y)?target_y-previous_y:previous_y-target_y;
     step_x<=target_x>previous_x;step_y<=target_y>previous_y;
     error<=((target_x>previous_x)?{1'b0,target_x}-{1'b0,previous_x}:{1'b0,previous_x}-{1'b0,target_x})-
             ((target_y>previous_y)?{2'b00,target_y}-{2'b00,previous_y}:{2'b00,previous_y}-{2'b00,target_y});
    end
    after_plot<=8;state<=30;
   end
   8:begin
    previous_x<=target_x;previous_y<=target_y;
    if(point==((captured_mode==1)?255:127)) begin ready<=1;state<=50;end
    else begin point<=point+1'b1;state<=6;end
   end
   20:begin index<=0;trig_phase<=0;accum_a<=0;accum_b<=0;state<=21;end
   21:begin
    mult_x<=windowed[index];mult_a<=cos_value;mult_b<=sin_value;
    return_state<=22;state<=40;
   end
   22:begin
    accum_a<=accum_a+result_a;accum_b<=accum_b+result_b;
    trig_phase<=trig_phase+bin;
    if(index==255) state<=23;
    else begin index<=index+1'b1;state<=21;end
   end
   23:begin
    magnitudes[bin-1'b1]<=magnitude;
    if(magnitude>max_magnitude) max_magnitude<=magnitude;
    if(bin==64) state<=24;
    else begin bin<=bin+1'b1;state<=20;end
   end
   24:begin
    spectrum_shift<=0;bin<=0;found_band<=0;first_bin<=0;last_bin<=63;state<=28;
   end
   28:begin
    if(max_magnitude!=0 && magnitudes[bin[5:0]]>visible_threshold) begin
     if(!found_band) begin first_bin<=bin[5:0];found_band<=1;end
     last_bin<=bin[5:0];
    end
    if(bin==63) state<=29;else bin<=bin+1'b1;
   end
   29:begin
    // Centre of the two-pixel first/last bar range is 63.5 after translation.
    spectrum_offset<=found_band?(9'sd63-$signed({2'b00,band_mid})):9'sd0;
    state<=25;
   end
   25:if((max_magnitude>>spectrum_shift)>48) spectrum_shift<=spectrum_shift+1'b1;
      else begin bin<=0;state<=26;end
   26:begin
    bar_height<=scaled_magnitude[5:0];
    bar_y<=62;bar_column<=0;state<=27;
   end
   27:begin
    if(bar_height!=0 && bar_y>62-bar_height) begin
     // Clip out-of-screen faint bins; never wrap to the opposite edge.
     if(bar_x_wide>=0 && bar_x_wide<=127)
      pixels[{bar_y[5:3],bar_x}]<=
       pixels[{bar_y[5:3],bar_x}]|(8'b1<<bar_y[2:0]);
     if(bar_column) begin bar_column<=0;bar_y<=bar_y-1'b1;end
     else bar_column<=1;
    end else if(bin==63) begin ready<=1;state<=50;end
    else begin bin<=bin+1'b1;state<=26;end
   end
   30:begin
    pixels[{plot_y[5:3],plot_x}]<=pixels[{plot_y[5:3],plot_x}]|(8'b1<<plot_y[2:0]);
    if(plot_x==target_x && plot_y==target_y) state<=after_plot;
    else begin
     // Calculate the next point. Both conditions use the same old error.
     if(twice_error>-$signed({1'b0,dy}) && twice_error<$signed({1'b0,dx})) begin
      error<=error-$signed({1'b0,dy})+$signed({1'b0,dx});
      plot_x<=step_x?plot_x+1'b1:plot_x-1'b1;
      plot_y<=step_y?plot_y+1'b1:plot_y-1'b1;
     end else if(twice_error>-$signed({1'b0,dy})) begin
      error<=error-$signed({1'b0,dy});plot_x<=step_x?plot_x+1'b1:plot_x-1'b1;
     end else if(twice_error<$signed({1'b0,dx})) begin
      error<=error+$signed({1'b0,dx});plot_y<=step_y?plot_y+1'b1:plot_y-1'b1;
     end
    end
   end
   40:begin
    term<={{11{mult_x[7]}},mult_x};prod_a<=0;prod_b<=0;mul_bit<=0;
    sign_a<=mult_a[9];sign_b<=mult_b[9];
    mag_a<=mult_a[9]?-mult_a:mult_a;mag_b<=mult_b[9]?-mult_b:mult_b;
    state<=41;
   end
   41:begin
    if(mag_a[0]) prod_a<=prod_a+term;
    if(mag_b[0]) prod_b<=prod_b+term;
    term<=term<<<1;mag_a<=mag_a>>1;mag_b<=mag_b>>1;
    if(mul_bit==9) state<=return_state;else mul_bit<=mul_bit+1'b1;
   end
   50:if(frame_done) begin ready<=0;trigger_timer<=0;state<=0;end
   default:state<=0;
  endcase
 end
endmodule
