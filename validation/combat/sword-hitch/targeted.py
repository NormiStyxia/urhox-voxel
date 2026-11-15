import glob,pathlib
from lupa.lua54 import LuaRuntime
files=sorted(p for p in glob.glob('tests/combat/perf_*.lua') if not p.endswith('_support.lua'))
files+=['tests/combat/core_motion.lua','tests/combat/core_hit.lua','tests/combat/core_melee_zone.lua','tests/combat/core_zone_values.lua','tests/combat/core_gc.lua','tests/combat/core_isolation.lua']
failed=0
for f in files:
 try:LuaRuntime(unpack_returned_tuples=True).execute(pathlib.Path(f).read_text());print('SUITE PASS',f)
 except Exception as e:failed+=1;print('SUITE FAIL',f,str(e))
print('suites',len(files),'failed',failed)
raise SystemExit(bool(failed))
