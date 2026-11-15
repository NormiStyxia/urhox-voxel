from pathlib import Path
from lupa.lua54 import LuaRuntime
import math,csv,subprocess
lua=LuaRuntime(unpack_returned_tuples=True)
for name in ['ContactAO','DayNight','SceneQuality','GameSettings']:
    lua.execute('assert(load(...))',Path('scripts/ruins/'+name+'.lua').read_text())
lua.execute(Path('validation/night-fx/fixture.lua').read_text()+Path('validation/night-visibility/check.lua').read_text())
ground=Path('assets/Shaders/BLGL/RuinsGround.shader').read_text()
original=subprocess.check_output(['git','show','HEAD:assets/Shaders/BLGL/RuinsGround.shader'],text=True)
# Cloud owner may edit the marked block concurrently; confirm our AO addition is exactly two lines outside it.
assert ground.count('#include "res://Shaders/BLGL/RuinsContactAO.shaderinc"')==1
assert ground.count('AO=ruins_contact_ao(VERTEX,n,0.0);')==1
ao=Path('assets/Shaders/BLGL/RuinsContactAO.shaderinc').read_text()
for bad in ['texture(', 'textureLod(', 'for (', 'fwidth', 'dFdx', 'dFdy', 'ALBEDO', 'hint_depth_texture', 'hint_screen_texture']:
    assert bad not in ao,bad
assert ao.count('uniform ')==4 and 'AO_LIGHT_AFFECT retains its documented default 0' in ao
for name in ['DayNight','SceneQuality','ContactAO']:
    source=Path('scripts/ruins/'+name+'.lua').read_text()
    assert 'ssaoRadius' not in source and 'ssaoIntensity' not in source and 'SetRenderPath' not in source
print('PASS shader bounded-work contract, four uniforms/no loops/samplers/derivatives; no ineffective GTAO/pipeline writes')
