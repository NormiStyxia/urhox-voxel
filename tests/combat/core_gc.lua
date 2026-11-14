-- Execute the actual Scene pacing block, without loading an engine Scene.
local f=assert(io.open('scripts/ruins/RuinsScene.lua'));local source=f:read('*a');f:close()
local body=assert(source:match('(%-%- Optional pacing.-)\nM.DEBUG_PANEL'))
local now,cpu,heap=0,0,1024
local pause,mul,steps=200,100,0
local logs,calls={},{}
-- 模拟静态绑定：类表可调用，Time 实例必须拒绝，防止 mock 漏掉接收者错误。
local timeClass={}
function timeClass:GetSystemTime()assert(self==timeClass,'GetSystemTime requires Time class');return now end
local timer=setmetatable({},{__index=timeClass})
local env={Safe=function(_,fn,...)return pcall(fn,...)end,CombatState={FlushSwapPerf=function()end},M={},Time=timeClass,GetTime=function()return timer end,os={clock=function()return cpu end},math=math,string=string,
 print=function(text)logs[#logs+1]=text end,
 collectgarbage=function(action,a,b)
  calls[#calls+1]=action
  assert(action~='generational' and action~='collect','never request full/generational collection')
  if action=='count' then return heap end
  if action=='setpause' then local old=pause;pause=a;return old end
  if action=='setstepmul' then local old=mul;mul=a;return old end
  if action=='incremental' then assert(a==110 and b==300);return 'incremental' end
  if action=='step' then assert(a==8);steps=steps+1;heap=heap-4;cpu=cpu+.00025;return steps%2==0 end
 end}
local api=assert(load(body..'\nreturn {start=StartSceneGC,stop=StopSceneGC,begin=Ruins_HandleGCBeginFrame,finish=Ruins_HandleGCEndFrame}', 'Scene GC pacing','t',env))()
api.start();assert(pause==110 and mul==300)
api.finish();assert(steps==0,'no begin frame, no manual step')
api.begin();now=12;api.finish();assert(steps==1,'12ms frame allowed')
api.finish();assert(steps==1,'duplicate EndFrame cannot double step')
api.begin();now=25;api.finish();assert(steps==1,'13ms frame skips')
env.M.gcDebug=true
api.begin();now=30;api.finish();assert(steps==2 and #logs==0)
api.begin();now=1030;api.finish();assert(steps==2 and #logs==1)
assert(logs[1]:find('steps=2',1,true) and logs[1]:find('maxStepCPUms=0.250',1,true))
env.M.SetGCEnabled(false);assert(pause==200 and mul==100)
api.begin();now=1031;api.finish();assert(steps==2)
env.M.SetGCEnabled(true);api.begin();now=1032;api.finish();assert(steps==3)
api.stop();assert(pause==200 and mul==100 and env.M.gcEnabled)
api.begin();now=2000;api.finish();assert(steps==3,'unloaded scene cannot step')
env.M.gcEnabled=false;api.start();assert(pause==200 and mul==100,'disabled startup leaves global GC parameters intact')
api.begin();now=2001;api.finish();assert(steps==3)
api.stop()
assert(source:find('SubscribeToEvent("BeginFrame", "Ruins_HandleGCBeginFrame")',1,true))
assert(source:find('SubscribeToEvent("EndFrame", "Ruins_HandleGCEndFrame")',1,true))
print('PASS GC: incremental110/300, budget8, >12ms skip, once/frame, debug1Hz, toggle/restore, unloaded/disabled guards')
