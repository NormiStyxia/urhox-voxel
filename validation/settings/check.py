from pathlib import Path
from lupa.lua54 import LuaRuntime
import json
lua=LuaRuntime(unpack_returned_tuples=True)
for p in Path('scripts').rglob('*.lua'):
    lua.execute('assert(load(...))',p.read_text())
print('Lua 5.4 syntax: all scripts PASS')
def from_lua(value):
    if hasattr(value,'items'): return {k:from_lua(v) for k,v in value.items()}
    return value
def into_lua(value):
    if isinstance(value,dict): return lua.table_from({k:into_lua(v) for k,v in value.items()})
    if isinstance(value,list): return lua.table_from([into_lua(v) for v in value])
    return value
lua.globals().encode=lambda v:json.dumps(from_lua(v))
lua.globals().decode=lambda v:into_lua(json.loads(v))
lua.execute(r'''
package.path='scripts/?.lua;scripts/?/init.lua;'..package.path
logs={}; print=function(s) logs[#logs+1]=s end
platform='Windows'; GetPlatform=function() return platform end
input={focus=true,minimized=false,numTouches=0,GetKeyDown=function() return false end,GetMouseButtonDown=function() return false end}
receivers={}; nodes=0
function Node()
 nodes=nodes+1
 return {CreateScriptObject=function(self)
  local obj={events={}}
  function obj:SubscribeToEvent(event,fn) self.events[event]=fn end
  function obj:UnsubscribeFromAllEvents() self.events={} end
  receivers[#receivers+1]=obj; return obj
 end, Remove=function() nodes=nodes-1 end}
end
function subscriptions(event)
 local n=0; for _,r in ipairs(receivers) do if r.events[event] then n=n+1 end end; return n
end
function step(dt,times)
 local data={GetFloat=function() return dt end}
 for i=1,(times or 1) do
  -- Snapshot: a callback may dispose its owner or create a new subscription.
  local fs={}; for _,r in ipairs(receivers) do if r.events.Update then fs[#fs+1]={r,r.events.Update} end end
  for _,pair in ipairs(fs) do pair[2](pair[1],nil,data) end
 end
end
cjson={encode=encode,decode=decode}; FILE_READ=0; FILE_WRITE=1
storage=nil; storageMode='ok'; writes=0
function File(path,mode)
 assert(path=='settings.json')
 if storageMode=='throw' then error('unavailable') end
 if storageMode=='nil' then return nil end
 return {IsOpen=function() return storageMode~='closed' and (mode==FILE_WRITE or storage~=nil) end,
 ReadString=function() return storage end,
 WriteString=function(_,s) writes=writes+1; if storageMode=='writefail' then return false end; storage=s; return true end,
 Close=function() end}
end
S=require('ruins.GameSettings'); D=require('ruins.DebugLog')
assert(nodes==0 and subscriptions('Update')==0 and not D.enabled)
S.Load(); assert(S.Get('quality')=='high' and not S.Get('debugLog') and not S.Get('perfHud'))
assert(nodes==0 and subscriptions('Update')==0)
S.TouchDetected(); assert(S.Get('quality')=='medium')
S.Set('quality','high'); S.TouchDetected(); assert(S.Get('quality')=='high')
step(.1,4); assert(writes==0); S.Set('grass','half'); step(.1,4); assert(writes==0)
step(.1,2); assert(writes==1 and nodes==0 and subscriptions('Update')==0)
assert(S.GetProfile().grassDensity==.5)
S.Set('quality','low'); assert(S.GetProfile().grassDensity==.5 and not S.GetProfile().shadowOn)
S.Set('clouds',true); assert(S.GetProfile().cloudsEnabled and S.GetProfile().cloudCount>0)
S.Set('lightShafts',true); S.Set('floatingMotes',true); S.Set('volumetric',true)
assert(S.GetProfile().lightShafts>0 and S.GetProfile().motes>0 and S.GetProfile().volumetric=='full')
S.Set('shadows','high'); S.Set('postFx','full'); assert(S.GetProfile().shadowOn and S.GetProfile().bloom)
S.Set('grass',nil); assert(S.GetProfile().grassDensity==.25)
S.Set('clouds',nil); assert(S.GetProfile().cloudsEnabled and S.GetProfile().cloudCount==4)
assert(not S.Set('quality','ultra') and not S.Set('debugLog',1) and not S.Set('unknown',true))
S.Set('lowClouds',false); S.Set('cloudShadow',false); assert(S.Save()); S.Load(); assert(S.Get('lowClouds')==false and S.Get('cloudShadow')==false); assert(S.Get('quality')=='low' and S.Get('clouds')==nil and S.Get('shadows')=='high')
for _,mode in ipairs({'nil','throw','closed','writefail'}) do
 storageMode=mode; S.Set('quality','medium'); assert(not S.Save()); assert(S.Get('quality')=='medium'); assert(subscriptions('Update')==0)
 S.Load(); assert(S.Get('quality')=='high' or mode=='writefail')
end
storageMode='ok'; storage='broken JSON'; S.Load(); assert(S.Get('quality')=='high')
storage=cjson.encode({version=1,values={quality='ultra',debugLog=3,perfHud=true,grass='bad',unknown=true}})
S.Load(); assert(S.Get('quality')=='high' and S.Get('debugLog')==false and S.Get('perfHud') and S.Get('grass')==nil)
platform='Android'; storage=nil; S.Load(); assert(S.Get('quality')=='medium'); platform='Windows'
S.Load(); local calls=0; local notifications=0
S.RegisterQuality('test',function(p) calls=calls+1; assert(p.quality) end)
local off=S.OnChange(function() notifications=notifications+1 end)
assert(calls==1)
S.Set('perfHud',true); assert(calls==1 and notifications==1)
S.Set('quality','auto'); assert(subscriptions('Update')==1 and S.GetProfile().quality=='high')
step(.05,199); assert(S.GetProfile().quality=='high'); step(.05,50); assert(S.GetProfile().quality=='medium')
step(.05,100); assert(S.GetProfile().quality=='medium'); step(.05,150); assert(S.GetProfile().quality=='low')
step(1/60,1800); assert(S.GetProfile().quality=='low')
S.Set('quality','auto'); S.Set('quality','high'); S.Set('quality','auto')
step(.05,90); step(1/60,180); step(.05,90); assert(S.GetProfile().quality=='high')
S.Set('quality','high'); step(.1,6); assert(subscriptions('Update')==0)
off(); local oldNotifications=notifications; S.Set('perfHud',false); assert(notifications==oldNotifications); step(.1,6)
-- Disabled logging never formats varargs, probes or subscribes. No transient allocation growth.
local probeCalls=0; D.RegisterProbe('probe',function() probeCalls=probeCalls+1; return {count=7} end)
local format=string.format; string.format=function() error('format while disabled') end
for i=1,1000 do D.Log('off','%d',i); D.Warn('off','%d',i) end
string.format=format; assert(probeCalls==0 and nodes==0)
collectgarbage('collect'); collectgarbage('stop'); local mem=collectgarbage('count')
for i=1,10000 do D.Log('off','%d',i); D.SetEnabled(false) end
assert(collectgarbage('count')-mem<1); collectgarbage('restart')
D.SetEnabled(true); assert(subscriptions('Update')==1 and nodes==1)
step(.02,251); assert(probeCalls==1)
for i=1,220 do D.Log('ring','entry %d',i) end
local recent=D.GetRecent(200); assert(#recent==200 and recent[1]:find('entry 21') and recent[200]:find('entry 220'))
D.SetEnabled(false); assert(nodes==0 and subscriptions('Update')==0 and #D.GetRecent()==0)
step(.1,100); assert(probeCalls==1)
S.Stop(); assert(nodes==0)
''')
print('Settings/DebugLog: defaults, storage failures, debounce, overrides, auto hysteresis, opt-in probes/ring/zero disabled allocation PASS')
