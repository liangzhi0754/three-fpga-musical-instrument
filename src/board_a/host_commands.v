// 8-byte command: 43 4D sequence opcode arg_lo arg_hi checksum 0D.
// Checksum is sum(sequence..arg_hi). All actions acknowledge via telemetry.
module host_commands(
 input wire clk,input wire rx,output reg command_valid=0,
 output reg [7:0] opcode=0,output reg [15:0] argument=0,
 output reg [7:0] command_sequence=0
);
 wire [7:0] data;
 wire valid,err;
 uart_rx receiver(clk,rx,data,valid,err);
 reg [2:0] index=0;
 reg [7:0] sum=0,check=0,seq=0,op=0;
 reg [15:0] arg=0;
 reg [21:0] timeout=0;
 always @(posedge clk) begin
  command_valid<=0;
  if(index!=0) begin
   if(timeout==2700000) begin index<=0;timeout<=0;end
   else timeout<=timeout+1'b1;
  end
  if(err) index<=0;
  if(valid) begin
   timeout<=0;
   case(index)
    0:if(data==8'h43) index<=1;
    1:if(data==8'h4d) begin index<=2;sum<=0;end else index<=0;
    2:begin seq<=data;sum<=data;index<=3;end
    3:begin op<=data;sum<=sum+data;index<=4;end
    4:begin arg[7:0]<=data;sum<=sum+data;index<=5;end
    5:begin arg[15:8]<=data;sum<=sum+data;index<=6;end
    6:begin check<=data;index<=7;end
    7:begin
     if(data==13&&check==sum) begin
      command_sequence<=seq;opcode<=op;argument<=arg;command_valid<=1;
     end
     index<=0;
    end
   endcase
  end
 end
endmodule
