"""Hardware-free OLED tests, plus old/new C audio-node equivalence."""
import json
from pathlib import Path
import subprocess
import build

ROOT = Path(__file__).resolve().parent
IVERILOG = Path('E:/qiansai/tmp/iverilog_portable_v9/bin/iverilog.exe')
out = ROOT / 'validation'
out.mkdir(exist_ok=True)
tests = {
 'led_note_guide': ['led_note_guide.v'],
 'oled_rx': ['oled_i2s_rx.v'],
 'oled_display': ['oled_i2c_byte.v', 'oled_ssd1306.v'],
 'oled_mode_key': ['oled_mode_key.v'],
 'oled_visualizer': ['oled_visualizer.v', 'oled_trig_lut.v'],
 'oled_notes': ['oled_visualizer.v', 'oled_trig_lut.v'],
 'spectrum_center': ['oled_visualizer.v', 'oled_trig_lut.v'],
 'oled_c_equivalence': [],
}
results = {}
for name, files in tests.items():
    binary = out / (name + '.vvp')
    command = [str(IVERILOG), '-g2005', '-s', 'tb_' + name, '-o', str(binary),
               'sim/tb_' + name + '.v']
    command += ['src/board_c/' + n for n in files]
    if name == 'oled_c_equivalence':
        command += ['sim/board_c_baseline.v']
        command += [str(p.relative_to(ROOT)) for p in build.sources_for('C')]
    p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    log = p.stdout + p.stderr
    ok = p.returncode == 0
    if ok:
        p = subprocess.run([str(IVERILOG.with_name('vvp.exe')), str(binary)],
                           cwd=ROOT, capture_output=True, text=True, timeout=300)
        log += p.stdout + p.stderr
        ok = p.returncode == 0 and 'PASS' in log
    results[name] = {'passed': ok, 'log': log}
    (out / (name + '.log')).write_text(log, encoding='utf-8')
    print(name, log.strip(), flush=True)
if results['oled_visualizer']['passed']:
    p = subprocess.run([__import__('sys').executable, 'check_visual_results.py'],
                       cwd=ROOT, capture_output=True, text=True)
    results['numeric_reference'] = {'passed': p.returncode == 0,
                                    'log': p.stdout + p.stderr}
    print('numeric_reference', p.stdout + p.stderr, flush=True)
(out / 'oled_results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
raise SystemExit(not all(x['passed'] for x in results.values()))
