"""Run combat specs in isolated Lua 5.4 VMs; requires lupa and numpy, no Runtime."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]


def main():
    os.chdir(ROOT)
    specs = [p for p in sorted(Path('tests/combat').glob('*.lua'))
             if not p.stem.endswith(('_mock', '_support'))]
    failures = []
    for path in specs:
        try:
            LuaRuntime(unpack_returned_tuples=True).execute(path.read_text())
        except Exception as exc:
            failures.append(str(path))
            print('FAIL', path, exc, flush=True)
    # Export from tracked Blender data and compare bytes, not just counts.
    try:
        with tempfile.TemporaryDirectory(prefix='thornbow-export-') as temp:
            output = Path(temp) / 'mesh.json'
            subprocess.run([sys.executable, 'art/weapon_gen/thornbow_export.py',
                            'art/weapon_gen/out/thornbow_game.json', str(output)], check=True)
            shipped = Path('assets/model/forge-blades/ThornBow.mesh.json')
            assert output.read_bytes() == shipped.read_bytes(), 'non-reproducible mesh export'
    except Exception as exc:
        failures.append('thornbow_export')
        print('FAIL thornbow_export', exc, flush=True)
    print(f'{len(specs)} Lua suites + export reproducibility; {len(failures)} failed', flush=True)
    return bool(failures)


if __name__ == '__main__':
    sys.exit(main())
