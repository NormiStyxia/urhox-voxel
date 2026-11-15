from pathlib import Path
from lupa.lua54 import LuaRuntime
import xml.etree.ElementTree as ET
lua=LuaRuntime(unpack_returned_tuples=True)
for n in ['Fireflies','NightBraziers','SkyAtmosphere','GameSettings']:
    lua.execute('assert(load(...))',Path('scripts/ruins/'+n+'.lua').read_text())
for n in ['RuinsFireflies','RuinsPillarFlameDynamic']:
    ET.parse('assets/Materials/'+n+'.xml')
    shader=Path('assets/Shaders/BLGL/'+n+'.shader').read_text()
    for banned in ['fwidth','dFdx','dFdy','hint_screen_texture','hint_depth_texture','for (','TIME']:
        assert banned not in shader,(n,banned)
    assert 'uniform float' in shader and 'depth_draw_never' in shader
print('PASS Lua syntax/XML/shader safety contracts (not GPU compilation)')
lua.execute(Path('validation/night-fx/fixture.lua').read_text()+Path('validation/night-fx/check.lua').read_text())
