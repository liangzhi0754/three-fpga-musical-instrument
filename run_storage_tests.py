"""Storage verification with real SPI pins and bounded-latency/fault models."""
from pathlib import Path
import json
import subprocess

root = Path(__file__).resolve().parent
iv = Path('E:/qiansai/tmp/iverilog_portable_v9/bin/iverilog.exe')
tests = {
    'store_spi': ('tb_store', ['sim/tb_store.v', 'sim/spi_flash_model.v',
                   'src/board_a/event_store.v', 'src/board_a/flash_page.v',
                   'src/common/spi_byte.v']),
    'store_stress': ('tb_store_stress', ['sim/tb_store_stress.v',
                   'sim/flash_page_model.v', 'src/board_a/event_store.v']),
}
results = {}
for name, (top, sources) in tests.items():
    binary = root / 'validation' / (name + '.vvp')
    p = subprocess.run([str(iv), '-g2005', '-s', top, '-o', str(binary), *sources],
                       cwd=root, capture_output=True, text=True)
    log = p.stdout + p.stderr
    if p.returncode == 0:
        p = subprocess.run([str(iv.with_name('vvp.exe')), str(binary)], cwd=root,
                           capture_output=True, text=True, timeout=180)
        log += p.stdout + p.stderr
    ok = p.returncode == 0 and 'PASS' in log and 'FAIL' not in log
    results[name] = dict(passed=ok, log=log)
    (root / 'validation' / (name + '.log')).write_text(log, encoding='utf8')
    print(name, log.strip(), flush=True)
(root / 'validation/storage_results.json').write_text(json.dumps(results, indent=2))
raise SystemExit(not all(r['passed'] for r in results.values()))
