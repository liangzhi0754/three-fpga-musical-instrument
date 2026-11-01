module board_b_top(
 input wire clk,input wire ctrl_sck,input wire ctrl_mosi,input wire ctrl_cs_n,
 input wire frame_toggle,input wire audio_sck,input wire audio_cs_n,
 output wire audio_data,output wire [5:0] diag_led_n,output wire diag_uart_tx
);
 wire legacy_led,packet_valid,packet_error,locked;
 wire report_done;wire [3:0] reason;wire [9:0] count;
 wire [23:0] prefix;wire [15:0] calc_crc,wire_crc;
 node_top #(0,3,1) node(.clk(clk),.ctrl_sck(ctrl_sck),.ctrl_mosi(ctrl_mosi),
  .ctrl_cs_n(ctrl_cs_n),.frame_toggle(frame_toggle),.audio_sck(audio_sck),
  .audio_cs_n(audio_cs_n),.audio_data(audio_data),.led(legacy_led),
  .debug_packet_valid(packet_valid),.debug_packet_error(packet_error),
  .debug_locked(locked),.debug_done(report_done),.debug_reason(reason),
  .debug_count(count),.debug_prefix(prefix),.debug_crc_calc(calc_crc),.debug_crc_wire(wire_crc));
 link_diagnostics indicators(clk,ctrl_sck,frame_toggle,packet_valid,
                             packet_error,locked,diag_led_n);
 packet_diagnostic_uart #(.BOARD_ID(8'h42)) report(clk,ctrl_sck,ctrl_cs_n,
  ctrl_mosi,frame_toggle,locked,report_done,reason,count,prefix,calc_crc,wire_crc,diag_uart_tx);
endmodule
