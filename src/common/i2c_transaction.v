// 100 kHz open-drain I2C transaction engine, 27 MHz input clock.
// op 0 writes one byte, op 1 writes two bytes, op 2 reads two bytes.
module i2c_transaction #(parameter integer HALF_PERIOD=135) (
    input wire clk,
    input wire req,
    input wire [1:0] op,
    input wire [6:0] addr,
    input wire [7:0] reg_addr,
    input wire [7:0] data0,
    input wire [7:0] data1,
    output reg busy = 1'b0,
    output reg done = 1'b0,
    output reg ack_ok = 1'b0,
    output reg [7:0] rx0 = 8'd0,
    output reg [7:0] rx1 = 8'd0,
    inout wire scl,
    inout wire sda
);
    localparam ST_IDLE=0, ST_START1=1, ST_START2=2,
               ST_TX_HIGH=3, ST_TX_END=4,
               ST_ACK_LOW=5, ST_ACK_HIGH=6, ST_ACK_END=7,
               ST_RSTART1=8, ST_RSTART2=9, ST_RSTART3=10, ST_RSTART4=11,
               ST_RX_LOW=12, ST_RX_HIGH=13, ST_RX_SAMPLE=14,
               ST_RX_ACK_LOW=15, ST_RX_ACK_HIGH=16, ST_RX_ACK_END=17,
               ST_STOP1=18, ST_STOP2=19, ST_STOP3=20;
    reg [4:0] state = ST_IDLE;
    reg [7:0] tick_count = 8'd0;
    reg [18:0] watchdog = 0;
    reg scl_low = 1'b0;
    reg sda_low = 1'b0;
    reg [1:0] op_latched = 2'd0;
    reg [6:0] addr_latched = 7'd0;
    reg [7:0] reg_latched = 8'd0;
    reg [7:0] data0_latched = 8'd0;
    reg [7:0] data1_latched = 8'd0;
    reg [2:0] bit_index = 3'd7;
    reg [2:0] byte_index = 3'd0;
    reg [7:0] rx_shift = 8'd0;

    assign scl = scl_low ? 1'b0 : 1'bz;
    assign sda = sda_low ? 1'b0 : 1'bz;

    function [7:0] tx_byte;
        input [2:0] index;
        begin
            if (op_latched >= 2'd2) begin
                case (index)
                    3'd0: tx_byte = {addr_latched, 1'b0};
                    3'd1: tx_byte = reg_latched;
                    default: tx_byte = {addr_latched, 1'b1};
                endcase
            end else begin
                case (index)
                    3'd0: tx_byte = {addr_latched, 1'b0};
                    3'd1: tx_byte = reg_latched;
                    3'd2: tx_byte = data0_latched;
                    default: tx_byte = data1_latched;
                endcase
            end
        end
    endfunction

    wire [7:0] current_tx_byte = tx_byte(byte_index);
    wire [7:0] next_tx_byte = tx_byte(byte_index + 1'b1);
    wire [7:0] write_address = {addr_latched, 1'b0};
    wire [7:0] read_address = {addr_latched, 1'b1};
    wire stretch_state = (state == ST_TX_END || state == ST_ACK_END ||
                          state == ST_RX_SAMPLE || state == ST_RX_ACK_END ||
                          state == ST_RSTART3 || state == ST_STOP3);
    wire waiting_scl = stretch_state && !scl_low && !scl;
    wire bus_tick = (tick_count == HALF_PERIOD-1) && !waiting_scl;

    always @(posedge clk) begin
        done <= 1'b0;
        if (!busy) watchdog <= 0;
        else watchdog <= watchdog + 1'b1;
        if (bus_tick) tick_count <= 8'd0;
        else if(!waiting_scl) tick_count <= tick_count + 1'b1;

        if (bus_tick) begin
            case (state)
                ST_IDLE: begin
                    scl_low <= 1'b0;
                    sda_low <= 1'b0;
                    if (req && !busy) begin
                        busy <= 1'b1;
                        ack_ok <= 1'b1;
                        op_latched <= op;
                        addr_latched <= addr;
                        reg_latched <= reg_addr;
                        data0_latched <= data0;
                        data1_latched <= data1;
                        state <= ST_START1;
                    end
                end
                ST_START1: begin
                    scl_low <= 1'b0;
                    sda_low <= 1'b1;
                    state <= ST_START2;
                end
                ST_START2: begin
                    scl_low <= 1'b1;
                    sda_low <= ~write_address[7];
                    bit_index <= 3'd7;
                    byte_index <= 3'd0;
                    state <= ST_TX_HIGH;
                end
                ST_TX_HIGH: begin
                    scl_low <= 1'b0;
                    state <= ST_TX_END;
                end
                ST_TX_END: begin
                    scl_low <= 1'b1;
                    if (bit_index == 3'd0) begin
                        sda_low <= 1'b0;
                        state <= ST_ACK_LOW;
                    end else begin
                        bit_index <= bit_index - 1'b1;
                        sda_low <= ~current_tx_byte[bit_index - 1'b1];
                        state <= ST_TX_HIGH;
                    end
                end
                ST_ACK_LOW: begin
                    scl_low <= 1'b1;
                    sda_low <= 1'b0;
                    state <= ST_ACK_HIGH;
                end
                ST_ACK_HIGH: begin
                    scl_low <= 1'b0;
                    state <= ST_ACK_END;
                end
                ST_ACK_END: begin
                    scl_low <= 1'b1;
                    if (sda) begin
                        ack_ok <= 1'b0;
                        state <= ST_STOP1;
                    end else if (op_latched >= 2'd2 && byte_index == 3'd1) begin
                        state <= ST_RSTART1;
                    end else if (op_latched >= 2'd2 && byte_index == 3'd2) begin
                        bit_index <= 3'd7;
                        rx_shift <= 8'd0;
                        state <= ST_RX_LOW;
                    end else if (op_latched == 2'd0 && byte_index == 3'd2) begin
                        state <= ST_STOP1;
                    end else if (op_latched == 2'd1 && byte_index == 3'd3) begin
                        state <= ST_STOP1;
                    end else begin
                        byte_index <= byte_index + 1'b1;
                        bit_index <= 3'd7;
                        sda_low <= ~next_tx_byte[7];
                        state <= ST_TX_HIGH;
                    end
                end
                ST_RSTART1: begin
                    scl_low <= 1'b1;
                    sda_low <= 1'b0;
                    state <= ST_RSTART2;
                end
                ST_RSTART2: begin
                    scl_low <= 1'b0;
                    sda_low <= 1'b0;
                    state <= ST_RSTART3;
                end
                ST_RSTART3: begin
                    scl_low <= 1'b0;
                    sda_low <= 1'b1;
                    state <= ST_RSTART4;
                end
                ST_RSTART4: begin
                    scl_low <= 1'b1;
                    sda_low <= ~read_address[7];
                    byte_index <= 3'd2;
                    bit_index <= 3'd7;
                    state <= ST_TX_HIGH;
                end
                ST_RX_LOW: begin
                    scl_low <= 1'b1;
                    sda_low <= 1'b0;
                    state <= ST_RX_HIGH;
                end
                ST_RX_HIGH: begin
                    scl_low <= 1'b0;
                    state <= ST_RX_SAMPLE;
                end
                ST_RX_SAMPLE: begin
                    scl_low <= 1'b1;
                    rx_shift[bit_index] <= sda;
                    if (bit_index == 3'd0) begin
                        if (byte_index == 3'd2) rx0 <= {rx_shift[7:1], sda};
                        else rx1 <= {rx_shift[7:1], sda};
                        state <= ST_RX_ACK_LOW;
                    end else begin
                        bit_index <= bit_index - 1'b1;
                        state <= ST_RX_LOW;
                    end
                end
                ST_RX_ACK_LOW: begin
                    scl_low <= 1'b1;
                    sda_low <= (byte_index == 3'd2 && op_latched == 2'd2);
                    state <= ST_RX_ACK_HIGH;
                end
                ST_RX_ACK_HIGH: begin
                    scl_low <= 1'b0;
                    state <= ST_RX_ACK_END;
                end
                ST_RX_ACK_END: begin
                    scl_low <= 1'b1;
                    sda_low <= 1'b0;
                    if (byte_index == 3'd2 && op_latched == 2'd2) begin
                        byte_index <= 3'd3;
                        bit_index <= 3'd7;
                        rx_shift <= 8'd0;
                        state <= ST_RX_LOW;
                    end else state <= ST_STOP1;
                end
                ST_STOP1: begin
                    scl_low <= 1'b1;
                    sda_low <= 1'b1;
                    state <= ST_STOP2;
                end
                ST_STOP2: begin
                    scl_low <= 1'b0;
                    sda_low <= 1'b1;
                    state <= ST_STOP3;
                end
                ST_STOP3: begin
                    scl_low <= 1'b0;
                    sda_low <= 1'b0;
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
        if(busy && watchdog == 19'd269999) begin
            state <= ST_IDLE;
            scl_low <= 0;
            sda_low <= 0;
            busy <= 0;
            done <= 1;
            ack_ok <= 0;
            tick_count <= 0;
            watchdog <= 0;
        end
    end
endmodule
