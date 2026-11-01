// Transaction-level model only. Physical SPI timing is tested separately.
module flash_page #(parameter integer ERASE_DELAY=10000, PROGRAM_DELAY=500)(
 input wire clk,input wire start,input wire [1:0] operation,
 input wire [23:0] address,input wire [7:0] host_address,
 input wire host_write,input wire [7:0] host_data,output reg [7:0] host_q=0,
 input wire miso,output wire sck,output wire mosi,output wire cs_n,
 output reg [23:0] jedec_id=24'hef4017,
 output reg busy=0,output reg done=0,output reg error=0
);
 reg [2047:0] mem[0:255];
 integer i,k;
 integer delay=0;
 integer erase_count=0;
 reg inject_error=0,corrupt_read=0;
 reg [1:0] op;
 reg [23:0] addr;
 reg [7:0] memory[0:255];
 assign sck=0;assign mosi=0;assign cs_n=1;
 initial for(i=0;i<256;i=i+1) mem[i]={2048{1'b1}};
 always @(posedge clk) begin
  done<=0;
  host_q<=memory[host_address];
  if(host_write&&!busy) memory[host_address]<=host_data;
  if(start&&!busy) begin
   busy<=1;delay<=operation==2?ERASE_DELAY:operation==1?PROGRAM_DELAY:20;op<=operation;addr<=address;error<=0;
  end else if(busy) begin
   if(delay!=0) delay<=delay-1'b1;
   else begin
    busy<=0;done<=1;
    if(inject_error) error<=1;
    else case(op)
     0:for(k=0;k<256;k=k+1) memory[k]<=mem[addr[15:8]][2047-k*8-:8]^(corrupt_read&&k==100?8'h01:8'h00);
     1:for(k=0;k<256;k=k+1) mem[addr[15:8]][2047-k*8-:8]<=mem[addr[15:8]][2047-k*8-:8]&memory[k];
     2:begin erase_count<=erase_count+1;for(k=0;k<16;k=k+1) mem[{addr[15:12],4'd0}+k]<={2048{1'b1}};end
    endcase
   end
  end
 end
endmodule
