"""Real Lua host time -> actual material uniforms -> executed vertex -> pixels.
Offline evidence only: cannot prove the published Web consumes these uniforms.
"""
from pathlib import Path
import runpy,json,math
import numpy as np
from lupa.lua54 import LuaRuntime
ROOT=Path(__file__).resolve().parents[3];D=Path(__file__).resolve().parent
prefix=(ROOT/'validation/sky-fx/check.lua').read_text().split('local settings=require',1)[0]
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute(prefix+'''
Clouds=require('ruins.SkyClouds')
scene=node('Scene')
dn=require('ruins.DayNight').New({scene=scene,zone={},sun={SetAttribute=function()end},sunNode=node('Sun'),zoneNode=node('Env'),hour=12})
samples={}
for _,count in ipairs({4,12,24}) do
 local c=Clouds.New(scene,count,true,true)
 local rows={}
 for frame=0,3600 do
  if frame>0 then c:Update(1/60,1,0,dn) end
  if frame==0 or frame==600 or frame==1200 or frame==3600 then
   rows[#rows+1]={time=c.elapsed,wind={c.wind.x,c.wind.y,c.wind.z,c.wind.w},detail=c.motionDetail,count=count}
  end
 end
 assert(math.abs(c.elapsed-60)<1e-9)
 local time=c.elapsed;c:SetMotion(false,c.motionDetail)
 for i=1,600 do c:Update(1/60,1,0,dn) end
 assert(c.elapsed==time and c.wind.z==0 and c.wind.w==0)
 c:SetMotion(true,c.motionDetail);c:Update(2.5,1,0,dn)
 assert(c.elapsed==time+2.5,'long real dt must not truncate to 1 second')
 samples[count]=rows;c:Dispose()
end
-- Download latency advances logical phase but never renders a placeholder.
local async=cache.GetResourceAsync;local callback
cache.GetResourceAsync=function(_,_,_,fn)callback=fn end
local c=Clouds.New(scene,4,true,true)
for i=1,100 do c:Update(.2,1,0,dn)end
assert(c.loading and not c.material and math.abs(c.elapsed-20)<1e-9)
callback(cache:GetResource('Texture2D','Textures/Sky/cloud_sculpted_atlas_low.png'))
assert(c.ready and c.material.params.drift_time==c.elapsed and c.wind.x>20)
c:Dispose();callback(nil);assert(c.disposed)
cache.GetResourceAsync=async
-- Real resolved auto profiles + real 5Hz host path, no night/fire changes.
local settingsTick
Node=function()return{Dispose=function()end,Remove=function()end,CreateScriptObject=function()return{
 SubscribeToEvent=function(_,event,fn)settingsTick=fn end,UnsubscribeFromAllEvents=function()end}end}end
input.focus,input.minimized=true,false
local settings=require('ruins.GameSettings');settings.Load()
for _,key in ipairs({'nightBraziers','floatingMotes','lightShafts','volumetric','atmosphereFog'}) do settings.Set(key,false) end
settings.Set('quality','high');settings.Set('clouds',true);settings.Set('cloudMotion',true)
local a=require('ruins.SkyAtmosphere').New(scene,dn)
local ground=Material:new();local clock=0;local writes=0
local function bindCount()
 local mat=a.clouds.material;local original=mat.SetShaderParameter
 mat.SetShaderParameter=function(owner,k,v) if k=='cloud_wind' then writes=writes+1 end;return original(owner,k,v) end
end
bindCount()
for i=1,1200 do a:Update(1/60,Vector3.ZERO,ground);clock=clock+1/60 end
assert(math.abs(a.clouds.elapsed+a.cloudStep-clock)<1e-9,'host does not invent initial .2 seconds')
assert(a.clouds.elapsed>19.8 and writes<=101,'host uploads at <=5Hz, no per-frame uniform writes')
assert(ground.params.cloud_wind==a.clouds.wind)
settings.Set('quality','auto');local rebuilt=0;local prior=a.clouds
for i=1,600 do
 settingsTick(nil,nil,{GetFloat=function()return .05 end});a:Update(.05,Vector3.ZERO,ground);clock=clock+.05
 if prior~=a.clouds then assert(prior.disposed);rebuilt=rebuilt+1;prior=a.clouds end
end
assert(settings.GetProfile().quality=='low' and a.clouds.budget==4 and rebuilt==2)
assert(a.clouds.elapsed>clock-.21 and a.clouds.elapsed<=clock+.001)
local before=a.clouds.elapsed;local wx=a.clouds.wind.x
for i=1,1200 do a:Update(1/60,Vector3.ZERO,ground)end
assert(a.clouds.elapsed>before+19.8 and a.clouds.wind.x~=wx,'auto low must continue moving')
assert(ground.params.cloud_shadow_strength==0,'low shadow budget remains off')
settings.Set('cloudMotion',false);local frozen=a.clouds.elapsed
for i=1,600 do a:Update(1/60,Vector3.ZERO,ground)end
assert(a.clouds.elapsed==frozen)
settings.Set('cloudMotion',true);a:Update(.2,Vector3.ZERO,ground);assert(a.clouds.elapsed>frozen)
a:Stop();settings.Stop()
hostWrites=writes
''')
rows={}
for count in (4,12,24):
 rows[count]=[dict(lua.globals().samples[count][i]) for i in range(1,5)]
 for row in rows[count]:row['wind']=[row['wind'][i] for i in range(1,5)]
(D/'lua-uniforms.json').write_text(json.dumps(rows,indent=2))
print('PASS actual Lua: all tiers at 0/10/20/60s, cold load, pause/resume, 2.5s dt, 20s host time, real auto high->medium->low, shared shadow, freeze')

# Reproduce prior low freeze using saved actual source, no inferred device state.
old=LuaRuntime(unpack_returned_tuples=True);old.execute(prefix)
old.globals().Cloud=old.execute((D/'SkyClouds.lua.before.txt').read_text())
old.execute('c=Cloud.New(Node(),4,true,true);for i=1,100 do c:Update(.2,1,0)end;assert(c.elapsed==0 and c.wind.x==0)')
print('PASS reproduces baseline low-tier zero movement; NOT evidence user actually selected low')

r=runpy.run_path(str(ROOT/'validation/sky-fx/rotation_check.py'))
shader=(ROOT/'assets/Shaders/BLGL/RuinsCloud.shader').read_text()
old_shader=(D/'RuinsCloud.shader.before.txt').read_text()
# Only shader comment changed; executable path/fragment entirely identical.
assert r['body'](shader)==r['body'](old_shader)
assert shader.split('void fragment()',1)[1]==old_shader.split('void fragment()',1)[1]
assert shader.count('texture(')==1
pixels=[]
for count in (4,12,24):
 tris,_=r['reference']['geometry'](count,12)
 # Track authored patch centres in a fixed camera looking at each starting patch.
 for patch in range(count):
  v=tris[patch*8,0];n=v[9:12];radius=np.linalg.norm(v[:3])
  yaw=np.degrees(np.arctan2(n[0],n[2]));pitch=-np.degrees(np.arcsin(n[1]))
  view,inv=r['camera'](yaw,pitch);base=None;last=None
  for row in rows[count]:
   output=r['evaluate'](shader,n*radius,n,v[5:9],np.eye(4),view,inv,time=row['time'],detail=row['detail'],wind_value=row['wind'])
   ndc=r['project'](output[1])
   if base is None:base=ndc
   delta=(ndc-base)[:2]*[1920/2,1080/2]
   pixels.append(dict(count=count,patch=patch,time=round(row['time']),px1080=float(np.linalg.norm(delta)),px390=float(np.linalg.norm(delta)*390/1080)))
 for t in (10,20):
  values=[p['px390'] for p in pixels if p['count']==count and p['time']==t]
  assert np.median(values)>2*(t/10),('insufficient median motion',count,t,values)
(D/'pixel-displacements.json').write_text(json.dumps(pixels,indent=2))
for count in (4,12,24):
 for t in (10,20,60):
  values=[p['px390'] for p in pixels if p['count']==count and p['time']==t]
  print(f'count={count} t={t}s @390px height/FOV55: min={min(values):.3f}, median={np.median(values):.3f}, max={max(values):.3f}px')
print('PASS real uploaded Lua wind -> actual vertex expressions -> camera projection. CPU proxy, not Web observation.')

# Use actual shader expressions across hours; each ring stays near its authored
# centre. Root-solve real X wrap times and inspect both sides, not just strings.
seams=0;max_jump=0.;min_live={}
for count in (4,12,24):
 tris,_=r['reference']['geometry'](count,12);live=[]
 for t in np.linspace(0,7200,145):
  alive=0
  for patch in range(count):
   v=tris[patch*8,0];cap={};n=v[9:12]
   r['evaluate'](shader,n*np.linalg.norm(v[:3]),n,v[5:9],np.eye(4),np.eye(4),np.eye(4),time=t,capture=cap,detail=0 if count==4 else 1)
   alpha=r['raw'](cap['cloud_data'])[3]
   assert np.isfinite(r['raw'](cap['cloud_direction'])).all()
   assert np.linalg.norm(r['raw'](cap['centre_xz'])-r['raw'](cap['centre'])[[0,2]])<383
   alive+=alpha>.05
  live.append(alive)
 min_live[count]=min(live)
 assert min(live)>0,('entire sky disappeared',count)
 for patch in range(count):
  v=tris[patch*8,0];n=v[9:12];layer=.5+(v[5]>=.35)-.5*(v[5]>=.55)
  phase=(v[6]-.5)*180
  for cycle in (0,1,3):
   target=(180+360*cycle-phase)/layer
   lo,hi=0.,6000.
   for _ in range(55):
    mid=(lo+hi)/2;dx=1.20*mid+150*(1-math.cos(mid*.0008))
    if dx<target:lo=mid
    else:hi=mid
   t=(lo+hi)/2
   for eps in (-.001,.001):
    cap={};r['evaluate'](shader,n*np.linalg.norm(v[:3]),n,v[5:9],np.eye(4),np.eye(4),np.eye(4),time=t+eps,capture=cap)
    assert r['raw'](cap['cloud_data'])[3]==0
    seams+=1
print('PASS actual vertex over 2h / all tiers; minimum globally visible patches:',min_live,'; transparent seam sides:',seams)
