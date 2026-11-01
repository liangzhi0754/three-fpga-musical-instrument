// Independent UART frame decoders. Only complete, checksum-valid commands
// enter the arbiter; bytes from different sources can never interleave.
module dual_host_commands(
 input wire clk, phone_rx, pc_rx,
 output reg command_valid=0,
 output reg [7:0] opcode=0,
 output reg [15:0] argument=0,
 output reg source_pc=0,
 output reg [7:0] phone_sequence=0,
 output reg [7:0] pc_sequence=0
);
 wire phone_valid,pc_valid;
 wire [7:0] phone_op,pc_op,phone_seq,pc_seq;
 wire [15:0] phone_arg,pc_arg;
 host_commands phone(clk,phone_rx,phone_valid,phone_op,phone_arg,phone_seq);
 host_commands pc(clk,pc_rx,pc_valid,pc_op,pc_arg,pc_seq);
 reg phone_pending=0,pc_pending=0;
 reg [7:0] saved_phone_op=0,saved_pc_op=0,saved_phone_seq=0,saved_pc_seq=0;
 reg [15:0] saved_phone_arg=0,saved_pc_arg=0;
 reg prefer_pc=0;
 wire choose_pc=pc_pending && (!phone_pending || prefer_pc);
 // One slot per input suffices: arbitration takes at most two clocks, whereas
 // each next UART command needs 18720 clocks at the fixed 115200 baud rate.
 always @(posedge clk) begin
  command_valid<=0;
  if(phone_pending || pc_pending) begin
   command_valid<=1;
   source_pc<=choose_pc;
   prefer_pc<=!choose_pc;
   if(choose_pc) begin
    pc_pending<=0;opcode<=saved_pc_op;argument<=saved_pc_arg;
    pc_sequence<=saved_pc_seq;
   end else begin
    phone_pending<=0;opcode<=saved_phone_op;argument<=saved_phone_arg;
    phone_sequence<=saved_phone_seq;
   end
  end
  if(phone_valid) begin
   phone_pending<=1;saved_phone_op<=phone_op;saved_phone_arg<=phone_arg;
   saved_phone_seq<=phone_seq;
  end
  if(pc_valid) begin
   pc_pending<=1;saved_pc_op<=pc_op;saved_pc_arg<=pc_arg;
   saved_pc_seq<=pc_seq;
  end
 end
endmodule
