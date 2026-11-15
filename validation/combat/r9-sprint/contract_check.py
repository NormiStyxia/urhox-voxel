from pathlib import Path
from lupa.lua54 import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.path='scripts/?.lua;'..package.path")
old=lua.execute("return dofile('validation/combat/r9-sprint/before/AnimClips.lua.txt')")
new=lua.execute("return require('combat.AnimClips')")[0]
def plain(t):
 if hasattr(t,'items'):return {k:plain(v) for k,v in t.items()}
 return t
for key in ('dur','events','motion','realTime','continuous','cancelAt','cancelBlend'):
 assert plain(old['Clips']['dodge_slide'][key])==plain(new['Clips']['dodge_slide'][key]),key
 print('PASS dodge_slide unchanged',key)
source=Path('scripts/combat/AnimClips.lua').read_text()
assert source.count('id="dodge_slide"')==1
print('PASS one authored slide definition; physical window/event/motion contract identical to R9 baseline')
