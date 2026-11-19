"""3x wind from actual Lua -> unchanged actual vertex expressions. CPU, not Web."""
from pathlib import Path
import json,runpy,math
import numpy as np
from lupa.lua54 import LuaRuntime
ROOT=Path(__file__).resolve().parents[3];D=Path(__file__).resolve().parent
prefix=(ROOT/'validation/sky-fx/check.lua').read_text().split('local settings=require',1)[0]
def runtime(source):
 lua=LuaRuntime(unpack_returned_tuples=True);lua.execute(prefix)
 lua.globals().Cloud=lua.execute(source)
 lua.execute('''
 instances={}
 function windSample(count,t)
  local c=instances[count]
  if not c then c=Cloud.New(Node(),count,true,true);instances[count]=c end
  c.elapsed=t;c:Update(0,1,0)
  return {c.wind.x,c.wind.y,c.wind.z,c.wind.w,c.material.params.drift_time,c.motionDetail}
 end
 ''')
 lua.execute('''
 package.loaded['ruins.SkyClouds']=Cloud
 function hostSequence(tier,fps)
  local settings=require('ruins.GameSettings');settings.Load()
  for _,key in ipairs({'nightBraziers','floatingMotes','lightShafts','volumetric','atmosphereFog'})do settings.Set(key,false)end
  settings.Set('quality',tier);settings.Set('cloudMotion',true)
  local scene=Node()
  local dn=require('ruins.DayNight').New({scene=scene,zone={},sun={SetAttribute=function()end},sunNode=Node(),zoneNode=Node(),hour=12})
  local a=require('ruins.SkyAtmosphere').New(scene,dn)
  local rows={};local last,interval,writes=0,0,0
  local material=a.clouds.material;local setter=material.SetShaderParameter
  material.SetShaderParameter=function(m,k,v)
   if k=='cloud_wind' then interval=math.max(interval,a.clock-last);last=a.clock;writes=writes+1 end
   return setter(m,k,v)
  end
  for frame=0,10*fps do
   if frame>0 then a:Update(1/fps,Vector3.ZERO,nil)end
   if frame==0 or frame==3*fps or frame==5*fps or frame==10*fps then
    local c=a.clouds;local w=c.material.params.cloud_wind
    rows[frame/fps]={w.x,w.y,w.z,w.w,c.material.params.drift_time,c.motionDetail}
   end
  end
  assert(a.clouds.elapsed+a.cloudStep>9.999 and writes<=51)
  a:Stop();settings.Stop()
  return rows,interval,writes
 end
 ''')
 return lua
old=runtime((D/'SkyClouds.before.lua.txt').read_text())
new=runtime((ROOT/'scripts/ruins/SkyClouds.lua').read_text())
def sample(vm,count,t):
 row=vm.globals().windSample(count,float(t))
 return np.array([row[i] for i in range(1,7)],float)
uniforms={};derivative_error=0;host_intervals={}
for count in (4,12,24):
 uniforms[count]={}
 tier={4:'low',12:'medium',24:'high'}[count]
 host_old,_,_=old.globals().hostSequence(tier,60)
 host_new,interval,writes=new.globals().hostSequence(tier,60)
 _,interval30,writes30=new.globals().hostSequence(tier,30)
 host_intervals[count]={'60fps_max_interval':interval,'30fps_max_interval':interval30,'writes_10s_60fps':writes,'writes_10s_30fps':writes30}
 for t in (0,3,5,10):
  a=np.array([host_old[t][i] for i in range(1,7)])
  b=np.array([host_new[t][i] for i in range(1,7)])
  assert np.allclose(b[:2],(a[:2]*3)%3600) and np.allclose(b[2:4],a[2:4]*3)
  assert np.array_equal(a[4:],b[4:]),'breathing clock/detail must not speed up'
  uniforms[count][t]={'old':a.tolist(),'new':b.tolist()}
 for t in np.linspace(0,86400,289):
  a=sample(new,count,t);b=sample(new,count,t+.001)
  delta=(b[:2]-a[:2]+1800)%3600-1800
  error=float(np.max(np.abs(delta/.001-a[2:4])));derivative_error=max(error,derivative_error)
  assert error<2e-6
  assert np.allclose(a[2:4],sample(old,count,t)[2:4]*3)
(D/'actual-lua-uniforms.json').write_text(json.dumps(uniforms,indent=2))
print('PASS actual old/new Lua: 3x displacement/velocity at all tiers; same wind heading, breathing clock/detail; derivative error',derivative_error,flush=True)

r=runpy.run_path(str(ROOT/'validation/sky-fx/rotation_check.py'))
shader=(ROOT/'assets/Shaders/BLGL/RuinsCloud.shader').read_text()
assert shader==(D/'RuinsCloud.before.shader.txt').read_text()
assert shader.count('texture(')==1
def evaluate(v,count,t,view=None,inv=None,vm=new,capture=None,model=None,sample_data=None):
 data=sample(vm,count,t) if sample_data is None else np.array(sample_data)
 return r['evaluate'](shader,v[:3],v[9:12],v[5:9],np.eye(4) if model is None else model,
   np.eye(4) if view is None else view,np.eye(4) if inv is None else inv,
   time=data[4],detail=data[5],wind_value=data[:4],capture=capture)
pixels=[];steps=[];long_counts={};geometry={}
for count in (4,12,24):
 tris,_=r['reference']['geometry'](count,12);geometry[count]=tris
 centres=[]
 for patch in range(count):
  v=tris[patch*8,0].copy();n=v[9:12];v[:3]=n*np.linalg.norm(v[:3]);centres.append(v)
  yaw=np.degrees(np.arctan2(n[0],n[2]));pitch=-np.degrees(np.arcsin(n[1]))
  view,inv=r['camera'](yaw,pitch)
  base=r['project'](evaluate(v,count,0,view,inv)[1])
  for t in (0,3,5,10):
   for name,vm in (('old',old),('new',new)):
    projected=r['project'](evaluate(v,count,t,view,inv,vm,sample_data=uniforms[count][t][name])[1])
    displacement=(projected-base)[:2]*[1920/2,1080/2]
    pixels.append(dict(count=count,patch=patch,seconds=t,version=name,px390=float(np.linalg.norm(displacement)*390/1080)))
  # Recenter observation on each instantaneous cloud for a bounded screen step.
  for t in np.linspace(0,7200,49):
   d=evaluate(v,count,t)[2];view,inv=r['camera'](np.degrees(np.arctan2(d[0],d[2])),-np.degrees(np.arcsin(d[1])))
   a,b={},{}
   p=r['project'](evaluate(v,count,t,view,inv,capture=a)[1])
   q=r['project'](evaluate(v,count,t+max(host_intervals[count]['60fps_max_interval'],host_intervals[count]['30fps_max_interval']),view,inv,capture=b)[1])
   if min(r['raw'](a['cloud_data'])[3],r['raw'](b['cloud_data'])[3])>.05:
    delta=(q-p)[:2]*[1920/2,1080/2]
    steps.append(dict(count=count,t=float(t),px390=float(np.linalg.norm(delta)*390/1080)))
 # Two hours, 5-second sampling: include opacity-weighted population, not count alone.
 population=[];opacity=[]
 for t in range(0,7201,5):
  alpha=[]
  for v in centres:
   cap={};p=evaluate(v,count,t,capture=cap)
   assert np.isfinite(p[0]).all()
   assert .96<=cap['breathe_x']<=1.04 and .94<=cap['breathe_y']<=1.06
   alpha.append(float(r['raw'](cap['cloud_data'])[3]))
  population.append(sum(a>.05 for a in alpha));opacity.append(sum(alpha))
 assert min(population)>0,(count,'whole layer disappeared')
 long_counts[count]={'min_visible':min(population),'min_opacity_sum':min(opacity),'mean_visible':float(np.mean(population))}

# Exact root crossings for every patch and layer, including the first three local wraps.
seams=0;fade_rates=[]
for count,tris in geometry.items():
 for patch in range(count):
  v=tris[patch*8,0];layer=.5+(v[5]>=.35)-.5*(v[5]>=.55);phase=(v[6]-.5)*180
  for cycle in range(3):
   target=(180+360*cycle-phase)/layer
   lo,hi=0.,1500.
   for _ in range(50):
    mid=(lo+hi)/2;distance=3*(1.20*mid+150*(1-math.cos(mid*.0008)))
    if distance<target:lo=mid
    else:hi=mid
   t=(lo+hi)/2
   for epsilon in (-.0001,.0001):
    cap={};evaluate(v,count,t+epsilon,capture=cap)
    assert float(r['raw'](cap['cloud_data'])[3])==0
    seams+=1
   # Wrap fade is still distance-based; faster passage shortens duration naturally.
   fade_rates.append(50/(sample(new,count,t)[2]*layer))

# Actual new wind through camera yaw/pitch/roll/translation; never assume default helper speed.
poses=((0,0,0),(90,0,0),(180,0,0),(360,0,0),(0,60,0),(0,-60,0),(0,0,45))
rotation_cases=0
for count,tris in geometry.items():
 for patch in range(count):
  v=tris[patch*8,0]
  for t in (0,3,5,10,900):
   base=evaluate(v,count,t)
   for pos in ((0,0,0),(100,80,-50),(-900,30000,750)):
    model=np.eye(4);model[:3,3]=np.asarray(pos)+[13,-3.2,-7]
    for yaw,pitch,roll in poses:
     view,inv=r['camera'](yaw,pitch,roll,pos)
     out=evaluate(v,count,t,view,inv,model=model)
     assert np.allclose(out[2],base[2],atol=1e-10)
     assert np.allclose(out[1],view@np.r_[np.asarray(pos)+base[0][:3],1],atol=1e-8)
     rotation_cases+=1

summary={}
for count in (4,12,24):
 summary[count]={}
 for t in (3,5,10):
  summary[count][t]={}
  for version in ('old','new'):
   p=[x['px390'] for x in pixels if x['count']==count and x['seconds']==t and x['version']==version]
   summary[count][t][version]={'min':min(p),'median':float(np.median(p)),'max':max(p)}
  assert summary[count][t]['new']['median']>summary[count][t]['old']['median']*2.8
 assert summary[count][3]['new']['median']>2
step_values=[p['px390'] for p in steps]
report={'cpu_not_web':True,'pixel_units':'390px height, FOV55, each initial cloud centred, fixed view over time',
 'motion':summary,'host_cadence':host_intervals,'step_actual_30_60fps_px390':{'p95':float(np.percentile(step_values,95)),'max':max(step_values)},
 'two_hour_population':long_counts,'seam_checks':seams,'rotation_cases':rotation_cases,
 'fade_50m_band_seconds':{'min':min(fade_rates),'max':max(fade_rates)}}
(D/'projection-results.json').write_text(json.dumps(report,indent=2))
(D/'pixel-displacements.json').write_text(json.dumps(pixels,indent=2))
print(json.dumps(report,indent=2),flush=True)
print('PASS formal 0/3/5/10s projection, all tiers, 2h population, transparent wraps, actual new wind camera invariance; no GPU/visual acceptance claim')
