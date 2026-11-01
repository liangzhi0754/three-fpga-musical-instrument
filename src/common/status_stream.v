// Sends FPGA state for visualization only. Frame format:
// AA 55 seq touch adc_lo adc_hi volume_lo volume_hi flags timbre checksum 0D
// checksum is the 8-bit sum of seq through timbre.
module status_stream (
    input wire clk,
    input wire [6:0] touch_bits,
    input wire [15:0] adc_value,
    input wire [15:0] volume_value,
    input wire mpr_online,
    input wire ads_online,
    input wire adc_valid,
    input wire volume_valid,
    input wire [2:0] timbre_mode,
    output wire uart_tx
);
    localparam integer FRAME_PERIOD = 19'd270_000; // 10 ms heartbeat
    reg [18:0] period_count = 19'd0;
    reg frame_pending = 1'b0;
    reg [6:0] last_touch = 7'd0;
    reg [6:0] rise_pending = 7'd0;
    reg [7:0] sequence = 8'd0;
    reg [3:0] byte_index = 4'd0;
    reg byte_start = 1'b0;
    reg [6:0] frame_touch = 7'd0;
    reg [15:0] frame_adc = 16'd0;
    reg [15:0] frame_volume = 16'd0;
    reg [7:0] frame_flags = 8'd0;
    reg [1:0] frame_timbre = 2'd0;
    // byte_start is registered, so uart_tx sees it one clock later. Keep the
    // byte index unchanged until the transmitter has actually become busy.
    reg waiting_start = 1'b0;
    wire tx_busy;
    wire [7:0] checksum = sequence + {1'b0, frame_touch} + frame_adc[7:0] +
                           frame_adc[15:8] + frame_volume[7:0] +
                           frame_volume[15:8] + frame_flags + {6'd0, frame_timbre};
    reg [7:0] current_byte;

    always @* begin
        case (byte_index)
            4'd0: current_byte = 8'hAA;
            4'd1: current_byte = 8'h55;
            4'd2: current_byte = sequence;
            4'd3: current_byte = {1'b0, frame_touch};
            4'd4: current_byte = frame_adc[7:0];
            4'd5: current_byte = frame_adc[15:8];
            4'd6: current_byte = frame_volume[7:0];
            4'd7: current_byte = frame_volume[15:8];
            4'd8: current_byte = frame_flags;
            4'd9: current_byte = {6'd0, frame_timbre};
            4'd10: current_byte = checksum;
            default: current_byte = 8'h0D;
        endcase
    end

    uart_tx tx_engine(.clk(clk), .start(byte_start), .data(current_byte),
                      .busy(tx_busy), .tx(uart_tx));

    always @(posedge clk) begin
        byte_start <= 1'b0;
        last_touch <= touch_bits;
        // Preserve short presses that begin and end during another UART frame.
        rise_pending <= rise_pending | (touch_bits & ~last_touch);
        if (!frame_pending) begin
            if (period_count == FRAME_PERIOD - 1 ||
                touch_bits != frame_touch || |rise_pending ||
                |(touch_bits & ~last_touch)) begin
                period_count <= 19'd0;
                frame_pending <= 1'b1;
                byte_index <= 4'd0;
                sequence <= sequence + 1'b1;
                waiting_start <= 1'b0;
                frame_touch <= touch_bits | rise_pending | (touch_bits & ~last_touch);
                rise_pending <= 7'd0;
                frame_adc <= adc_value;
                frame_volume <= volume_value;
                frame_flags <= {4'd0, volume_valid, adc_valid, ads_online, mpr_online};
                frame_timbre <= timbre_mode;
            end else begin
                period_count <= period_count + 1'b1;
            end
        end else if (waiting_start) begin
            // The UART samples start on the following clock. Once busy is
            // visible, the current byte is safely latched and we may advance.
            if (tx_busy) begin
                waiting_start <= 1'b0;
                if (byte_index == 4'd11)
                    frame_pending <= 1'b0;
                else
                    byte_index <= byte_index + 1'b1;
            end
        end else if (!tx_busy) begin
            // Start exactly the byte selected by byte_index. Do not advance
            // until the next state above confirms that UART accepted it.
            byte_start <= 1'b1;
            waiting_start <= 1'b1;
        end
    end
endmodule
