// AA59: AA58 fields through byte 85, twenty probe bytes, checksum, CR (108 bytes).
module status_dual(
 input wire clk,input wire [6:0] gates,input wire [2:0] timbre,
 input wire [15:0] pitch,input wire [15:0] volume,
 input wire [3:0] sensor_flags,input wire [2:0] features,
 input wire [2:0] ads_online,input wire [1:0] aux_online,
 input wire [1:0] link_ok,input wire [3:0] store_status,
 input wire [3:0] store_flags,input wire [7:0] command_sequence,
 input wire [15:0] distance,input wire [7:0] gesture,
 input wire [6:0] pressure_valid,input wire [111:0] pressure,
 input wire [287:0] link_counters,input wire [111:0] aux_diagnostic,
 input wire [159:0] probe_diagnostic,
 input wire [7:0] pc_command_sequence,
 output wire tx,pc_tx,
 input wire [13:0] encoder_diagnostic,
 input wire [3:0] store_fault_code,
 input wire waveform_valid,input wire signed [15:0] waveform_sample
);
 reg [863:0] packet=0;
 reg [7:0] saved_pc_sequence=0;
 reg [3:0] saved_store_fault_code=0;
 reg [13:0] saved_encoder_diagnostic=0;
 wire pc_busy;
 reg [7:0] seq=0,checksum;
 reg [6:0] index=0;
 reg [18:0] timer=0;
 reg sending=0,waiting=0,start=0;
 reg [6:0] last_gates=0,rises=0,previous=0;
 wire busy;
 wire [7:0] data=packet[863-index*8-:8];
 integer j;
 reg [863:0] next_packet;
 always @* begin
  next_packet=0;
  next_packet[863-:16]=16'haa59;
  next_packet[863-2*8-:8]=seq+1'b1;
  next_packet[863-3*8-:8]=1;
  next_packet[863-4*8-:8]={1'b0,gates|rises|(gates&~previous)};
  next_packet[863-5*8-:8]={5'd0,timbre};
  next_packet[863-6*8-:8]=pitch[7:0];next_packet[863-7*8-:8]=pitch[15:8];
  next_packet[863-8*8-:8]=volume[7:0];next_packet[863-9*8-:8]=volume[15:8];
  next_packet[863-10*8-:8]={4'd0,sensor_flags};
  next_packet[863-11*8-:8]={5'd0,features};
  next_packet[863-12*8-:8]={5'd0,ads_online};
  next_packet[863-13*8-:8]={6'd0,aux_online};
  next_packet[863-14*8-:8]={6'd0,link_ok};
  next_packet[863-15*8-:8]={4'd0,store_status};next_packet[863-16*8-:8]={4'd0,store_flags};
  next_packet[863-17*8-:8]=command_sequence;
  next_packet[863-18*8-:8]=distance[7:0];next_packet[863-19*8-:8]=distance[15:8];
  next_packet[863-20*8-:8]=gesture;next_packet[863-21*8-:8]={1'b0,pressure_valid};
  for(j=0;j<7;j=j+1) begin
   next_packet[863-(22+j*2)*8-:8]=pressure[j*16+:8];
   next_packet[863-(23+j*2)*8-:8]=pressure[j*16+8+:8];
  end
  for(j=0;j<36;j=j+1) next_packet[863-(36+j)*8-:8]=link_counters[j*8+:8];
  for(j=0;j<14;j=j+1) next_packet[863-(72+j)*8-:8]=aux_diagnostic[j*8+:8];
  for(j=0;j<20;j=j+1) next_packet[863-(86+j)*8-:8]=probe_diagnostic[j*8+:8];
  checksum=0;
  for(j=2;j<106;j=j+1) checksum=checksum+next_packet[863-j*8-:8];
  next_packet[15:8]=checksum;next_packet[7:0]=13;
 end
 // Both UARTs share timing and the same snapshot. Only the acknowledgement
 // byte and checksum differ; a phone keepalive cannot overwrite a PC receipt.
 // Diagnostic high bits only on the PC port. Phone bytes remain unchanged.
 wire [7:0] diag10={saved_encoder_diagnostic[3:0],4'b0};
 wire [7:0] diag12={1'b1,saved_encoder_diagnostic[7:4],3'b0};
 wire [7:0] diag13={saved_encoder_diagnostic[13:8],2'b0};
 wire [7:0] pc_checksum=packet[15:8]-packet[863-17*8-:8]+saved_pc_sequence+
                         diag10+diag12+diag13+{saved_store_fault_code,4'd0};
 wire [7:0] pc_data=index==17 ? saved_pc_sequence : index==106 ? pc_checksum :
                    index==10 ? data|diag10 : index==12 ? data|diag12 :
                    index==13 ? data|diag13 :
                    index==15 ? data|{saved_store_fault_code,4'd0} : data;
 uart_tx transmitter(clk,start,data,busy,tx);
 reg pc_snapshot_valid=0;
 reg [863:0] pc_snapshot=0;
 reg [863:0] pc_next;
 reg [7:0] pc_sum;
 integer k;
 always @* begin
  pc_next=next_packet;
  pc_next[863-17*8-:8]=pc_command_sequence;
  pc_next[863-10*8-:8]=next_packet[863-10*8-:8]|{encoder_diagnostic[3:0],4'b0};
  pc_next[863-12*8-:8]=next_packet[863-12*8-:8]|{1'b1,encoder_diagnostic[7:4],3'b0};
  pc_next[863-13*8-:8]=next_packet[863-13*8-:8]|{encoder_diagnostic[13:8],2'b0};
  pc_next[863-15*8-:8]=next_packet[863-15*8-:8]|{store_fault_code,4'd0};
  pc_sum=0;
  for(k=2;k<106;k=k+1) pc_sum=pc_sum+pc_next[863-k*8-:8];
  pc_next[15:8]=pc_sum;
 end
 pc_wave_stream pc_transmitter(clk,pc_snapshot_valid,pc_snapshot,
  waveform_valid,waveform_sample,pc_tx);
 always @(posedge clk) begin
  start<=0;pc_snapshot_valid<=0;previous<=gates;rises<=rises|(gates&~previous);
  if(timer<270000) timer<=timer+1'b1;
  if(!sending) begin
   if(timer>=270000||gates!=last_gates||rises!=0) begin
    saved_pc_sequence<=pc_command_sequence;
    saved_store_fault_code<=store_fault_code;
    saved_encoder_diagnostic<=encoder_diagnostic;
    packet<=next_packet;seq<=seq+1'b1;index<=0;sending<=1;waiting<=0;
    pc_snapshot<=pc_next;pc_snapshot_valid<=1;
    timer<=0;last_gates<=gates;rises<=0;
   end
  end else if(waiting) begin
   if(busy) begin
    waiting<=0;
    if(index==107) sending<=0;else index<=index+1'b1;
   end
  end else if(!busy) begin start<=1;waiting<=1;end
 end
endmodule
