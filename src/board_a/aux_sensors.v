// Shared auxiliary bus. NACK and poll timeout skip a failed device; touch and
// audio run independently. A host retry restarts the script at a transaction boundary.
module aux_sensors #(parameter integer I2C_HALF_PERIOD=135,
 parameter integer DELAY_CLOCKS_PER_MS=27000, parameter integer POLL_LIMIT=2047,
 parameter integer PROBE_HALF_PERIOD=540,parameter integer PROBE_HOLD=270000,
 parameter integer PROBE_RISE_TIMEOUT=270000,parameter integer BOOT_WAIT=810000,
 parameter integer GESTURE_RETRY_LIMIT=5) (
 input wire clk,inout wire scl,inout wire sda,
 output reg [15:0] distance=0,output reg distance_valid=0,
 output wire [7:0] gesture,output wire gesture_event,
 output reg [1:0] online=0,
 input wire retry,output wire [111:0] diagnostic,output wire [159:0] probe_diagnostic
);
 reg [8:0] pc=0;
 wire [48:0] instruction;
 aux_program rom(pc,instruction);
 wire [3:0] op=instruction[48:45];
 wire chip=instruction[44];
 wire [7:0] regaddr=instruction[43:36],value=instruction[35:28],mask=instruction[27:20];
 wire [3:0] slot=instruction[19:16];
 wire [15:0] argument=instruction[15:0];
 reg [7:0] slots[0:15];
 reg [3:0] state=0;
 reg req=0;
 reg [1:0] txop=0;
 reg [7:0] txvalue=0;
 wire busy,done,ok;
 wire [2:0] bus_fault;
 reg retry_pending=0,boot_probe=1,probe_start=0;
 wire probe_busy,probe_done;
 reg [31:0] boot_count=0;
 reg [8:0] resume_pc=0;
 aux_probe #(.HALF_PERIOD(PROBE_HALF_PERIOD),.HOLD_CLOCKS(PROBE_HOLD),
  .RISE_TIMEOUT(PROBE_RISE_TIMEOUT)) probe(clk,probe_start,scl,sda,
  probe_busy,probe_done,probe_diagnostic);
 reg [7:0] fail_code=0,model_id=0,fail_reg=0,fail_read=0;
 reg [8:0] fail_pc=0;
 reg fail_chip=0;
 reg [2:0] fail_bus=0;
 reg [7:0] attempts=1,ranges=0,transactions=0,last_reg=0;
 reg [3:0] gesture_retries=0;
 reg [1:0] scl_sync=3,sda_sync=3;
 // Bytes 0..13 are packed little-endian in this diagnostic vector.
 assign diagnostic={5'd0,fail_bus,last_reg,transactions,ranges,attempts,
   slots[9],fail_read,model_id,fail_reg,6'd0,fail_chip,fail_pc[8],
   fail_pc[7:0],fail_code,
   distance_valid,sda_sync[1],scl_sync[1],busy,state[2:0],pc[8],pc[7:0]};
 wire [7:0] r0,r1;
 reg [31:0] delay_count=0;
 reg [11:0] polls=0;
 reg [23:0] range_age=0;
 reg gesture_poll=0;
 reg [7:0] gesture_raw=0;
 aux_gesture_filter #(.CLOCKS_PER_MS(DELAY_CLOCKS_PER_MS)) gesture_filter(
  clk,!online[1]||retry,gesture_poll,gesture_raw,gesture,gesture_event);
 reg [47:0] map_temp;
 reg [5:0] map_index=0;
 reg [6:0] map_left=0;
 reg map_skip_first=0;
 integer i;
 initial for(i=0;i<16;i=i+1) slots[i]=0;
 aux_i2c_transaction #(I2C_HALF_PERIOD) bus(clk,req,txop,chip?7'h73:7'h29,regaddr,
                          txvalue,8'd0,busy,done,ok,r0,r1,scl,sda,bus_fault);
 task next;
  begin pc<=pc+1'b1;state<=0;polls<=0;end
 endtask
 task fail;
  input [7:0] reason;
  begin
   // Initial NACKs can be the PAJ wake-up handshake. Retry after the
   // script's10ms delay; never classify the first NACK as a dead device.
   if(chip && ((pc>=160 && pc<=215)||(pc>=240 && pc<=246)) &&
      gesture_retries<GESTURE_RETRY_LIMIT) begin
    gesture_retries<=gesture_retries+1'b1;
    online[1]<=0;pc<=160;state<=0;polls<=0;
   end else begin
   // Give the gesture fault priority only if scanning actually found0x73.
   // Otherwise preserve the original distance diagnostic for compatibility.
   if(!chip||fail_code==0||probe_diagnostic[32+115]) begin
    fail_code<=reason;fail_pc<=pc;fail_reg<=regaddr;
    fail_chip<=chip;fail_read<=r0;fail_bus<=reason==1?bus_fault:3'd0;
   end
   online[chip]<=0;
   if(!chip) distance_valid<=0;
   pc<=chip?9'd216:9'd158;state<=0;polls<=0;
   end
  end
 endtask
 always @(posedge clk) begin
  req<=0;gesture_poll<=0;probe_start<=0;
  if(boot_count<BOOT_WAIT) boot_count<=boot_count+1'b1;
  scl_sync<={scl_sync[0],scl};sda_sync<={sda_sync[0],sda};
  if(retry) retry_pending<=1;
  if(done) begin transactions<=transactions+1'b1;last_reg<=regaddr;end
  if(range_age<5400000) range_age<=range_age+1'b1;
  else distance_valid<=0;
  if((retry_pending||retry||boot_probe)&&state==0&&!busy&&boot_count>=BOOT_WAIT) begin
   resume_pc<=boot_probe?9'd0:9'd234;
   state<=8;probe_start<=1;boot_probe<=0;polls<=0;req<=0;retry_pending<=0;
   online<=0;distance_valid<=0;range_age<=0;gesture_raw<=0;gesture_retries<=0;
   fail_code<=0;fail_pc<=0;fail_reg<=0;fail_read<=0;fail_chip<=0;fail_bus<=0;
   model_id<=0;if(!boot_probe) attempts<=attempts+1'b1;
   for(i=0;i<16;i=i+1) slots[i]<=0;
  end else if(!boot_probe) case(state)
   0:begin
    case(op)
     6:begin
      // Walk the SPAD map over 48 clocks rather than a long priority chain.
      map_temp<={slots[7],slots[6],slots[5],slots[4],slots[3],slots[2]};
      map_index<=0;map_left<=slots[1][6:0];map_skip_first<=slots[1][7];state<=6;
     end
     7:begin delay_count<=argument*DELAY_CLOCKS_PER_MS;state<=5;end
     9:begin pc<=argument[8:0];end
     10:begin online[chip]<=value[0];next;end
     11:begin if(!online[chip]) pc<=argument[8:0];else pc<=pc+1'b1;end
     12:begin if((slots[slot]&mask)==0) pc<=argument[8:0];else pc<=pc+1'b1;end
     default:begin
      txop<=(op==0||op==4)?2'd0:(op==8&&!chip)?2'd2:2'd3;
      txvalue<=op==4?slots[slot]:value;
      state<=1;
     end
    endcase
   end
   1:begin req<=1;if(busy) begin req<=0;state<=2;end end
   2:if(done) begin
    if(!ok) fail(1);
    else case(op)
     1:begin slots[slot]<=r0;next;end
     2:begin
      if((value==255 && (r0&mask)!=0)||((r0&mask)==value)) next;
      else if(polls==POLL_LIMIT) fail(2);
      else begin polls<=polls+1'b1;state<=1;end
     end
     3:begin txvalue<=(r0&mask)|value;txop<=0;state<=3;end
     5:begin
      if(!chip&&regaddr==8'hc0) model_id<=r0;
      if((r0&mask)!=(value&mask)) fail(3);else next;
     end
     8:begin
      if(!chip) begin
       distance<={r0,r1};ranges<=ranges+1'b1;
       // VL53L0X raw device status 11 means range complete, not an optical fault.
       distance_valid<=slots[9][6:3]==11&&{r0,r1}>=30&&{r0,r1}<=2000;
       range_age<=0;
      end
      else begin
       gesture_raw<=r0;gesture_poll<=1;
      end
      next;
     end
     default:next;
    endcase
   end
   3:begin req<=1;if(busy) begin req<=0;state<=4;end end
   4:if(done) begin if(!ok) fail(1);else next;end
   5:if(delay_count==0) next;else delay_count<=delay_count-1'b1;
   6:begin
    if((map_skip_first&&map_index<12)||map_left==0) map_temp[map_index]<=0;
    else if(map_temp[map_index]) map_left<=map_left-1'b1;
    if(map_index==47) state<=7;else map_index<=map_index+1'b1;
   end
   7:begin
    for(i=0;i<6;i=i+1) slots[i+2]<=map_temp[i*8+:8];
    next;
   end
   8:if(probe_done) begin
    pc<=resume_pc;state<=0;
   end
   default:state<=0;
  endcase
 end
endmodule

