import subprocess
from lupa.lua54 import LuaRuntime, LuaError

lua = LuaRuntime()
lua.globals().baseline_moves = subprocess.check_output(
    ['git', 'show', 'a99b8c2:scripts/combat/CombatMoves.lua'], text=True)
lua.execute('package.preload["combat.CombatMoves"]=function() return assert(load(baseline_moves,"baseline CombatMoves"))() end')
try:
    lua.execute("dofile('tests/combat/core_zone_values.lua')")
except LuaError as error:
    print(error)
    assert 'damage=nil origin=(0.0,0.0,0.0)' in str(error), 'unexpected failure'
    print('PASS baseline defect reproduced: expected zero-damage failure at nonzero world position')
else:
    raise AssertionError('baseline unexpectedly passed')
