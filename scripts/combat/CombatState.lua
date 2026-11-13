-- Single-player combat visibility/lifetime. No physics, damage or TimeObject calls.
-- Aggro is a heartbeat: W3 calls OnEnemyAggro(id) while an enemy is alert/chasing.
local M = { EXPLORE='EXPLORE', IDLE='COMBAT_IDLE', ACTIVE='COMBAT_ACTIVE' }
local state, weapon = M.EXPLORE, 'sword'
local quiet, idle, transition, spellDelay, glow = 0, 0, 0, 0, 1
local mounted, dead, busy = false, false, false
local options = {}
local lastPose = 'hidden'
local readyFlash=0
local settings={aimAssist=true,damageNumbers=false}
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
    state, quiet, idle, glow, transition = M.IDLE, 0, 0, 0, .3
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
    state, quiet, idle, transition, busy = M.EXPLORE, 0, 0, 0, false
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
    state, idle, quiet, transition = M.ACTIVE, 0, 0, 0
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
    if options.rig then options.rig:SetActive(value) end
    if state ~= M.EXPLORE then state = M.IDLE; Pose('back') end
    if options.cancel then options.cancel('weapon') end
    return true
end
---@param dt number
function M.Update(dt)
    dt = math.max(0, dt)
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
        state, transition = M.IDLE, .3
        Pose('back')
    end
end
function M.Stop() M.Exit('stop'); options = {} end

return M
