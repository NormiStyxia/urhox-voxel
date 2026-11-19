"""Bounded opt-in native material getters; no GPU equivalence claim."""
from pathlib import Path
from lupa.lua54 import LuaRuntime
ROOT=Path(__file__).resolve().parents[3]
lua=LuaRuntime(unpack_returned_tuples=True)
prefix=(ROOT/"validation/sky-fx/check.lua").read_text().split("local settings=require",1)[0]
lua.execute(prefix+'''
local settings=require("ruins.GameSettings");settings.Load()
for _,key in ipairs({"nightBraziers","floatingMotes","lightShafts","volumetric","atmosphereFog"})do settings.Set(key,false)end
settings.Set("quality","high");settings.Set("cloudMotion",true)
local scene=Node()
local dn=require("ruins.DayNight").New({scene=scene,zone={},sun={SetAttribute=function()end},sunNode=Node(),zoneNode=Node(),hour=12})
local a=require("ruins.SkyAtmosphere").New(scene,dn)
local logger=require("ruins.DebugLog")
local reads=0
local function getters(m)
 m.GetShaderParameter=function(self,key)
  reads=reads+1
  local v=self.params[key]
  -- Copy on read to represent a native value getter, not an alias to wind.
  if type(v)=="table" then
   local copy=Vector4(v.x,v.y,v.z,v.w)
   return {GetVector4=function()return copy end,GetTypeName=function()return "Vector4"end}
  end
  return {GetFloat=function()return v or 0 end}
 end
end
getters(a.clouds.material)
a.clouds.geometry[1].GetMaterial=function(g)return g.material end
for i=1,600 do a:Update(1/60,Vector3.ZERO,nil)end
local p=a:Probe();assert(p.motionSample==nil and reads==0 and a.motionProbeSamples==0)
logger.enabled=true -- Avoid installing a mock timer; exercise the real Probe.
local previous=-1
for i=1,6 do
 for j=1,300 do a:Update(1/60,Vector3.ZERO,nil)end
 p=a:Probe()
 assert(p.motionSample==i and p.motionEnabled and p.cloudElapsed>previous)
 assert(p.hostClock>p.cloudElapsed-.001 and p.cloudStep>=0 and p.cloudStep<.22)
 assert(p.ownedMaterial==p.drawMaterial and p.ownedMaterial:find("Vector4:"))
 assert(p.settingMotion=="true" and p.settingQuality=="high")
 previous=p.cloudElapsed
end
assert(reads==36)
for i=1,100 do p=a:Probe();assert(p.motionSample==nil)end
assert(reads==36 and a.motionProbeSamples==6)
-- Detect wrong binding without changing either material or animation.
a.motionProbeSamples=0
local wrong=Material:new();wrong.params.cloud_wind=Vector4(0,0,0,0);getters(wrong)
a.clouds.geometry[1].material=wrong
p=a:Probe();assert(p.drawMaterial~=p.ownedMaterial)
-- Missing/loading/disposed/binding API failure are bounded safe observations.
a.clouds.geometry[1].GetMaterial=function()error("fixture binding unavailable")end
p=a:Probe();assert(p.drawMaterial=="binding-readback-error")
a.clouds.material.GetShaderParameter=function()error("fixture getter unavailable")end
p=a:Probe();assert(p.ownedMaterial=="readback-error")
local c=a.clouds;a.clouds=nil;p=a:Probe();assert(not p.motionEnabled and p.cloudElapsed==0)
a.clouds=c;logger.enabled=false
settings.Set("cloudMotion",false);local t=c.elapsed
for i=1,600 do a:Update(1/60,Vector3.ZERO,nil)end
assert(c.elapsed==t and a:Probe().motionSample==nil)
a:Stop()
''')
before=(ROOT/"validation/sky-fx/web-still/SkyAtmosphere.before.lua.txt").read_text()
after=(ROOT/"scripts/ruins/SkyAtmosphere.lua").read_text()
assert before.split("function M:Update",1)[1].split("-- 只被DebugLog",1)[0]==after.split("function M:Update",1)[1].split("-- 只被DebugLog",1)[0]
assert (ROOT/"assets/Shaders/BLGL/RuinsCloud.shader").read_bytes()==(ROOT/"validation/sky-fx/web-still/RuinsCloud.shader.online.txt").read_bytes()
assert (ROOT/"scripts/ruins/SkyClouds.lua").read_bytes()==(ROOT/"validation/sky-fx/web-still/SkyClouds.decoded.lua.txt").read_bytes()
print("PASS disabled=0 getter calls; enabled <=6 snapshots/36 getters; owned vs bound material discrepancy; unavailable APIs safe; Update/shader/SkyClouds unchanged")
