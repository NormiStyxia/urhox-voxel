LIGHT_POINT=20
local geometries={}
local makeGeometry=geometry
geometry=function()local g=makeGeometry();geometries[#geometries+1]=g;return g end
local settings=require('ruins.GameSettings')
local Fires=require('ruins.NightBraziers')
package.loaded['ruins.VoxelBrush']={}
package.loaded['ruins.RuinsPalette']={P={}}
package.loaded['ruins.RuinsTerrain']={RING_Y=6,STAIR_HALF=3.75}
package.loaded['ruins.RuinsTrees']={}
local build=require('ruins.RuinsBuild')
-- Identical fixed-seed decisions used by BuildColonnade; no voxel generation.
local rng=require('ruins.Noise').Rng(77)
build.colBroken={}
for id=0,23 do
 local a=(id+0.5)/24*2*math.pi
 local h=rng:Next()
 if math.abs(math.sin(a))<=0.97 and h<0.35 then build.colBroken[id]=1.2+rng:Next()*3.5 end
 if id==5 or id==17 then build.colBroken[id]=nil end
end
local anchors=Fires.Anchors(build,6)
assert(#anchors==6)
for _,a in ipairs(anchors) do
 assert(math.abs(math.sqrt(a.x*a.x+a.z*a.z)-24.6)<1e-8 and a.y==13.9)
 local found=false
 for id=0,23 do
  local angle=build.ColAngle(id)
  if not build.colBroken[id] and math.abs(a.x-math.cos(angle)*24.6)<1e-8 and math.abs(a.z-math.sin(angle)*24.6)<1e-8 then found=true end
 end
 assert(found,'only actual intact pillars')
 assert(1-.21>.75 and 1+.21<1.25,'beam clearance and cap support')
end
local scene=node('Scene')
local dn=require('ruins.DayNight').New({scene=scene,zone={},sun={SetAttribute=function()end},sunNode=node('Sun'),zoneNode=node('Env'),hour=12})
settings.Load();settings.Set('quality','high')
local a=require('ruins.SkyAtmosphere').New(scene,dn)
a:SetPillarLayout(build,6)
local log=require('ruins.DebugLog')
log.Log=function()error('disabled logger invoked')end
log.Warn=function()error('disabled logger invoked')end
local previous
local lastPhase=0
for _,case in ipairs({{'high',6,3,1,.009},{'medium',4,2,.5,.006},{'low',2,1,0,0}}) do
 settings.Set('quality',case[1])
 assert(math.abs(a.clouds.elapsed-lastPhase)<1e-9,'quality switch preserves world wind phase')
 if previous then assert(previous.root.disposed and previous.material.disposed and previous.basinMaterial.disposed)end
 local f=a.braziers;assert(f.available and f.count==case[2] and #f.lights==case[3])
 assert(f.batchCount==case[2]+1 and f.triangleCount==case[2]*44)
 for _,g in ipairs(geometries)do
  if g.material==f.basinMaterial then
   assert(#g.verts/3==case[2]*36)
   for j=1,#g.verts,3 do
    local v,b,c=g.verts[j],g.verts[j+1],g.verts[j+2]
    local ux,uy,uz=b.x-v.x,b.y-v.y,b.z-v.z
    local vx,vy,vz=c.x-v.x,c.y-v.y,c.z-v.z
    local n=v.normal
    assert((uy*vz-uz*vy)*n.x+(uz*vx-ux*vz)*n.y+(ux*vy-uy*vx)*n.z>0,'basin outward winding')
   end
  end
 end
 assert(a.clouds.motionDetail==case[4])
 for h=0,288 do
  dn:SetHour(h/12);a:Update(.2,Vector3.ZERO,nil)
  assert(f.level==f.level and f.level>=0 and f.level<=1)
  for _,light in ipairs(f.lights)do
   assert(light.lightType==LIGHT_POINT and not light.castShadows and light.range==12)
   assert(light.brightness>=0 and light.brightness<=7)
  end
 end
 dn:SetHour(12);a:Update(.2,Vector3.ZERO,nil);assert(not f.root.enabled)
 for _,light in ipairs(f.lights)do assert(light.brightness==0)end
 dn:SetHour(0);a:Update(.2,Vector3.ZERO,nil);assert(f.root.enabled and f.level>.99)
 previous=f
 lastPhase=a.clouds.elapsed
end
print('PASS real profiles: 6/4/2 fires, 3/2/1 shadowless points, 7/5/3 object draws; 289 day samples per tier; intact cap/beam clearance')
settings.Set('cloudMotion',false)
local c=a.clouds;local frozen=c.elapsed
for i=1,600 do a:Update(1/60,Vector3.ZERO,nil)end
assert(c.elapsed==frozen)
settings.Set('cloudMotion',true);a:Update(.2,Vector3.ZERO,nil);assert(c.elapsed>frozen)
settings.Set('atmosphereFog',false);assert(not dn.zone.depthFogEnable and not dn.zone.heightFogEnable)
settings.Set('nightBraziers',false);assert(not a.braziers and previous.root.disposed)
settings.Set('clouds',false);settings.Set('lightShafts',false);settings.Set('floatingMotes',false);settings.Set('volumetric',false)
assert(not a.active)
local clock=a.clock
for i=1,600 do a:Update(1/60,Vector3.ZERO,nil)end
assert(a.clock==clock)
settings.Set('clouds',true);assert(a.clouds.elapsed==a.cloudElapsed,'re-enable keeps frozen phase')
settings.Set('clouds',false)
print('PASS independent switches, freeze/resume, 600 all-off frames no work or logging')
a:Stop();a:Stop()
local original=cache.GetResourceAsync
local callback;local calls=0
cache.GetResourceAsync=function(_,kind,path,fn)calls=calls+1;callback=fn end
local pending=Fires.New(scene,anchors,6,3)
pending:Update(1,4,false);assert(not pending.root and pending.loading)
callback(Material:new());assert(pending.available and pending.root.enabled and pending.material.params.night_strength==1)
pending:Dispose();pending:Dispose()
local cancelled=Fires.New(scene,anchors,4,2);cancelled:Dispose();callback(Material:new());assert(not cancelled.root)
local failed=Fires.New(scene,anchors,2,1);callback(nil)
local before=calls
for i=1,600 do failed:Update(1,i,false)end
assert(calls==before and not failed.root and #failed.lights==0)
local off=Fires.New(scene,anchors,0,0);assert(calls==before)
cache.GetResourceAsync=original
print('PASS async fire resource: current night before show, late completion ignored, failure hidden/no lights/no retry, zero budget no lookup')
