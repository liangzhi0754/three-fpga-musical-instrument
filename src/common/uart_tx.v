// 8N1 UART transmitter, 27 MHz clock, approximately 115200 baud.
module uart_tx (
    input wire clk,
    input wire start,
    input wire [7:0] data,
    output reg busy = 1'b0,
    output reg tx = 1'b1
);
    localparam integer BAUD_DIV = 234;
    reg [7:0] data_reg = 8'd0;
    reg [3:0] bit_index = 4'd0;
    reg [8:0] baud_count = 9'd0;
    reg [9:0] shift = 10'b1111111111;

    always @(posedge clk) begin
        if (!busy) begin
            tx <= 1'b1;
            baud_count <= 9'd0;
            if (start) begin
                data_reg <= data;
                shift <= {1'b1, data, 1'b0};
                bit_index <= 4'd0;
                busy <= 1'b1;
                tx <= 1'b0;
            end
        end else if (baud_count == BAUD_DIV - 1) begin
            baud_count <= 9'd0;
            shift <= {1'b1, shift[9:1]};
            tx <= shift[1];
            if (bit_index == 4'd9) begin
                busy <= 1'b0;
                tx <= 1'b1;
            end else begin
                bit_index <= bit_index + 1'b1;
            end
        end else begin
            baud_count <= baud_count + 1'b1;
        end
    end
endmodule
