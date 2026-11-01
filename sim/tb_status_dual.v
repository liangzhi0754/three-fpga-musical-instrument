`timescale 1ns/1ps
module tb_status_dual;
 reg clk=0;always #5 clk=~clk;
 wire tx,pc_tx;
 reg [7:0] phone_seq=8'h41,pc_seq=8'h82;
 wire [7:0] phone_data,pc_data;
 wire phone_valid,pc_valid,phone_err,pc_err;
 reg [7:0] ph[0:107],pc[0:107];
 integer pi=0,ci=0,i,sum1,sum2;
 reg first=1;
 status_dual dut(.clk(clk),.gates(7'h41),.timbre(2'd3),.pitch(16'd1234),.volume(16'd5678),
 .sensor_flags(4'hf),.features(3'd6),.ads_online(3'd7),.aux_online(2'd2),.link_ok(2'd3),
 .store_status(4'd0),.store_flags(4'd4),.command_sequence(phone_seq),.distance(16'hc123),
 .gesture(8'd2),.pressure_valid(7'h7f),.pressure(112'd0),.link_counters(288'd0),
 .aux_diagnostic(112'd0),.probe_diagnostic(160'd0),.pc_command_sequence(pc_seq),
 .tx(tx),.pc_tx(pc_tx),.encoder_diagnostic(14'h2d76),.store_fault_code(4'd3),
 .waveform_valid(1'b0),.waveform_sample(16'sd0));
 uart_rx r1(clk,tx,phone_data,phone_valid,phone_err);
 uart_rx r2(clk,pc_tx,pc_data,pc_valid,pc_err);
 always @(posedge clk) begin
  if(phone_err||pc_err) $fatal(1,"UART framing error");
  if(phone_valid) begin ph[pi]=phone_data;pi=pi+1;end
  if(pc_valid) begin pc[ci]=pc_data;ci=ci+1;end
 end
 task check_frame;
 input [7:0] expected_ph,expected_pc;
 begin
  sum1=0;sum2=0;
  for(i=0;i<108;i=i+1) begin
   if(i!=10&&i!=12&&i!=13&&i!=15&&i!=17&&i!=106&&pc[i]!==ph[i]) $fatal(1,"state differs at byte %d",i);
   if(i>=2&&i<106) begin sum1=(sum1+ph[i])&255;sum2=(sum2+pc[i])&255;end
  end
  if(ph[0]!=8'haa||ph[1]!=8'h59||ph[107]!=13) $fatal(1,"AA59 compatibility");
  if(pc[10]!=8'h6f||pc[12]!=8'hbf||pc[13]!=8'hb6||
     ph[10]!=8'h0f||ph[12]!=8'h07||ph[13]!=8'h02)
   $fatal(1,"encoder diagnostic packing/low status fields corrupted");
  if(pc[15]!=8'h30 || ph[15]!=0) $fatal(1,"storage fault PC extension/phone compatibility");
  if(ph[17]!=expected_ph||pc[17]!=expected_pc||ph[106]!=sum1||pc[106]!=sum2)
   $fatal(1,"per-source receipt or checksum");
 end endtask
 initial begin
  wait(pi>20); // Change live seq mid-frame: both packets must stay snapshotted.
  phone_seq=8'h52;pc_seq=8'h93;
  wait(pi==108&&ci==108);@(negedge clk);
  check_frame(8'h41,8'h82);pi=0;ci=0;
  wait(pi==108&&ci==108);@(negedge clk);
  check_frame(8'h52,8'h93);
  $display("PASS dual AA59: 108 bytes, same state, independent snapshotted receipts and checksums on both UARTs");
  $finish;
 end
 initial begin #9000000;$fatal(1,"dual status timeout");end
endmodule
