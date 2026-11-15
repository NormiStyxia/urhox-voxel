"""Actual Lua + actual vertex expressions. CPU contracts, NOT GPU compilation."""
from pathlib import Path
import json, math, runpy, hashlib
import numpy as np
from lupa.lua54 import LuaRuntime
ROOT=Path(__file__).resolve().parents[3]
D=Path(__file__).resolve().parent
shader=(ROOT/'assets/Shaders/BLGL/RuinsCloud.shader').read_text()
old=(D/'RuinsCloud.shader.before.txt').read_text()
assert shader.split('void fragment()',1)[1]==old.split('void fragment()',1)[1]
assert shader.count('texture(')==1 and not any(x in shader for x in ('fwidth(', 'dFdx(', 'dFdy(', 'screen_depth'))
def shared(name):
 s=(ROOT/f'assets/Shaders/BLGL/{name}.shader').read_text()
 return s.split('// CLOUD_SHADOW_SHARED_BEGIN',1)[1].split('// CLOUD_SHADOW_SHARED_END',1)[0]
assert shared('RuinsGround')==shared('RuinsGrassTuft')
assert 'stretch_envelope=16.0*cell.x*(1.0-cell.x)*cell.y*(1.0-cell.y)' in shared('RuinsGround')
assert 'cloud_flat_atlas' not in (ROOT/'scripts/ruins/SkyAtmosphere.lua').read_text()
print('PASS unchanged cloud fragment; one texture; identical ground/fallback grass projection; no legacy atlas')

lua=LuaRuntime(unpack_returned_tuples=True)
prefix=(ROOT/'validation/sky-fx/check.lua').read_text().split('local settings=require',1)[0]
lua.execute(prefix+'''
local scene=node('Scene')
local dn=require('ruins.DayNight').New({scene=scene,zone={},sun={SetAttribute=function()end},sunNode=node('Sun'),zoneNode=node('Env'),hour=12})
local oldRequire=require
require=function(name) if name=='ruins.GameSettings' then error('standalone test') end return oldRequire(name) end
local Atmos=assert(loadfile('scripts/ruins/SkyAtmosphere.lua'))()
require=oldRequire
local a=Atmos.New(scene,dn)
local profiles=require('ruins.GameSettings').PROFILES
local function applyTier(name) a:ApplyProfile(profiles[name]) end
local ground,grass=Material:new(),Material:new()
package.loaded['ruins.RuinsTerrain']={tufts={material=grass}}
local oldPrint,oldFormat=print,string.format
print=function()error('log created while disabled')end
string.format=function()error('log formatted while disabled')end
local samples={}
for _,tier in ipairs({'high','medium','low'}) do
 local old=a.clouds
 applyTier(tier)
 if old~=a.clouds then assert(old.disposed and old.material.disposed) end
 for i=0,288 do
  dn.hour=i/12;dn:Apply();a:Update(.2,Vector3(0,6,0),ground)
  local p=ground.params.cloud_shadow_projection
  local strength=ground.params.cloud_shadow_strength
  assert(strength==strength and strength>=0 and strength<=.16)
  assert(strength==grass.params.cloud_shadow_strength)
  if dn.elev<=.04 or tier=='low' then assert(strength==0) end
  if tier~='low' then
   assert(ground.params.cloud_wind==a.clouds.wind and grass.params.cloud_wind==a.clouds.wind)
   assert(ground.params.cloud_shadow_projection==grass.params.cloud_shadow_projection)
   assert(math.abs(p.x)<=4 and math.abs(p.y)<=4 and p.z==120)
   assert(p.w==(tier=='high' and 1 or 0))
  else assert(a.clouds.motionDetail==0) end
  samples[#samples+1]={tier=tier,hour=dn.hour,strength=strength,x=p and p.x or 0,z=p and p.y or 0}
 end
end
applyTier('high');dn.hour=12;dn:Apply();a:Update(.2,Vector3.ZERO,ground)
a:SetFeature('cloudMotion',false)
local elapsed,x,z=a.clouds.elapsed,a.clouds.wind.x,a.clouds.wind.y
for i=1,600 do a:Update(1/60,Vector3.ZERO,ground) end
assert(a.clouds.elapsed==elapsed and a.clouds.wind.x==x and a.clouds.wind.y==z)
assert(a.clouds.wind.z==0 and a.clouds.wind.w==0)
local oldCloud=a.clouds;applyTier('medium');assert(oldCloud.disposed)
assert(a.clouds.elapsed==elapsed and a.clouds.wind.x==x and a.clouds.wind.y==z)
applyTier('low');local freeze=a.clouds.elapsed
for i=1,600 do a:Update(1/60,Vector3.ZERO,ground) end
assert(a.clouds.elapsed==freeze and a.clouds.wind.x==x and ground.params.cloud_shadow_strength==0)
a:SetQuality('off');local clock=a.clock
local calls=0
ground.SetShaderParameter=function()calls=calls+1 end
grass.SetShaderParameter=function()calls=calls+1 end
for i=1,600 do a:Update(1/60,Vector3.ZERO,ground) end
assert(calls==0 and a.clock==clock and not a.clouds)
a:Stop()
-- Failed receiver binding: zero strength, no retry loop, no logging.
local b=Atmos.New(scene,dn);local target=Material:new();local binds=0
target.SetSurfaceTexture=function()binds=binds+1;return false end
b:Update(.2,Vector3.ZERO,target)
for i=1,600 do b:Update(1/60,Vector3.ZERO,target) end
assert(binds==1 and target.params.cloud_shadow_strength==0)
b:Stop()
print,string.format=oldPrint,oldFormat
windSamples=samples
''')
rows=[dict(lua.globals().windSamples[i]) for i in range(1,len(lua.globals().windSamples)+1)]
(D/'day-shadow-samples.json').write_text(json.dumps(rows,indent=2))
print('PASS real Lua: 289 times x 3 tiers; same wind; solar projection finite; night/low zero; freeze/rebuild; 600 off frames zero writes; failed binding no retry; zero logging')

r=runpy.run_path(str(ROOT/'validation/sky-fx/rotation_check.py'))
triangles,_=r['reference']['geometry']()
view,inv=r['camera']();model=np.eye(4)
counts=0;max_step=0.;fade_checks=0
for time in (0,137,1500,6000,12000,31415.9265359,60000):
 for v in triangles[:-2].reshape(-1,12)[::24]:
  cap={};a=r['evaluate'](shader,v[:3],v[9:12],v[5:9],model,view,inv,time,capture=cap)
  assert np.isfinite(a[0]).all() and abs(np.linalg.norm(a[2])-1)<1e-10
  assert 0<=r['raw'](cap['cloud_data'])[3]<=1
  assert len(r['raw'](cap['cloud_data']))==4
  if time==0: assert r['raw'](cap['cloud_data'])[3]==v[8]
  assert .96<=cap['breathe_x']<=1.04 and .94<=cap['breathe_y']<=1.06
  b=r['evaluate'](shader,v[:3],v[9:12],v[5:9],model,view,inv,time+.2)
  max_step=max(max_step,float(np.linalg.norm(a[2]-b[2])))
  counts+=1
# At arbitrary wrap crossings the entire patch alpha is zero on BOTH sides.
for layer in (.5,1.,1.5):
 for centre in (-90.,0.,90.):
  for epsilon in (-.001,.001):
   moved=centre+(180-centre+epsilon)/layer*layer
   wrap=(moved+180)%360-180
   alpha=1-r['reference']['smooth'](120,170,abs(wrap))
   assert alpha==0;fade_checks+=1
  for offset in (0,800,3599.999):
   a=(centre+offset*layer+180)%360-180
   b=(centre+(offset+3600)*layer+180)%360-180
   assert abs(a-b)<1e-8
# Analytic wind displacement derivative really equals the uploaded velocity.
for t in np.linspace(0,60000,289):
 a=r['raw'](r['wind'](t));b=r['raw'](r['wind'](t+.001))
 delta=(b[:2]-a[:2]+1800)%3600-1800
 assert np.allclose(delta/.001,a[2:],atol=1e-6)
# Mip gutters sampled independently for all 8 cells; coarse LOD never crosses cells.
# The stretching envelope vanishes on every cell boundary, including diagonal sun.
for slope in ((4,4),(-4,4),(0,0),(1,-2)):
 for edge in range(4):
  for t in np.linspace(0,1,33):
   cell=np.array(([0,t],[1,t],[t,0],[t,1])[edge],float)
   envelope=16*cell[0]*(1-cell[0])*cell[1]*(1-cell[1])
   assert envelope==0
for low in (False,True):
 mips=r['reference']['mipmaps'](low)
 for lod in (2,3):
  uv=[]
  for i in range(8):
   for t in np.linspace(.004,.996,33):
    uv.extend([[(i%4+.004)/4,(i//4+t)/2],[(i%4+.996)/4,(i//4+t)/2]])
  data=r['reference']['sample'](mips,np.array(uv),np.full(len(uv),lod))
  assert data[:,3].max()<.01,('gutter alpha',low,lod,data[:,3].max())
out=dict(vertex_cases=counts,wrap_fade_cases=fade_checks,max_sampled_5Hz_direction_step=max_step,
 cloud_fragment_sha256=hashlib.sha256(shader.split('void fragment()',1)[1].encode()).hexdigest(),
 high=dict(clouds=24,triangles=194,draws=1,sky_texture_reads=1,shadow_texture_reads=2),
 medium=dict(clouds=12,triangles=98,draws=1,sky_texture_reads=1,shadow_texture_reads=1),
 low=dict(clouds=4,triangles=34,draws=1,sky_texture_reads=1,shadow_texture_reads=0),
 gpu_compiled=False,web_validated=False,native_grass_shadow=False)
(D/'counts.json').write_text(json.dumps(out,indent=2))
print('PASS actual vertex finite/breath bounds; wrap transparency and common period; analytic wind derivative; both atlas mip gutters')
print(json.dumps(out,indent=2))
