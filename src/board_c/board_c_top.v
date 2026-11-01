module board_c_top(
 input wire clk,input wire ctrl_sck,input wire ctrl_mosi,input wire ctrl_cs_n,
 input wire frame_toggle,input wire audio_sck,input wire audio_cs_n,
 output wire audio_data,output wire [5:0] diag_led_n,output wire diag_uart_tx,
 input wire monitor_bclk,input wire monitor_lrck,input wire monitor_din,
 inout wire oled_scl,inout wire oled_sda,input wire display_key,
 input wire guide_key,output wire [6:0] note_led
);
 wire [6:0] display_notes,control_notes;
 wire legacy_led,packet_valid,packet_error,locked;
 wire report_done;wire [3:0] reason;wire [9:0] count;
 wire [23:0] prefix;wire [15:0] calc_crc,wire_crc;
 node_top #(3,4,17,8,1) node(.clk(clk),.ctrl_sck(ctrl_sck),.ctrl_mosi(ctrl_mosi),
  .ctrl_cs_n(ctrl_cs_n),.frame_toggle(frame_toggle),.audio_sck(audio_sck),
  .audio_cs_n(audio_cs_n),.audio_data(audio_data),.led(legacy_led),
  .debug_packet_valid(packet_valid),.debug_packet_error(packet_error),
  .debug_locked(locked),.debug_done(report_done),.debug_reason(reason),
  .debug_count(count),.debug_prefix(prefix),.debug_crc_calc(calc_crc),.debug_crc_wire(wire_crc),.display_notes(display_notes),.control_notes(control_notes));
 // Visual aid observes validated commands; it never changes audio or packets.
 led_note_guide guide(.clk(clk),.key_n(guide_key),.link_online(locked),
  .notes(control_notes),.leds(note_led));
 link_diagnostics indicators(clk,ctrl_sck,frame_toggle,packet_valid,
                             packet_error,locked,diag_led_n);
 packet_diagnostic_uart #(.BOARD_ID(8'h43)) report(clk,ctrl_sck,ctrl_cs_n,
  ctrl_mosi,frame_toggle,locked,report_done,reason,count,prefix,calc_crc,wire_crc,diag_uart_tx);
 wire signed [15:0] monitor_sample;
 wire monitor_valid,monitor_online,trace_ready,frame_done,captured_online;
 wire [9:0] read_addr;
 wire [7:0] read_data;
 wire [1:0] mode,captured_mode;
 oled_mode_key mode_button(clk,display_key,mode);
 oled_i2s_rx monitor(clk,monitor_bclk,monitor_lrck,monitor_din,
  monitor_sample,monitor_valid,monitor_online);
 oled_visualizer visual(clk,monitor_sample,monitor_valid,monitor_online,mode,
  frame_done,read_addr,read_data,trace_ready,captured_online,captured_mode,display_notes);
 oled_ssd1306 screen(clk,trace_ready,captured_online,read_addr,read_data,
  frame_done,oled_scl,oled_sda);
endmodule
