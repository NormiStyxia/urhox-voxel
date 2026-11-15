local scene=node('NightFixture')
local Terrain=require('ruins.RuinsTerrain')
local Flies=require('ruins.Fireflies')
local Fires=require('ruins.NightBraziers')
local Settings=require('ruins.GameSettings')
local Log=require('ruins.DebugLog')
local spawned=0
local function CheckPatch(f,p)
 assert(f.liveCount<=f.count and f.batchCount<=1)
 assert(#f.geometry.verts==f.liveCount*6+6)
 local vertex=1
 for i=1,f.count do
  local a=f.anchors[i]
  if a then
   spawned=spawned+1
   assert((a.x-p.x)^2+(a.z-p.z)^2<26^2)
   local phase=f.geometry.verts[vertex].color.r*math.pi*2
   vertex=vertex+6
   for sample=0,288 do
    local t=sample*0.7
    local x,z=a.x+math.sin(t*.45+phase)*.45,a.z+math.cos(t*.3+phase*2)*.45
    local y=a.y+math.sin(t*.6+phase)*.35
    assert(Terrain.HasGround(x,z),'flight entered void')
    local height=y-Terrain.GroundHeight(x,z)
    assert(height>=.3 and height<=2.5,'height outside requested envelope: '..height)
   end
  end
 end
end
for _,count in ipairs({48,20,0}) do
 local f=Flies.New(scene,count)
 if count==0 then assert(not f.node and not f.ready) else
  for _,p in ipairs({Vector3(0,0,0),Vector3(32,6,0),Vector3(55,6,0),Vector3(0,6,60),Vector3(-55,6,-20),Vector3(43,6,0),Vector3(1000,100,1000)}) do
   f.fade=0;f.recycling=true
   f:Update(.1,p,1,0)
   CheckPatch(f,p)
   if p.x==0 and p.z==0 then assert(f.liveCount==count) end
   if p.x==1000 then assert(f.liveCount==0 and not f.node.enabled) end
  end
  local p=Vector3(0,0,0)
  f.fade=0;f.recycling=true;f:Update(.1,p,1,0)
  for k=1,600 do f:Update(1/60,p,1,k/60) end
  local commits=f.geometry.commits
  local writes=0;local old=f.material.SetShaderParameter
  f.material.SetShaderParameter=function(...)writes=writes+1;return old(...)end
  for k=1,600 do f:Update(1/60,p,0,k/60) end
  assert(f.geometry.commits==commits and writes==0 and not f.node.enabled,'day path updated GPU')
  for k=1,60 do f:Update(1/60,p,1,k/60) end
  for k=1,10 do f:Update(1/60,Vector3(12,0,0),1,k/60) end
  assert(f.geometry.commits==commits,'rebuild must wait for complete fade')
  for k=1,60 do f:Update(1/60,Vector3(12,0,0),1,k/60) end
  assert(f.geometry.commits==commits+1 and f.centerX==12)
  CheckPatch(f,Vector3(12,0,0))
  local n,m=f.node,f.material
  f:Dispose();f:Dispose();f:Update(1/60,p,1,100)
  assert(n.disposed and m.disposed and not f.node and not f.material)
 end
end
assert(Flies.Wrap(-25,0)==15 and Flies.Wrap(25,0)==-15)
print('PASS real terrain paths/count/range/full shader flight envelope/recycle/day/dispose; anchors',spawned)

local anchors={Vector3(0,8,0),Vector3(10,8,0),Vector3(-10,8,0),Vector3(0,8,10),Vector3(0,8,-10),Vector3(10,8,10)}
local fire=Fires.New(scene,anchors,6,3,1)
assert(fire.available and not fire.fallback and fire.sparkCount==4 and #fire.lights==3)
local dn=require('ruins.DayNight').New({scene=scene,zone={},sun={},sunNode=node('Sun'),zoneNode=node('Env'),hour=12})
for k=0,288 do
 dn:SetHour(k/12)
 local n=Flies.NightLevel(dn.nightK)
 assert(n==n and n>=0 and n<=1)
 fire:Update(dn.nightK,k*.125,false)
 assert(fire.level>=0 and fire.level<=1)
 for _,light in ipairs(fire.lights) do
  assert(light.brightness>=0 and light.brightness<=7.00001)
  assert(light.color.g>=.48 and light.color.g<=.51601)
  assert(light.color.b>=.16 and light.color.b<=.18401)
 end
end
for k=0,1000 do
 local n=k/1000
 assert(Flies.NightLevel(n)>=Flies.NightLevel(math.max(0,n-.001)))
end
local colors=0;local originalColor=Color
Color=function(...)colors=colors+1;return originalColor(...)end
for k=1,1000 do fire:Update(1,k/60,true) end
Color=originalColor
assert(colors==0,'light flicker allocates Color')
collectgarbage('collect');collectgarbage('stop')
local memory=collectgarbage('count')
for k=1,10000 do fire:Update(1,k/60,true) end
local growth=collectgarbage('count')-memory
collectgarbage('restart')
assert(growth<1,'mock flicker loop allocates Lua tables: '..growth)
fire:Update(0,0,false);assert(not fire.root.enabled)
for _,light in ipairs(fire.lights)do assert(light.brightness==0)end
local root,mat=fire.root,fire.material
fire:Dispose();fire:Dispose();assert(root.disposed and mat.disposed and not fire.root)
print('PASS 289 day/night samples, smooth twilight, bounded synchronized flicker, cached colors, disposal')

local get=cache.GetResource
cache.GetResource=function(s,kind,path)
 if path=='Materials/RuinsPillarFlameDynamic.xml' then return nil end
 return get(s,kind,path)
end
fire=Fires.New(scene,anchors,6,3,1)
assert(fire.available and fire.fallback and fire.triangleCount==6*44)
fire:Update(1,1,false);assert(fire.root.enabled)
fire:Dispose()
cache.GetResource=function()return nil end
fire=Fires.New(scene,anchors,6,3,1);assert(not fire.available and not fire.root)
local f=Flies.New(scene,48);assert(not f.ready and not f.node)
cache.GetResource=get
local async=cache.GetResourceAsync
local delayed={}
cache.GetResourceAsync=function(s,kind,path,cb)delayed[#delayed+1]=function()cb(get(s,kind,path))end end
fire=Fires.New(scene,anchors,6,3,1);f=Flies.New(scene,48)
fire:Dispose();f:Dispose()
for _,cb in ipairs(delayed)do cb()end
assert(not fire.root and not f.node)
cache.GetResourceAsync=async
print('PASS material/shader load failure fallback and both missing safe-hide, late callbacks cannot revive disposed nodes')

Settings.Load()
for _,tier in ipairs({'high','medium','low'})do
 Settings.Set('quality',tier)
 local p=Settings.GetProfile()
 assert(p.fireflies==({high=48,medium=20,low=0})[tier])
 assert(p.flameDetail==({high=1,medium=.5,low=.25})[tier])
end
Settings.Set('quality','high');Settings.Set('floatingMotes',false)
assert(Settings.GetProfile().fireflies==0)
local calls=0
Log.RegisterProbe('night_test',function()calls=calls+1 end)
for i=1,1000 do Log.Log('night','hidden %d',i)end
assert(not Log.enabled and calls==0)
print('PASS quality budgets, existing ambient off switch, disabled log probe not evaluated')

-- Isolate the sky wiring from unrelated clouds, using the real settings and night modules.
package.loaded['ruins.SkyClouds']={New=function()error('clouds should be disabled')end}
package.loaded['ruins.LightShafts']={New=function()error('shafts should be disabled')end}
package.loaded['ruins.FloatingMotes']={New=function()return{count=80,Update=function()end,Dispose=function()end}end}
package.loaded['ruins.SkyAtmosphere']=nil
Settings.Set('clouds',false);Settings.Set('lightShafts',false);Settings.Set('floatingMotes',nil)
local sky=require('ruins.SkyAtmosphere').New(scene,dn)
assert(sky.fireflies and sky.fireflies.count==48)
sky.pillarAnchors=anchors;sky:ApplySwitches()
dn:SetHour(23)
for k=1,60 do sky:Update(1/60,Vector3(0,0,0),nil)end
assert(sky.braziers.material.params.flame_time==sky.clock)
assert(sky.fireflies.material.params.flight_time==sky.clock)
local retired=sky.fireflies
Settings.Set('quality','low');assert(not sky.fireflies and retired.disposed)
Settings.Set('nightBraziers',false)
assert(not sky.active)
local clock=sky.clock
for k=1,600 do sky:Update(1/60,Vector3(0,0,0),nil)end
assert(sky.clock==clock,'closed sky still updating')
Settings.Set('quality','high');assert(sky.fireflies)
sky:Stop();assert(not sky.fireflies and not sky.braziers and not sky.scene)
Settings.Set('quality','medium');assert(not sky.fireflies)
print('PASS sky every-frame clock wiring, settings disposal/re-enable, 600 closed frames, stop unregister')
