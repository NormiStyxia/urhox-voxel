-- Single-player combat visibility/lifetime. No physics, damage or TimeObject calls.
-- Aggro is a heartbeat: W3 calls OnEnemyAggro(id) while an enemy is alert/chasing.
local M = { EXPLORE='EXPLORE', IDLE='COMBAT_IDLE', ACTIVE='COMBAT_ACTIVE' }
local state, weapon = M.EXPLORE, 'sword'
local quiet, idle, transition, spellDelay, glow = 0, 0, 0, 0, 1
local mounted, dead, busy = false, false, false
local options = {}
local lastPose = 'hidden'
local readyFlash=0
local settings={aimAssist=true,damageNumbers=false,dodgeFov=false,cameraShake=true,cameraFov=true,bowZoom=false}
local logTime,logWindow,logCount=0,0,0
local logLast={}
-- Event-only diagnostics: no Update spam, bounded even during a damage burst.
function M.Log(key,format,...)
    if logTime-logWindow>=1 then logWindow,logCount=logTime,0 end
    if logCount>=48 or logTime-(logLast[key] or -100)<.02 then return end
    logLast[key],logCount=logTime,logCount+1
    local write=options.log or print
    write(string.format(format,...))
end
-- Per-subsystem circuit breaker. No per-frame table/closure construction.
local faults={}
local clockKind='system'
local function EngineMilliseconds()
    local timer=time or (GetTime and GetTime())
    if timer and timer.GetSystemTime then return timer:GetSystemTime() end
end
local function Milliseconds()
    local ok,value=pcall(EngineMilliseconds)
    if ok and type(value)=='number' and value==value then clockKind='system';return value end
    clockKind='cpu-fallback'
    return os.clock()*1000
end
function M.ResetIsolation() for key in pairs(faults) do faults[key]=nil end end
function M.Isolated(key,fn,...)
    local now=Milliseconds()
    local fault=faults[key]
    if fault and now<fault.resumeAt then return false end
    local ok,a,b,c,d=pcall(fn,...)
    if ok then return true,a,b,c,d end
    if not fault then fault={lastLog=-math.huge};faults[key]=fault end
    fault.resumeAt=now+3000
    if now-fault.lastLog>=5000 then
        fault.lastLog=now
        local textOK,message=pcall(tostring,a)
        pcall(print,'Isolated error: '..key..' '..(textOK and message or '<unprintable error>'))
    end
    return false
end
-- Event trace only; deferred HUD/audio work is sampled for 600ms after swap.
M.swapPerf=false
local swapPerf={pending=false}
function M.BeginSwapPerf()
    if not M.swapPerf then return end
    M.FlushSwapPerf(true)
    swapPerf.pending=true
    swapPerf.at=Milliseconds()
    swapPerf.total,swapPerf.rigSetActive,swapPerf.animPlay,swapPerf.hudRebuild,swapPerf.audio=0,0,0,0,0
    swapPerf.hudMeasured=false
    swapPerf.accepted=nil
end
function M.EndSwapPerf(accepted)
    if swapPerf.pending then
        swapPerf.total=Milliseconds()-swapPerf.at
        if accepted~=nil then swapPerf.accepted=accepted end
    end
end
function M.PerfCall(part,fn,...)
    if not M.swapPerf or not swapPerf.pending or (part=='hudRebuild' and swapPerf.hudMeasured) then return fn(...) end
    local at=Milliseconds()
    local ok,a,b,c,d=pcall(fn,...)
    swapPerf[part]=swapPerf[part]+math.max(0,Milliseconds()-at)
    if part=='hudRebuild' then swapPerf.hudMeasured=true end
    if not ok then error(a,0) end -- outer subsystem breaker owns the failure
    return a,b,c,d
end
function M.FlushSwapPerf(force)
    if not swapPerf.pending or (not force and Milliseconds()-swapPerf.at<600) then return end
    swapPerf.pending=false
    if M.swapPerf then
        print(string.format('Perf: weaponSwap total=%.3f rigSetActive=%.3f animPlay=%.3f hudRebuild=%.3f audio=%.3f ms window=600 hudSample=%s accepted=%s clock=%s',
            swapPerf.total,swapPerf.rigSetActive,swapPerf.animPlay,swapPerf.hudRebuild,swapPerf.audio,tostring(swapPerf.hudMeasured),tostring(swapPerf.accepted),clockKind))
    end
end
local function SetState(nextState,reason)
    if nextState==state then return end
    M.Log('state:'..state..':'..nextState,'Combat: state %s->%s %s',state,nextState,reason)
    state=nextState
end
function M.GetSetting(key) return settings[key] end
function M.SetSetting(key,value)
    if settings[key]==nil or type(value)~='boolean' then return false end
    settings[key]=value; return true
end

local function Pose(p)
    if p == lastPose then return end
    local previous=lastPose
    lastPose = p
    if options.rig then options.rig:SetPose(p) end
    if options.pose then options.pose(p,previous) end
end
local function Changed(reason)
    if options.cancel then options.cancel(reason) end
    if options.changed then options.changed(state, reason) end
end

---@param opts table|nil rig, cancel(reason), changed(state,reason), say(text)
function M.Configure(opts)
    options = opts or {}
    logTime,logWindow,logCount,logLast=0,0,0,{}
    state, weapon = M.EXPLORE, options.weapon=='bow' and 'bow' or 'sword'
    quiet, idle, transition, spellDelay, glow = 0, 0, 0, 0, 1
    mounted, dead, busy = false, false, false
    readyFlash=0
    lastPose = 'hidden'
    if options.rig then options.rig:SetActive(weapon); options.rig:SetPose('hidden') end
end
function M.Get() return state end
function M.InCombat() return state ~= M.EXPLORE end
function M.GetWeapon() return weapon end
function M.GetPose() return lastPose end
function M.TransitionRemaining() return transition end
function M.FinishTransition() transition=0 end
function M.CanUseTime() return state == M.EXPLORE and spellDelay <= 0 and not mounted and not dead end
function M.Glow() return (mounted or dead) and 0 or glow end
function M.ReadyFlash() return readyFlash>0 end
function M.HasAggro() return options.aggro and options.aggro()==true or false end
function M.CanSheath() return not M.HasAggro() end
function M.SetBusy(value) busy = value == true end
function M.SetRig(rig)
    options.rig = rig
    if rig then rig:SetActive(weapon); rig:SetPose(lastPose) end
end

---@param reason string|nil
function M.Enter(reason)
    if mounted or dead then return false end
    if state ~= M.EXPLORE then return true end
    SetState(M.IDLE,reason or 'manual')
    quiet, idle, glow, transition = 0, 0, 0, .3
    Pose('back')
    Changed(reason or 'manual')
    if options.say then options.say('拔刃 · 时间之力暂息') end
    return true
end
---@param reason string|nil
function M.Exit(reason)
    if reason=='manual' and M.InCombat() and not M.CanSheath() then
        if options.say then options.say('仍在交战') end
        return false
    end
    local wasCombat = state ~= M.EXPLORE
    SetState(M.EXPLORE,reason or 'manual')
    quiet, idle, transition, busy = 0, 0, 0, false
    if wasCombat then spellDelay, glow = 1, 0 end
    Pose('hidden')
    -- Force paths also clear held input when already exploring.
    if wasCombat or reason == 'mount' or reason == 'death' or reason == 'stop' then Changed(reason or 'manual') end
    if wasCombat and options.say and reason ~= 'stop' then options.say('收刃 · 时间之力恢复中') end
end
function M.OnEnemyAggro(enemyId)
    if enemyId == nil or mounted or dead then return end
    M.Enter('aggro'); quiet = 0
end
function M.OnPlayerHit()
    if mounted or dead then return end
    M.Enter('hit'); quiet = 0
end
-- Called by accepted combat moves, not by ordinary exploration LMB/1.
---@param cancelTransition boolean|nil Dodge can interrupt draw/sheath.
function M.Activity(cancelTransition)
    if not M.Enter('attack') then return false end
    if transition > 0 and not cancelTransition then return false end
    SetState(M.ACTIVE,'attack')
    idle, quiet, transition = 0, 0, 0
    Pose('hand')
    return true
end
function M.SetMounted(value)
    if value == mounted then return end
    mounted = value == true
    if mounted then M.Exit('mount') end
end
function M.SetDead(value)
    dead = value == true
    if dead then M.Exit('death') end
end
function M.SetWeapon(value)
    if value ~= 'sword' and value ~= 'bow' then return false end
    if value == weapon then return true end
    if busy or transition > 0 or mounted or dead then return false end
    weapon, transition, idle = value, .4, 0
    if options.rig then M.PerfCall('rigSetActive',options.rig.SetActive,options.rig,value) end
    if state ~= M.EXPLORE then SetState(M.IDLE,'weapon'); Pose('back') end
    if options.cancel then options.cancel('weapon') end
    return true
end
---@param dt number
function M.Update(dt)
    dt = math.max(0, dt)
    logTime=logTime+dt
    transition = math.max(0, transition - dt)
    local previousDelay=spellDelay
    spellDelay = math.max(0, spellDelay - dt)
    readyFlash=math.max(0,readyFlash-dt)
    if previousDelay>0 and spellDelay==0 then readyFlash=.12 end
    if state == M.EXPLORE then
        if spellDelay>0 then glow=0
        else glow = math.min(1, glow + math.max(0,dt-previousDelay) / .4) end
        return
    end
    glow = 0
    quiet = quiet + dt
    if not busy then idle = idle + dt else idle = 0 end
    if quiet >= 6 and not busy then M.Exit('quiet'); return end
    if state == M.ACTIVE and idle >= 2.5 then
        SetState(M.IDLE,'idle'); transition = .3
        Pose('back')
    end
end
function M.Stop() M.Exit('stop'); options = {} end

return M
