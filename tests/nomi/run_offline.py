"""Run standalone Lua specs in isolated Lua 5.4 VMs, never an engine executable."""
import argparse, os, subprocess, tempfile
from pathlib import Path
from lupa.lua54 import LuaRuntime
ROOT=Path(__file__).resolve().parents[2]
os.chdir(ROOT)
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--focused',action='store_true',help='only elbow/legacy character contract test')
args=parser.parse_args()
with tempfile.TemporaryDirectory(prefix='nomi-elbow-baseline-') as temp:
    baseline=Path(temp)/'BlockCharacter.lua'
    # Immutable pre-elbow blob: HEAD may advance while other owners work.
    baseline.write_bytes(subprocess.check_output(['git','show','f38bf8a63f4e9f8da6cb67461bd19fab074eecaa']))
    os.environ['NOMI_BASELINE_LUA']=str(baseline)
    # Existing standalone test entry points only; support/mocks are loaded by specs.
    tests=[Path('tests/nomi/elbow_rig.lua')]
    if not args.focused:
        tests += [p for p in sorted(Path('tests/combat').glob('*.lua'))
                  if not any(token in p.stem for token in ('mock','support'))]
        tests += sorted(Path('tests/ruins').glob('*.lua'))
    failed=[]
    for path in tests:
        print('RUN',path,flush=True)
        try:
            LuaRuntime(unpack_returned_tuples=True).execute(path.read_text())
        except Exception as exc:
            print('FAIL',path,str(exc),flush=True);failed.append(str(path))
    print('RESULT',len(tests)-len(failed),'PASS',len(failed),'FAIL',failed,flush=True)
    if failed: raise SystemExit(1)
