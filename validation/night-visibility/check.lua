function vm:Lerp(other,t)return Vector3(self.x+(other.x-self.x)*t,self.y+(other.y-self.y)*t,self.z+(other.z-self.z)*t)end
function Vector4(x,y,z,w)return{x=x,y=y,z=z,w=w}end
function BiasParameters(...)return{...}end
local scene=node('Visibility')
local Terrain=require('ruins.RuinsTerrain')
local Build=require('ruins.RuinsBuild')
local Settings=require('ruins.GameSettings')
local AO=require('ruins.ContactAO')
local DayNight=require('ruins.DayNight')
local dn=DayNight.New({scene=scene,zone={},sun={SetAttribute=function()end},sunNode=node('Sun'),zoneNode=node('Env'),hour=12})
local floorMat,stoneMat,rubble=Material:new(),Material:new(),Material:new()
Terrain.groundMaterial=floorMat
Settings.Load();Settings.Set('quality','high')
local host={zone=dn.zone,sun=dn.sun,dayNight=dn,surfaceMaterials={stone=stoneMat,gateRubble=rubble}}
require('ruins.SceneQuality').Attach(host)
assert(dn.contactAO.layoutSupported,'actual colonnade mismatches shader layout')
assert(rubble.params.contact_ao_strength==nil,'dynamic gate rubble must not acquire static AO uniforms')
assert(stoneMat.params.contact_columns.x==Build.COLONNADE_R)
assert(stoneMat.params.contact_stairs.y==Terrain.STAIR_HALF)
local minimum=10
for k=0,288 do
 dn:SetHour(k/12)
 minimum=math.min(minimum,dn.sun.brightness)
 assert(dn.sun.brightness>=.16 and dn.sun.brightness<=2.20001)
 local direction=dn.sunNode.direction
 assert(math.abs(direction.x^2+direction.y^2+direction.z^2-1)<1e-8)
 assert(dn.zone.envTextureDiffIntensity>=.68 and dn.zone.envTextureDiffIntensity<=1.08001)
 assert(dn.zone.envTextureSpecIntensity>=.38 and dn.zone.envTextureSpecIntensity<=.44001)
 assert(stoneMat.params.contact_ao_strength>=0 and stoneMat.params.contact_ao_strength<=.28001)
 if dn.nightK>=.99 then
  assert(dn.sun.brightness>.80 and stoneMat.params.contact_ao_strength==0)
  assert(dn.sky.skyTopColor.r>=.169 and dn.sky.skyHorizonColor.r>=.239)
 end
end
-- The old sun/moon branch switched direction and colour at elevation -.06.
local hour=18-math.asin(-.06)*12/math.pi
dn:SetHour(hour-1e-6)
local before=dn.sunNode.direction;local color=dn.sun.color;local brightness=dn.sun.brightness
dn:SetHour(hour+1e-6)
assert(math.abs(before.x-dn.sunNode.direction.x)<.0001 and math.abs(before.y-dn.sunNode.direction.y)<.0001)
assert(math.abs(color.r-dn.sun.color.r)<.0001 and math.abs(brightness-dn.sun.brightness)<.0001)
print('PASS 289 hours: finite radiance/normalised direction/nonzero illumination; continuous twilight handover; minimum light',minimum)

dn:SetHour(23)
for _,tier in ipairs({'low','high','medium','low','high'})do
 Settings.Set('quality',tier)
 assert(dn.nightMoon==.82 and dn.nightIBL==1.08)
 assert(dn.sun.brightness>.8199 and dn.zone.envTextureDiffIntensity>1.0799)
 assert(stoneMat.params.contact_ao_strength==0,'AO must remain zero at night through quality changes')
 dn:SetHour(12)
 assert(stoneMat.params.contact_ao_strength==({high=.28,medium=.18,low=0})[tier])
 dn:SetHour(23)
end
local calls=0;local write=stoneMat.SetShaderParameter
stoneMat.SetShaderParameter=function(...)calls=calls+1;return write(...)end
for k=1,10000 do dn.contactAO:Apply(0)end
assert(calls==0,'steady night walks materials')
Settings.Set('quality','low');calls=0
for k=1,10000 do dn.contactAO:Apply(k%100/100)end
assert(calls==0,'low AO still updates uniforms')
Settings.Set('quality','high');dn:SetHour(12)
local original=Build.ColAngle
Build.ColAngle=function(i)return original(i)+.05 end
local mismatch=AO.New({stone=stoneMat},nil)
mismatch:SetQuality(Settings.GetProfile(),1)
assert(not mismatch.layoutSupported and stoneMat.params.contact_ao_strength==0)
Build.ColAngle=original;mismatch:Dispose()
dn.contactAO:Dispose();assert(next(dn.contactAO.materials)==nil)
print('PASS real layout guard, three quality tiers, night/day hot switches, no steady/low material writes, Dispose')

local originalAsync=cache.GetResourceAsync
cache.GetResourceAsync=function(s,kind,path,cb)cb(nil)end
local Fire=require('ruins.NightBraziers')
local fire=Fire.New(scene,{Vector3(0,14,0)},1,1,.25)
assert(not fire.available)
dn:SetHour(23);assert(dn.sun.brightness>.8,'failed fire material must not remove night illumination')
cache.GetResourceAsync=originalAsync
-- No capture support: preserve established preset IBL instead of assuming it is black.
dn.capture.supported=false
dn.zone.envTextureDiffIntensity=.31;dn:SetHour(23)
assert(dn.zone.envTextureDiffIntensity==.31 and dn.sun.brightness>.8)
print('PASS failed/disabled fire independent global night floor; unsupported capture preserves preset')
