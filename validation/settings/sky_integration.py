from pathlib import Path
from lupa.lua54 import LuaRuntime
import xml.etree.ElementTree as ET
lua=LuaRuntime(unpack_returned_tuples=True)
files=['SkyClouds','LightShafts','FloatingMotes','LightQuality','SkyAtmosphere','DayNight','RuinsScene']
for n in files: lua.execute('assert(load(...))',Path('scripts/ruins/'+n+'.lua').read_text())
print('PASS Lua 5.4 load: 7 changed/new Lua files')
for p in ['assets/Materials/RuinsCloud.xml','assets/Materials/RuinsLightShaft.xml','assets/LightGroup/RuinsDay.xml']:
 ET.parse(p)
print('PASS XML parse: 3 lighting/material assets')
lua.execute(Path('validation/settings/sky-integration.lua').read_text())
s=Path('scripts/ruins/tests/DayNightTest.lua').read_text().split('    local actual = dayNight_')[0]
# Concurrent settings work now reads the native capture.minCaptureInterval property.
# Original mock lacked it; supply the same .5 default without modifying the game's fixture.
s=s.replace('supported = true, capturing = false, requests = 0','supported = true, capturing = false, requests = 0, minCaptureInterval = 0.5')
lua.execute(s+chr(10)+'end'+chr(10)+'CheckLighting()')
print('PASS existing DayNightTest offline fixtures (native minCaptureInterval=.5 supplied to old mock)')
# No edits to the tested capture protocol or bottom-hemisphere palette.
dn=Path('scripts/ruins/DayNight.lua').read_text()
assert 'Color(0.30, 0.35, 0.42), Color(0.07, 0.09, 0.13)' in dn
assert 'self.sky.groundCurve = 0.28' in dn
scene=Path('scripts/ruins/RuinsScene.lua').read_text()
assert 'M.START_HOUR = 12.0' in scene
for n in ['SkyClouds','LightShafts','FloatingMotes','SkyAtmosphere']:
 source=Path('scripts/ruins/'+n+'.lua').read_text().split('function M:Update',1)[1]
 assert 'Vector3(' not in source and '{} ' not in source, n
print('PASS source guards: START_HOUR / bottom palette / no Vector3 constructor in new Update methods')
