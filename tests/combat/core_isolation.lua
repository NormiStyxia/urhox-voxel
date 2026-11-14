package.path='scripts/?.lua;'..package.path
local State=require('combat.CombatState')
local now=0
GetTime=function()return {GetSystemTime=function()return now end}end
local savedPrint=print
local logs={}
print=function(text)logs[#logs+1]=text end
local badCount,goodCount=0,0
local function bad()badCount=badCount+1;error('injected failure')end
local function good(a,b)goodCount=goodCount+1;return a,b end
assert(not State.Isolated('Rig.Update',bad))
local ok,a,b=State.Isolated('Audio.Update',good,7,8)
assert(ok and a==7 and b==8 and goodCount==1 and #logs==1)
now=2999;assert(not State.Isolated('Rig.Update',bad) and badCount==1)
now=3000;assert(not State.Isolated('Rig.Update',bad) and badCount==2 and #logs==1)
now=6000;assert(not State.Isolated('Rig.Update',bad) and #logs==2)
now=9000;assert(State.Isolated('Rig.Update',good) and goodCount==2,'automatic retry resumes independently')
GetTime=function()error('clock unavailable')end
assert(State.Isolated('clock-fallback',good),'error isolation cannot fail with missing engine clock')
GetTime=function()return {GetSystemTime=function()return now end}end
State.ResetIsolation()
-- Actual Scene tail: injected Apply and Rig failures cannot suppress AfterPose.
local file=assert(io.open('scripts/ruins/RuinsScene.lua'));local src=file:read('*a');file:close()
local a0=assert(src:find('    if combatAnim_ and (CombatState.InCombat()',1,true))
local b0=assert(src:find('    -- 法阵只更新一次',a0,true))
local count={}
local function tick(name)count[name]=(count[name] or 0)+1 end
local env=setmetatable({Safe=State.Isolated,CombatState={InCombat=function()return true end},
 combatAnim_={Apply=bad},combatMoves_={AfterPose=function()tick('hit')end},animPreview_={index=0},
 UpdateCombatPreviewText=function()tick('debug')end,UpdateCombatRig=bad,dt=.016},{__index=_G})
local tail=assert(load(src:sub(a0,b0-1),'actual Scene combat tail','t',env))
tail();tail();assert(count.hit==2 and count.debug==2,'Apply/Rig failure cannot abort later stages')
-- Actual PostUpdate: base camera failure, sigil failure and combat camera failure
-- must still update HUD and independent FX consumers in that same frame.
local post=assert(src:match('(function Ruins_HandlePostUpdate.-)\nfunction M.Stop'))
env.UpdateBaseCamera=bad;env.UpdateCombatCamera=bad;env.UpdateCombatHUD=function()tick('hud')end
env.M={aim={},sigils={Update=bad}}
env.nomi_={HandPos=function()return 0 end,CameraNode=function()return 0 end}
env.caster_={charge=0};env.Spells={ShatterRadius=function()return 0 end}
env.CombatState.CanUseTime=function()return true end
env.fx_={motesB={Draw=function()tick('b')end},motesG={Draw=function()tick('g')end}}
env.handMotes_={Draw=function()tick('hand')end}
assert(load(post,'actual Scene PostUpdate','t',env))()
local event={TimeStep={GetFloat=function()return .016 end}}
env.Ruins_HandlePostUpdate(nil,event)
assert(count.hud==1 and count.b==1 and count.g==1 and count.hand==1)
-- Perf logs are opt-in; event totals and first HUD sample do not become frame spam.
State.swapPerf=false;local before=#logs
State.BeginSwapPerf();State.PerfCall('animPlay',good);State.EndSwapPerf();State.FlushSwapPerf(true)
assert(#logs==before)
State.swapPerf=true
State.BeginSwapPerf();now=now+2
State.PerfCall('rigSetActive',function()now=now+7 end)
State.PerfCall('animPlay',function()now=now+3 end)
State.EndSwapPerf()
State.PerfCall('hudRebuild',function()now=now+4 end)
State.PerfCall('hudRebuild',function()now=now+100 end)
State.PerfCall('audio',function()now=now+1 end)
State.FlushSwapPerf();assert(#logs==before)
now=now+600;State.FlushSwapPerf()
assert(logs[#logs]:find('total=12.000 rigSetActive=7.000 animPlay=3.000 hudRebuild=4.000 audio=1.000',1,true))
before=#logs;State.FlushSwapPerf();assert(#logs==before)
print=savedPrint
print('PASS isolated cooldown/log limit/recovery/clock fallback, actual Scene animation+camera fault continuation, event-only swap timings')
