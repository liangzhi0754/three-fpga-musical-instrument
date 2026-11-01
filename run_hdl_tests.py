"""Re-run digital models with Icarus, without accessing physical hardware."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iverilog", default="E:/qiansai/tmp/iverilog_portable_v9/bin/iverilog.exe")
    args = parser.parse_args()
    compiler = Path(args.iverilog)
    runner = compiler.with_name("vvp.exe")
    a = "src/board_a/"
    c = "src/common/"
    tests = {
        "pressure_pitch_bend": [a + "pressure_pitch_bend.v"],
        "dual_control": [str(p.relative_to(ROOT)) for folder in (ROOT/a,ROOT/c)
                         for p in folder.glob("*.v")
                         if p.name not in ("synth_additive32.v", "status_stream.v",
                                           "node_control_cdc.v", "audio_sample_timing.v")],
        "status_dual": [a+"status_dual.v",a+"pc_wave_stream.v",c+"uart_rx.v",c+"uart_tx.v"],
        "pc_wave_stream": [a+"pc_wave_stream.v",c+"uart_rx.v",c+"uart_tx.v"],
        "rotary_encoder": [a + "rotary_encoder.v"],
        "encoder_strength": [a + "rotary_encoder.v"],
        "encoder_short_states": [a + "rotary_encoder.v"],
        "gesture_filter": [a+"aux_gesture_filter.v"],
        "paj_audit": ["sim/i2c_paj_model.v"] +
            [str(p.relative_to(ROOT)) for p in (ROOT / a).glob("aux_*.v")],
        "remote_gate": [a + "remote_gate.v"],
        "remote_uart_control": [a + n for n in
            ("host_commands.v", "remote_gate.v", "control_scheduler.v")] +
            [c + n for n in ("uart_rx.v", "control_pack.v", "ctrl_packet_tx.v")],
        "status_diagnostic": [a + "status_extended.v", c + "uart_rx.v", c + "uart_tx.v"],
    }
    output = ROOT / "validation"
    output.mkdir(exist_ok=True)
    results = {}
    for name, sources in tests.items():
        binary = output / (name + ".vvp")
        compiled = subprocess.run([str(compiler), "-g2005", "-s", "tb_" + name,
            "-o", str(binary), "sim/tb_" + name + ".v", *sources],
            cwd=ROOT, capture_output=True, text=True)
        log = compiled.stdout + compiled.stderr
        success = compiled.returncode == 0
        if success:
            simulated = subprocess.run([str(runner), str(binary)], cwd=ROOT,
                capture_output=True, text=True, timeout=180)
            log += simulated.stdout + simulated.stderr
            success = simulated.returncode == 0 and "PASS" in log
        (output / (name + ".log")).write_text(log, encoding="utf8")
        results[name] = {"passed": success, "output": log}
        print(name, "PASS" if success else "FAIL", flush=True)
    (output / "regression_results.json").write_text(
        json.dumps(results, indent=2), encoding="utf8")
    raise SystemExit(not all(r["passed"] for r in results.values()))


if __name__ == "__main__":
    main()
