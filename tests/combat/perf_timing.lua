package.path='scripts/?.lua;'..package.path
local f=assert(io.open('scripts/combat/SwingPerf.lua'));local source=f:read('*a');f:close()
local ms,seconds=0,0
local class={}
function class:GetSystemTime()assert(self==class,'static class receiver required');return ms end
local instance={GetElapsedTime=function()return seconds end}
local logs={}
local env=setmetatable({Time=class,time=instance,print=function(line)logs[#logs+1]=line end},{__index=_G})
local P=assert(load(source,'actual perf clocks','t',env))()
local state={};P.BeginFrame(state);assert(state.swingPerf==true)
P.Context(12,3,'sword_light_3');local start=P.Begin();ms=9;P.Finish('motion',start);P.EndFrame()
assert(#logs==1 and logs[1]:find('stage=motion',1,true) and logs[1]:find('attackId=12',1,true))
for _=1,10 do P.BeginFrame(state);P.motionRays=150;P.EndFrame() end
assert(#logs==1,'static elapsed frame clock limits logs, never times stages')
seconds=.5;P.BeginFrame(state);P.motionRays=150;P.EndFrame();assert(#logs==2)
seconds=.99;P.BeginFrame(state);P.motionRays=150;P.EndFrame();assert(#logs==2)
state.swingPerf=false;seconds=3;P.BeginFrame(state);P.motionRays=150;P.EndFrame();assert(#logs==2 and P.Begin()==nil)
state.swingPerf=true;P.BeginFrame(state);start=P.Begin();ms=0;P.Finish('motion',start);assert(P.stages.motion.ms==0)
print('PASS default-on/disable, correct static versus elapsed clocks, >=8ms threshold, <=2 lines/s, rollback sample discard')
