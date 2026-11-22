"""Reproduce broad-suite failures against the pre-animation checkpoint to separate existing failures."""
from pathlib import Path
import subprocess
from lupa.lua54 import LuaRuntime

BASE='dfd038f' # Original skeleton checkpoint, before animation integration.
print('BASELINE COMMIT',BASE,flush=True)
baseline={name:subprocess.check_output(['git','show',BASE+':'+path],text=True) for name,path in {
 'combat.CombatAnim':'scripts/combat/CombatAnim.lua',
 'game.BlockCharacter':'scripts/game/BlockCharacter.lua',
 'game.NomiYSMData':'scripts/game/NomiYSMData.lua',
}.items()}
lines=Path('validation/nomi-bb-animation/combat-tests.log').read_text().splitlines()
failed={line.split(' ',2)[1]:line.split(' ',2)[2] for line in lines if line.startswith('FAIL ')}
count=0
for path in failed:
    lua=LuaRuntime()
    lua.execute('print=function()end')
    for module,source in baseline.items():
        lua.execute('local name,source=...;package.preload[name]=function()return assert(load(source,name))()end',module,source)
    try:
        lua.execute('dofile(...)',path)
    except Exception as exc:
        first=str(exc).splitlines()[0]
        same=first==failed[path]
        print('EXISTING' if same else 'DIFFERENT FAILURE',path,first,flush=True)
        count+=int(same)
    else:
        print('NEW FAILURE',path,flush=True)
print('BASELINE FAILURES',count,'OF',len(failed))
raise SystemExit(count!=len(failed))
