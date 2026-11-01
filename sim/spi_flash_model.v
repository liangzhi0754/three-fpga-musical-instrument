// Simulation-only 64 KiB SPI NOR model: mode 0, WREN, WIP polling and NOR AND.
module spi_flash_model(input wire sck,input wire cs_n,input wire mosi,output reg miso=1);
 reg [7:0] mem[0:65535];
 reg [7:0] command=0,rx=0,tx=8'hff;
 reg [23:0] address=0;
 integer bits=0,bytes_seen=0,addr_bytes=0,data_count=0,i,k,busy_reads=0;
 reg wel=0,programmed=0;
 initial for(i=0;i<65536;i=i+1) mem[i]=8'hff;
 always @(negedge cs_n) begin
  command=0;rx=0;tx=8'hff;address=0;bits=0;bytes_seen=0;addr_bytes=0;
  data_count=0;programmed=0;miso=1;
 end
 always @(posedge sck) if(!cs_n) begin
  rx={rx[6:0],mosi};bits=bits+1;
  if(bits==8) begin
   bits=0;
   if(bytes_seen==0) begin
    command=rx;
    if(rx==8'h06) wel=1;
    if(rx==8'h9f) tx=8'hef;
    if(rx==8'h05) tx={7'd0,busy_reads!=0};
   end else if(command==8'h03||command==8'h02||command==8'h20) begin
    if(addr_bytes<3) begin
     address={address[15:0],rx};addr_bytes=addr_bytes+1;
     if(addr_bytes==3&&command==8'h03) tx=mem[address[15:0]];
    end else if(command==8'h03) begin
     address=address+1;tx=mem[address[15:0]];
    end else if(command==8'h02&&wel) begin
     mem[address[15:0]]=mem[address[15:0]]&rx;
     address={address[23:8],address[7:0]+8'd1};programmed=1;
    end
   end else if(command==8'h9f) begin
    data_count=data_count+1;
    case(data_count) 1:tx=8'h40;2:tx=8'h17;default:tx=8'hff;endcase
   end else if(command==8'h05) begin
    if(busy_reads>0) busy_reads=busy_reads-1;
    tx={7'd0,busy_reads!=0};
   end
   bytes_seen=bytes_seen+1;
  end
 end
 always @(negedge sck) if(!cs_n) miso=tx[7-bits];
 always @(posedge cs_n) begin
  miso=1;
  if(command==8'h20&&wel&&addr_bytes==3) begin
   for(k=0;k<4096;k=k+1) mem[{address[15:12],12'd0}+k]=8'hff;
   wel=0;busy_reads=2;
  end else if(programmed) begin wel=0;busy_reads=2;end
 end
endmodule
