from pathlib import Path
from lupa.lua54 import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
package.path='scripts/?.lua;'..package.path
local cm={}
function cm:Lerp(b,t) return Color(self.r+(b.r-self.r)*t,self.g+(b.g-self.g)*t,self.b+(b.b-self.b)*t) end
function Color(r,g,b) return setmetatable({r=r,g=g,b=b},{__index=cm}) end
function Vector3(x,y,z) return {x=x,y=y,z=z,Normalized=function(v) local n=math.sqrt(x*x+y*y+z*z);return {x=x/n,y=y/n,z=z/n} end} end
SKY_CAPTURE_MANUAL=0
''')
s=Path('scripts/ruins/tests/DayNightTest.lua').read_text().split('    local actual = dayNight_')[0]
lua.execute(s+'\nend\nCheckLighting()')
print('PASS existing DayNightTest offline fixtures: capture throttling, fast-forward, locked hour, unsupported capture, midnight wrap')
lua.execute('''
local Old=assert(loadfile('validation/island-void/visual-r1/DayNight.lua'))()
local New=require('ruins.DayNight')
local function fixture(M,h)
 local capture={supported=true,capturing=false,requests=0}
 function capture:RequestCapture() self.requests=self.requests+1 end
 local n={CreateComponent=function(_,name) if name=='SkyLightCapture' then return capture else return {} end end}
 local scene={CreateChild=function() return n end}
 return M.New({scene=scene,zone={},zoneNode=n,sun={},sunNode={},hour=h})
end
local function eq(a,b)
 if type(a)=='table' then for k,v in pairs(a) do assert(type(v)=='function' or eq(v,b[k])) end;return true end
 assert(a==b,tostring(a)..' != '..tostring(b));return true
end
local old,new=fixture(Old,12),fixture(New,12)
assert(new.sky.groundCurve==.28 and old.sky.groundCurve==.06)
for step=0,288 do
 local hour=step/12
 old:SetHour(hour);new:SetHour(hour)
 for _,k in ipairs({'speed','elev','day','dusk','nightK'}) do eq(old[k],new[k]) end
 eq(old.sun,new.sun);eq(old.sunNode,new.sunNode);eq(old.zone,new.zone)
 for _,k in ipairs({'skyCurve','sunDiskSize','sunCurve','skyTopColor','skyHorizonColor','groundHorizonColor','sunEnergy'}) do eq(old.sky[k],new.sky[k]) end
 local c=new.sky.groundBottomColor
 assert(c.r<c.g and c.g<c.b and c.b<=.42 and c.r>=.07)
 assert(new:ClockText()==old:ClockText() and new:PhaseName()==old:PhaseName())
 for _,dt in ipairs({0,1/60,.49,.6,2}) do
  old:Update(dt);new:Update(dt)
  for _,k in ipairs({'hour','lastCapturedHour','captureElapsed','capturePending'}) do eq(old[k],new[k]) end
  eq(old.capture,new.capture)
 end
end
print('PASS 289 time samples: sun/zone/horizon/capture interfaces identical; gray-blue ground palette and wider curve only')
''')
