"""Rebuild selected boards without replacing archived release images."""
import argparse
import shutil
import stat
import subprocess
from pathlib import Path
import build

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('board', choices=['A', 'B', 'C', 'all'])
    args = parser.parse_args()
    if build.GOWIN is None:
        raise SystemExit('Gowin not found; set GOWIN_GW_SH')
    output = build.ROOT / 'rebuilt'
    output.mkdir(exist_ok=True)
    for board in ('ABC' if args.board == 'all' else args.board):
        script = build.create_project(board, hardware=True)
        subprocess.run([str(build.GOWIN), str(script)], cwd=script.parent, check=True)
        source = script.parent / 'impl/pnr' / f'board_{board.lower()}.fs'
        target = output / f'{board}_REBUILT.fs'
        if target.exists():
            target.chmod(stat.S_IWRITE | stat.S_IREAD)
        shutil.copy2(source, target)
        print(target, flush=True)
