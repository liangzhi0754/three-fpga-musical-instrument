`timescale 1ns/1ps
module tb_pressure_pitch_bend;
    reg clk=0;
    always #5 clk=~clk;
    reg [15:0] base_pitch=13200,up_raw=0,down_raw=0;
    reg up_valid=0,down_valid=0,capture_zero=0;
    wire [15:0] adjusted_pitch;
    integer checks=0;
    pressure_pitch_bend dut(clk,base_pitch,up_raw,up_valid,
                            down_raw,down_valid,capture_zero,adjusted_pitch);
    task expect_pitch;
        input [15:0] expected;
        begin
            #1;
            if(adjusted_pitch!==expected)
                $fatal(1,"check %0d expected %0d got %0d",checks,expected,adjusted_pitch);
            checks=checks+1;
        end
    endtask
    initial begin
        // Missing sensors must not change the potentiometer pitch.
        expect_pitch(13200);
        @(negedge clk); up_valid=1;down_valid=1;up_raw=500;down_raw=700;
        @(negedge clk); expect_pitch(13200);
        // Noise near the independently captured rest levels has no effect.
        up_raw=628;down_raw=828;expect_pitch(13200);
        // A representative press: previous v12 shift was 1000; v12.1 is 4000.
        down_raw=700;up_raw=16628;expect_pitch(17200);
        up_raw=500;down_raw=16828;expect_pitch(9200);
        // Equal pressures cancel; unequal pressures retain their difference.
        up_raw=16628;expect_pitch(13200);
        up_raw=8628;expect_pitch(11200);
        // Release returns to base, and moving the potentiometer updates base.
        up_raw=500;down_raw=700;expect_pitch(13200);
        base_pitch=18000;expect_pitch(18000);
        up_raw=16628;expect_pitch(22000);
        // Preserve upper/lower limits without wrapping on large pressure.
        base_pitch=25000;expect_pitch(26400);
        base_pitch=1000;up_raw=500;down_raw=65535;expect_pitch(0);
        base_pitch=65535;down_raw=700;up_raw=65535;expect_pitch(26400);
        // Loss of a pressure channel must remove only its contribution.
        base_pitch=13200;up_raw=16628;down_raw=16828;
        up_valid=0;expect_pitch(9200);
        down_valid=0;expect_pitch(13200);
        // Explicit zero calibration supports a changed mechanical rest load.
        @(negedge clk);up_valid=1;down_valid=1;up_raw=2000;down_raw=3000;capture_zero=1;
        @(negedge clk);capture_zero=0;expect_pitch(13200);
        up_raw=6128;expect_pitch(14200);
        up_raw=1900;down_raw=2900;expect_pitch(13200);
        $display("PASS pressure pitch bend v12.1: %0d behavior checks",checks);
        $finish;
    end
    initial begin #10000;$fatal(1,"timeout");end
endmodule
