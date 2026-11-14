"""Run standalone Lua specs in isolated Lua 5.4 VMs, never an engine executable."""
import os, subprocess, tempfile
from pathlib import Path
from lupa.lua54 import LuaRuntime
ROOT=Path(__file__).resolve().parents[2]
os.chdir(ROOT)
with tempfile.TemporaryDirectory(prefix='nomi-elbow-baseline-') as temp:
    baseline=Path(temp)/'BlockCharacter.lua'
    baseline.write_bytes(subprocess.check_output(['git','show','HEAD:scripts/game/BlockCharacter.lua']))
    os.environ['NOMI_BASELINE_LUA']=str(baseline)
    # Existing standalone test entry points only; support/mocks are loaded by specs.
    tests=[Path('tests/nomi/elbow_rig.lua')]
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
