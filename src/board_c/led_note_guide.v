// v19: validated gate feedback only. C86 is retained as an unused input.
// No lesson state can hide note LEDs. Link loss clears control_notes upstream.
module led_note_guide #(
 parameter integer DEBOUNCE=270000, BLINK_HALF=6750000,
 parameter integer ACK_CLOCKS=2700000, FINISH_CLOCKS=27000000
)(
 input wire clk,input wire key_n,input wire link_online,
 input wire [6:0] notes,output wire [6:0] leds
);
 assign leds=link_online?notes:7'd0;
endmodule
