// remote_gate.v -- phone remote gate for the three-board instrument.
//
// Command: 43 4D SEQ 20 MASK_LO 00 CHECK 0D
//   MASK bit0..6 = Do Re Mi Fa Sol La Si
//
// The phone sends the full 7-bit mask on every press/release and refreshes
// it about every 150 ms while a key is held. If no refresh arrives for
// TIMEOUT_CYCLES, all remote notes are released automatically.
//
// effective_gate = physical MPR121 gate OR remote gate, so copper keys keep
// working and phone play works even if MPR121 is offline.
module remote_gate #(
    parameter [23:0] TIMEOUT_CYCLES = 24'd13_500_000  // 500 ms @ 27 MHz
) (
    input  wire        clk,
    input  wire        cmd_valid,
    input  wire [7:0]  command,
    input  wire [15:0] argument,
    input  wire [6:0]  physical_gate,
    output wire [6:0]  effective_gate,
    output reg  [6:0]  remote_gate = 7'd0
);
    localparam [7:0] OP_REMOTE_GATE = 8'h20;

    reg [23:0] timeout = 24'd0;
    wire refresh = cmd_valid && (command == OP_REMOTE_GATE);

    always @(posedge clk) begin
        if (refresh) begin
            remote_gate <= argument[6:0];
            timeout     <= 24'd0;
        end else if (timeout >= TIMEOUT_CYCLES - 24'd1) begin
            remote_gate <= 7'd0;
            timeout     <= TIMEOUT_CYCLES - 24'd1;
        end else begin
            timeout <= timeout + 24'd1;
        end
    end

    assign effective_gate = physical_gate | remote_gate;
endmodule
