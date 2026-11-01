"""Unified pressure A + unchanged B + three-mode OLED C project."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
UNUSED = {"synth_additive32.v", "status_stream.v", "node_control_cdc.v",
          "audio_sample_timing.v"}
def find_gowin():
    candidates = [os.environ.get("GOWIN_GW_SH", ""),
        "E:/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe",
        "D:/gaoyun/software/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe"]
    return next((Path(p) for p in candidates if p and Path(p).is_file()), None)

GOWIN = find_gowin()


PINS = {
    "A": dict(clk=4, led=15, timbre_key=53, rec_key=18, play_key=19,
              stop_key=79, uart_tx=76, uart_rx=80, pc_uart_rx=86, pc_uart_tx=52,
              touch_scl=71, touch_sda=72,
              adc_scl=27, adc_sda=28, aux_scl=54, aux_sda=55,
              encoder_a=25, encoder_b=56,
              ctrl_sck=77, ctrl_mosi=85, ctrl_cs_n=49, frame_toggle=16,
              audio_sck=17, audio_cs_n=20, audio_data_b=42, audio_data_c=41,
              i2s_bclk=73, i2s_lrck=74, i2s_din=75, flash_sck=29,
              flash_mosi=30, flash_miso=48, flash_cs_n=31, onboard_pa_enable=51),
    "B": dict(clk=4, ctrl_sck=27, ctrl_mosi=28, ctrl_cs_n=26,
              frame_toggle=25, audio_sck=73, audio_cs_n=29, audio_data=30),
    "C": dict(clk=4, ctrl_sck=27, ctrl_mosi=28, ctrl_cs_n=26,
              frame_toggle=25, audio_sck=73, audio_cs_n=29, audio_data=30),
}
for board_name in "BC":
    PINS[board_name].update({f"diag_led_n[{i}]": 15+i for i in range(6)})
    PINS[board_name]["diag_uart_tx"] = 76

PINS['C'].update(monitor_bclk=48, monitor_lrck=31, monitor_din=41,
                 oled_scl=71, oled_sda=72, display_key=42)
PINS['C']['guide_key']=86
PINS['C'].update({f'note_led[{i}]':pin for i,pin in enumerate([51,53,74,75,77,80,85])})


def sources_for(board):
    sources = sorted((ROOT / "src/common").glob("*.v"))
    sources += sorted((ROOT / f"src/board_{board.lower()}").glob("*.v"))
    sources = [p for p in sources if p.name not in UNUSED]
    if board == "C":
        overrides = sorted((ROOT / "src/c_common").glob("*.v"))
        override_names = {p.name for p in overrides}
        sources = [p for p in sources if p.name not in override_names] + overrides
    return sources


def create_project(board, hardware=False):
    folder = ROOT / "projects" / board
    folder.mkdir(parents=True, exist_ok=True)
    sources = sources_for(board)
    project = ET.Element("Project")
    ET.SubElement(project, "Template").text = "FPGA"
    ET.SubElement(project, "Version").text = "5"
    ET.SubElement(project, "Device", name="GW2AR-18C",
                  pn="GW2AR-LV18QN88C8/I7").text = "gw2ar18c-000"
    files = ET.SubElement(project, "FileList")
    for path in sources:
        ET.SubElement(files, "File", path=Path(os.path.relpath(path, folder)).as_posix(),
                      type="file.verilog", enable="1")
    timing = folder / "timing.sdc"
    constraints = "create_clock -name sys_clk -period 37.037 [get_ports {clk}]\n"
    # All external serial clocks are synchronized as data in the local domain.
    timing.write_text(constraints, encoding="ascii")
    ET.SubElement(files, "File", path="timing.sdc", type="file.sdc", enable="1")
    pins = PINS[board]
    lines = ["// Match WIRING.md; package numbers, not header positions."]
    for signal, pin in pins.items():
        lines.append(f'IO_LOC "{signal}" {pin};')
        pull = "UP" if (signal.endswith("_key") or signal.endswith("_scl") or
                         signal.endswith("_sda") or signal.endswith("uart_rx") or
                         signal in ("encoder_a", "encoder_b")) else "NONE"
        drive = ' DRIVE=4' if signal.startswith('note_led[') else ''
        lines.append(f'IO_PORT "{signal}" IO_TYPE=LVCMOS33 PULL_MODE={pull}{drive};')
    (folder / "pins.cst").write_text("\n".join(lines) + "\n", encoding="ascii")
    ET.SubElement(files, "File", path="pins.cst", type="file.cst", enable="1")
    ET.indent(project)
    project_path = folder / f"board_{board.lower()}.gprj"
    ET.ElementTree(project).write(project_path, encoding="utf-8", xml_declaration=True)
    script = folder / "synthesis.tcl"
    script.write_text(
        'cd [file dirname [info script]]\n'
        f'open_project {{board_{board.lower()}.gprj}}\n'
        f'set_option -top_module board_{board.lower()}_top\n'
        + ('set_option -use_sspi_as_gpio 1\n' if board=='A' else '')
        + ('run all\n' if hardware else 'run syn\n'), encoding="ascii")
    return script


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("board", choices=("A", "B", "C", "all"))
    parser.add_argument("--synthesize", action="store_true")
    parser.add_argument("--hardware", action="store_true")
    args = parser.parse_args()
    for board in ("ABC" if args.board == "all" else args.board):
        script = create_project(board, args.hardware)
        print(script, flush=True)
        if args.synthesize:
            if GOWIN is None:
                raise SystemExit("Set GOWIN_GW_SH to your gw_sh.exe path")
            subprocess.run([str(GOWIN), str(script)], cwd=script.parent, check=True)

