"""Native math contract + real ContactAO dependency integration, no Runtime."""
from pathlib import Path
from lupa.lua54 import LuaRuntime
emmy=Path('.emmylua/Vector3.d.lua').read_text()
assert 'function Vector3:Lerp(rhs, t) end' in emmy
for path in ('validation/sky-fx/check.lua','validation/settings/sky-integration.lua'):
 source=Path(path).read_text()
 prefix=source.split('local settings=require',1)[0]
 lua=LuaRuntime(unpack_returned_tuples=True)
 lua.execute(prefix+'''
 local a,b=Vector3(1,-2,3),Vector3(5,6,-1)
 for _,t in ipairs({0,.25,.5,1,1.5,-.5}) do
  local c=a:Lerp(b,t)
  assert(c~=a and c~=b)
  assert(c.x==1+4*t and c.y==-2+8*t and c.z==3-4*t)
  local n=c:Normalized();assert(math.abs(n.x*n.x+n.y*n.y+n.z*n.z-1)<1e-12)
  assert(a.x==1 and a.y==-2 and a.z==3 and b.x==5 and b.y==6 and b.z==-1)
 end
 assert(Vector2.ZERO.x==0 and Vector2.ZERO.y==0)
 local v=Vector4(1,2,3,4);assert(v.x==1 and v.y==2 and v.z==3 and v.w==4)
 local Terrain=require('ruins.RuinsTerrain')
 local Build=require('ruins.RuinsBuild')
 local AO=require('ruins.ContactAO')
 local floor=Material:new()
 local ao=AO.New({},floor)
 assert(ao.layoutSupported and floor.params.contact_columns.x==Build.COLONNADE_R)
 assert(floor.params.contact_stairs.x==Terrain.COURT_R and floor.params.contact_stairs.y==Terrain.STAIR_HALF)
 local Settings=require('ruins.GameSettings')
 for _,name in ipairs({'high','medium','low'}) do
  ao:SetQuality(Settings.PROFILES[name],1)
  assert(floor.params.contact_ao_strength==Settings.PROFILES[name].contactAO)
  ao:Apply(0);assert(floor.params.contact_ao_strength==0)
 end
 ao:Dispose();assert(ao.disposed and next(ao.materials)==nil)
 ''')
 print('PASS',path,': non-mutating unclamped Vector3.Lerp incl extrapolation/Normalized; Vec2.ZERO/Vec4; actual Terrain/Build/ContactAO quality/night/Dispose')
