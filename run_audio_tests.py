"""Compare normal timbres to v16 independently, and check cello RTL samples."""
from pathlib import Path
import json
import subprocess
import sys

root = Path(__file__).resolve().parent
compiler = Path('E:/qiansai/tmp/iverilog_portable_v9/bin/iverilog.exe')
runner = compiler.with_name('vvp.exe')
results = {}
for board, folder, mod in [('B','common','normal_reference_b'),
                           ('C','c_common','normal_reference_c')]:
    binary = root/f'validation/normal_{board}.vvp'
    command = [str(compiler), '-g2005', '-s', 'tb_normal_timbres', '-o', str(binary)]
    if board == 'C':
        command += ['-DC_NODE']
    command += ['sim/tb_normal_timbres.v', f'sim/{mod}.v',
                'sim/normal_reference_additive16.v', f'src/{folder}/node_synth.v',
                'src/common/synth_voice.v', 'src/common/synth_waveform.v',
                'src/common/poly_string_bank.v', 'src/common/synth_additive16.v', 'src/common/additive_component.v']
    p = subprocess.run(command, cwd=root, capture_output=True, text=True)
    log = p.stdout+p.stderr
    if p.returncode == 0:
        p = subprocess.run([str(runner),str(binary)], cwd=root,
                           capture_output=True,text=True,timeout=180)
        log += p.stdout+p.stderr
    results[board] = dict(passed=p.returncode==0 and 'PASS' in log,log=log)
    (root/f'validation/normal_{board}.log').write_text(log)
    print(board,log,flush=True)
(root/'validation/audio_results.json').write_text(json.dumps(results,indent=2))
raise SystemExit(not all(x['passed'] for x in results.values()))
