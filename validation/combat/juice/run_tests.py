from pathlib import Path
from lupa.lua54 import LuaRuntime
files=sorted(p for p in Path('tests/combat').glob('*.lua') if 'support' not in p.name and 'mock' not in p.name)
failed=[]
for p in files:
 try:
  LuaRuntime().execute('dofile('+repr(str(p))+')')
  print('PASS',p,flush=True)
 except Exception as e:
  failed.append(str(p));print('FAIL',p,e,flush=True)
print('TOTAL',len(files),'FAILURES',failed)
raise SystemExit(bool(failed))
