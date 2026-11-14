from pathlib import Path
from lupa.lua54 import LuaRuntime
root = Path(__file__).resolve().parents[2]
lua = LuaRuntime(unpack_returned_tuples=True)
paths = list((root / 'scripts').rglob('*.lua'))
for p in paths:
    lua.execute('assert(load(...))', p.read_text())
print(f'PASS Lua 5.4 syntax: {len(paths)} scripts; Error=0', flush=True)
lua.execute("package.path='scripts/?.lua;'..package.path")
scene = (root / 'scripts/ruins/RuinsScene.lua').read_text()
hook_start = scene.index('    nomi_.onVoidReturn=function(pos)')
hooks = scene[hook_start:scene.index('    sleepBase.valid = false', hook_start)]
gate = scene[scene.index('    if voidInputBlocked and not VoidRewind.IsActive() then'):scene.index('    if touchRevision~=TouchInput.revision then')]
lua.globals().productionHooks = hooks
lua.globals().productionGate = gate
lua.globals().productionSceneUpdate = scene[scene.index('function Ruins_HandleSceneUpdate'):scene.index('function Ruins_HandleUpdate')]
lua.execute((root / 'validation/void-rewind/check.lua').read_text())
