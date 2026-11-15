from pathlib import Path
from lupa.lua54 import LuaRuntime
lua=LuaRuntime()
paths=['scripts/ruins/FootLocomotion.lua','scripts/ruins/NomiController.lua','scripts/ruins/RuinsScene.lua','scripts/ruins/RuinsHUD.lua','scripts/combat/CombatMoves.lua','scripts/combat/CombatAnim.lua','scripts/combat/AnimClips.lua','scripts/combat/CombatCamera.lua','scripts/combat/CombatAudio.lua','scripts/combat/CombatState.lua','scripts/ui/TouchInput.lua','scripts/ui/TouchControls.lua']
for path in paths:
 lua.execute('local source,name=...; local f,err=load(source,name); assert(f,err)',Path(path).read_text(),path)
 print('PASS compile only',path)
