-- Player combat. Animation events are the only hit/cancel/fire clock.
-- Dependencies are injected so collision, cancellation and death can run offline.
local Hit=require('combat.Hit')
local Perf=require('combat.SwingPerf')
local Data=require('combat.AnimClips')
local Stamina=require('combat.Stamina')
local COMBO=Data.Combo
---@class PlayerCombatMoves
---@field o table
---@field anim table Animation port (real CombatAnim or offline event stub).
---@field state table
---@field rig table
---@field moveDir Vector3|nil
---@field motion Vector3
---@field playParams table
---@field playOpts table
---@field airState table
---@field plungeVelocity Vector3
---@field soundOpts table
---@field fireSnapshot table
---@field pendingFire table|nil
---@field feedbackPool table[]
---@field partNoticePool {part:string,untilTime:number}
---@field numberPool table[]
---@field numbers table[]
---@field damaged table
---@field queryHits table[]
---@field queryPool table[]
---@field slamHits table[]
---@field slamPool table[]
---@field queryShapes table
---@field feedbackGroups table
---@field eventPool table[]
---@field observe fun(kind:string, data:table)|nil
---@field partNotice {part:string,untilTime:number}|nil
---@field strikeTarget table|nil Assist-selected melee target for the current swing.
---@field motionScale number|nil Lunge scale so a dash stops short of its target.
---@field stamina CombatStamina Combat-only stamina (sprint, cross slash, plunge).
local C={}; C.__index=C
C.COMBO_LENGTH=Data.ComboLength
-- Real seconds; frame-average velocity integrates across hover/terminal boundaries.
C.PLUNGE={hover=.10,initialSpeed=6,terminalSpeed=12,accelerationTime=.25}
function C.PlungeDistance(age)
    local p=C.PLUNGE
    local t=math.max(0,age-p.hover);local a=math.min(t,p.accelerationTime)
    return p.initialSpeed*a+(p.terminalSpeed-p.initialSpeed)*a*a/(2*p.accelerationTime)
        +p.terminalSpeed*math.max(0,t-p.accelerationTime)
end
local BUFFER=.160
-- Holding attack this long fires the cross slash at once (no charge levels).
local HEAVY_HOLD=.40
C.HEAVY_HOLD=HEAVY_HOLD
local RING_EVENT={material='stone',kind='dust'}
-- Immutable after module initialization. Special outcomes inherit the source
-- stop; a weak point/kill does not silently upgrade the approved 40/80ms.
local PROFILES={}
local SOURCES={
    light_1={.04,.01,.06,0,.06,.85},light_2={.04,.01,.06,0,.06,.85},
    third={.04,.015,.08,0,.08,.95},spin={.06,.02,.09,0,.08,.95},finisher={.09,.03,.12,0,.10,1},plunge={.10,.03,.12,0,.10,1},heavy={.08,.025,.10,2,.08,1},full={.08,.025,.10,2,.10,1},
    arrow_weak={.03,0,0,0,.05,.75},arrow_mid={.03,0,0,0,.06,.85},arrow_full={.03,0,0,0,.07,.95},
}
for source,v in pairs(SOURCES) do
    local variants={}
    for _,outcome in ipairs({'source','critical','kill','stagger','break'}) do
        local impact=outcome=='break' or outcome=='stagger'
        variants[outcome]={id=outcome=='source' and source or outcome,
            stop=outcome=='break' and .10 or v[1],amp=impact and .03 or v[2],
            duration=impact and .12 or v[3],fov=v[4],
            flash=math.max(v[5],outcome=='source' and 0 or (outcome=='critical' and .09 or .10)),
            peak=outcome=='source' and v[6] or 1}
    end
    PROFILES[source]=variants
end
local ARROW_TIERS={weak='arrow_weak',mid='arrow_mid',full='arrow_full'}
local function Profile(e,info,arrow)
    local source=arrow and (ARROW_TIERS[info.tier] or 'arrow_weak')
        or (info.plunge and 'plunge') or (info.heavy and (e.full and 'full' or 'heavy') or (COMBO[e.combo] or COMBO[1]).profile)
    local outcome=e.broke and 'break' or (e.staggered and 'stagger' or (e.killed and 'kill' or (e.critical and 'critical' or 'source')))
    return PROFILES[source][outcome]
end
local function Flat(v,fallback)
    local d=Vector3(v.x,0,v.z)
    return d:LengthSquared()>.0001 and d:Normalized() or fallback
end
-- Intent is independent of body yaw. Select once, never track during a strike.
function C.SelectMeleeTarget(position,intent,enemies,cast)
    intent=Flat(intent,Vector3.FORWARD)
    local best,bestDir,bestScore=nil,intent,math.huge
    local origin=position+Vector3(0,.9,0)
    for _,enemy in ipairs(enemies) do
        if enemy.active~=false and not enemy.dead and enemy.position then
            local delta=enemy.position-position --[[@as Vector3]]
            local distance=math.sqrt(delta.x*delta.x+delta.z*delta.z)
            if distance>.001 and distance<=3.6 and math.abs(delta.y)<=2 then
                local direction=Flat(delta,intent)
                local dot=direction:DotProduct(intent)
                local limit=distance<=1.5 and 0 or math.cos(math.rad(75))
                if dot>=limit and Hit.Visible(origin,enemy.position+Vector3(0,.9,0),cast) then
                    local score=(1-dot)*2+distance/3.6
                    if score<bestScore then best,bestDir,bestScore=enemy,direction,score end
                end
            end
        end
    end
    return bestDir,best
end
-- Physical ground port returns height, normal.y. Nine probes cover the centre
-- and expanded footprint; no endpoint-only jump across a narrow gap.
function C.SlideFootprint(p,radius,ground)
    local y,ny=ground(p)
    if not y or (ny or 0)<math.cos(math.rad(35)) or math.abs(y-p.y)>.20+1e-6 then return nil end
    local margin=radius+.10
    for i=0,7 do
        local a=i*math.pi/4
        local h,n=ground(Vector3(p.x+math.sin(a)*margin,y,p.z+math.cos(a)*margin))
        if not h or (n or 0)<math.cos(math.rad(35))
            or math.abs(h-y)>margin*math.tan(math.rad(35))+.001 then return nil end
    end
    return y
end
local function SlideSafe(base,dir,distance,height,radius,ground,clear)
    local q=base+dir*distance
    local h=C.SlideFootprint(q,radius,ground)
    if not h or math.abs(h-height)>.20+1e-6
        or (clear and not clear(base,Vector3(q.x,h,q.z),radius+.10)) then return nil end
    return h
end
function C.ClipSlidePath(p,motion,radius,ground,clear,maxSteps)
    local height=C.SlideFootprint(p,radius,ground)
    if not height then return Vector3.ZERO,true,0 end
    local flat=Vector3(motion.x,0,motion.z)
    local length=flat:Length()
    if length<1e-8 then return Vector3.ZERO,false,0 end
    local dir=flat/length
    local done,steps=0,0
    while done<length-1e-8 and steps<(maxSteps or math.huge) do
        local amount=math.min(.10,length-done)
        local base=Vector3(p.x+dir.x*done,height,p.z+dir.z*done)
        local nextHeight=SlideSafe(base,dir,amount,height,radius,ground,clear)
        steps=steps+1;Perf.substeps=Perf.substeps+1
        if not nextHeight then
            local lo,hi=0,amount
            -- .10 / 2^3 <= .02: same refinement with an explicit ceiling.
            for _=1,3 do
                if hi-lo<=.02 then break end
                local mid=(lo+hi)*.5
                if SlideSafe(base,dir,mid,height,radius,ground,clear) then lo=mid else hi=mid end
            end
            return dir*(done+lo),true,0
        end
        done,height=done+amount,nextHeight
    end
    return dir*done,false,math.max(0,length-done)
end
---@param opts table
---@return PlayerCombatMoves
function C.New(opts)
    local self=setmetatable({o=opts,anim=opts.anim,state=opts.state,rig=opts.rig,hp=100,maxHP=100,
        age=0,invuln=0,hitstop=0,charge=0,hold=0,combo=0,drawElapsed=0,power=0,fireSnapshot={stats={}},
        motion=Vector3.ZERO,buffer=nil,bufferUntil=0,hitOpen=false,hitPending=false,
        cancelOpen=false,damaged={},dead=false,blocked=false,
        lastAttack=false,lastHeavy=false,shake=0,shakeAge=0,shakeDuration=0,
        eventPool={{},{},{},{},{},{},{},{}},eventWrite=0,swingSerial=0,feedbackGroups={},
        strikeZone={origin=Vector3(0,0,0),source=Vector3(0,0,0)},
        slamZone={origin=Vector3(0,0,0),source=Vector3(0,0,0)},
        queryHits={},queryPool={},slamHits={},slamPool={},queryShapes={},playParams={},playOpts={},airState={},plunging=false,plungeLanded=false,plungeVelocity=Vector3.ZERO},C)
    self.feedbackPool,self.numberPool,self.numbers,self.soundOpts={},{},{},{}
    self.partNoticePool={part='',untilTime=0}
    for i=1,32 do self.feedbackPool[i]={at=-math.huge,amp=0,duration=0,fov=0,stop=0,dir=Vector3()} end
    for i=1,12 do self.numberPool[i]={} end
    for _,e in ipairs(self.eventPool) do e.audio={};e.impactDir=Vector3() end
    self.shakeVector=Vector3()
    self.stamina=Stamina.New()
    self.feedbackWrite,self.numberWrite=0,0
    return self
end
-- Injected sound port keeps offline simulations engine-independent.
function C:Sound(name,opts)
    if self.o.audio then
        if not opts then self.soundOpts.pos=self.o.position() end
        local _,handle=self.state.Isolated('Audio.Play',self.state.PerfCall,'audio',self.o.audio.Play,name,opts or self.soundOpts)
        return handle
    end
end
function C:StopDrawSound()
    if self.drawSound and self.o.audio then self.state.Isolated('Audio.Stop',self.o.audio.Stop,self.drawSound) end
    self.drawSound=nil
end
function C:Flash(kind)
    if self.rig.Flash then self.rig:Flash(kind) end
end
function C:WeaponInHand()
    return (self.rig.pose or self.state.GetPose())=='hand'
end
-- 剑由低位 IK 管手臂，基础层保持空手姿态，收剑时才不会露出旧前举。
function C:BaseArmed()
    return self:WeaponInHand() and self.state.GetWeapon()=='bow'
end
function C:Play(id,fadeIn,entryFrom)
    if self.bowCancelHandle then self.anim:Stop(self.bowCancelHandle,0);self.bowCancelHandle=nil end
    local stats=self.rig:GetStats()
    -- Scale the clip clock; charge_full remains the sole full-charge signal.
    local speed=1
    local params=self.playParams
    for k in pairs(params) do params[k]=nil end
    params.weaponInHand=self:WeaponInHand() and 1 or 0
    if id=='plunge_loop' then
        params.plungeSpeed=(self.plungeSpeed or 6)/C.PLUNGE.terminalSpeed
        params.plungeTuck=math.max(0,1-(self.airState.height or 1)/.4)
    end
    if id=='bow_release' or id=='bow_cancel' then
        self.bowPoseCharge=self.charge
        self.bowPosePitch=math.max(-35,math.min(35,self.o.aimPitch and self.o.aimPitch() or 0))
        self.bowPoseFacing=Flat(self.o.forward(),Vector3.FORWARD)
        params.p,params.aimPitch=self.bowPoseCharge,self.bowPosePitch
    end
    local opts=self.playOpts
    opts.stats,opts.speed,opts.fadeIn,opts.params,opts.entryFrom=stats,speed,fadeIn,params,entryFrom
    local handle=self.state.PerfCall('animPlay',self.anim.Play,self.anim,id,opts)
    if not handle then return false end
    self.clip,self.handle=id,handle
    self.whoosh,self.whooshTime=false,0
    if id:find('sword_light_',1,true) or id=='sword_heavy_release' then
        self.swingSerial=self.swingSerial+1
    elseif id=='bow_draw' then
        self.bowFullAt=nil
        self:StopDrawSound(); self.drawSound=self:Sound('bow_draw')
    elseif id=='bow_release' then self:StopDrawSound() end
    self.clipStartedAt=self.age
    if self.observe then self.observe('start',{clip=id,age=self.age}) end
    if self.state.Log then self.state.Log('clip-start:'..id,'Combat: clip %s start',id) end
    self.hitOpen,self.hitPending,self.cancelOpen=false,false,false
    for key in pairs(self.damaged) do self.damaged[key]=nil end
    self.previousHit=nil
    self.motionDebt=0
    self.hitForward=(id:find('sword_light_',1,true) or id=='sword_heavy_release') and self.moveDir or nil
    self.cut=0 -- hit windows opened by this clip (cross slash has two)
    self.state.SetBusy(true)
    return true
end
function C:Cancel(reason,keepProtection)
    if self.o.locomotion then self.o.locomotion:Cancel(reason) end
    local softReason=reason=='blocked' or reason=='focus' or reason=='touch-clear' or reason=='touchcancel' or reason=='menu'
    -- A focus/touch callback may be followed by the blocked-input pass in the
    -- same frame. Do not restart or erase the already-safe cosmetic tail.
    if softReason and not self.clip and self.bowCancelHandle and self.anim:IsPlaying('bow_cancel') then return end
    local drawing=self.clip=='bow_draw' or self.clip=='bow_hold'
    local soft=drawing and softReason
    local charge,pitch=self.charge,math.max(-35,math.min(35,self.o.aimPitch and self.o.aimPitch() or 0))
    if self.bowCancelHandle then self.anim:Stop(self.bowCancelHandle,0) end
    self.bowCancelHandle=nil
    if self.o.camera then self.o.camera:Cancel() end
    local cancelledHandle=self.handle
    self:StopDrawSound()
    self.motionChecked=false
    self.combo,self.comboUntil=0,nil
    if self.clip=='bow_draw' or self.clip=='bow_hold' or self.pendingFire~=nil then
        if self.rig.CancelBow then self.rig:CancelBow() end
        self.cancelUntil=self.age+1.2
        if self.state.Log then self.state.Log('arrow-cancel','Combat: arrow cancel %s',reason or 'unknown') end
    end
    self.plunging,self.plungePeak,self.plungeLanded=false,nil,false
    if self.rig.SetPlunging then self.rig:SetPlunging(false) end
    self.buffer,self.pending,self.clip,self.handle=nil,nil,nil,nil
    self.motionDebt=0
    self.pendingFire=nil
    self.drawElapsed,self.power=0,0
    self.trailUntil=0
    self.autoFire,self.pendingReleased=false,false
    if not keepProtection then self.protection={} end
    self.drawFullReached,self.fireCrystal,self.fireCharge,self.fullCharged=false,false,nil,false
    self.hitOpen,self.hitPending,self.cancelOpen=false,false,false
    self.hold,self.charge,self.motion,self.knock=0,0,Vector3.ZERO,0
    self.lastAttack,self.lastHeavy,self.blocked=false,false,true
    if keepProtection then
        if cancelledHandle then self.anim:Stop(cancelledHandle,0) end
    else self.anim:Stop(nil,0) end
    if self.rig.StopCombatVisual then self.rig:StopCombatVisual() end
    self.state.PerfCall('rigSetActive',self.rig.SetActive,self.rig,self.state.GetWeapon()); self.rig:SetPose(self.state.GetPose())
    if not self.draining and not keepProtection then self.anim:Poll() end
    self.state.SetBusy(false)
    if self.o.clear then self.o.clear(reason) end
    -- Cosmetic release only: no attack handle, charge, pending arrow or busy lock.
    -- Hit/swap/death/exit replace the pose immediately as before.
    if soft and self.state.InCombat() and not self.dead then
        self.bowPoseCharge,self.bowPosePitch=charge,pitch
        self.bowCancelHandle=self.anim:Play('bow_cancel',{params={p=charge,aimPitch=pitch}})
    end
end
-- Jump interrupts any light-combo stage at any time. Soft: the attack pose
-- blends out over .10s instead of snapping, and the next press in the air
-- becomes a plunge. Heavy, charge, plunge and bow keep their own commitments.
function C:JumpCancel()
    local clip=self.clip
    if not clip or not clip:find('sword_light_',1,true) then return false end
    return self:SoftStop('jump')
end
-- Recovery (after cancel_open) is follow-through inertia, not a lock: any
-- move/sprint intent ends it with a soft blend. Heavy release included.
function C:RecoveryCancel(reason)
    local clip=self.clip
    if not clip or not self.cancelOpen or self.hitOpen then return false end
    if not (clip:find('sword_light_',1,true) or clip=='sword_heavy_release') then return false end
    return self:SoftStop(reason)
end
function C:SoftStop(reason)
    local clip=self.clip
    if self.state.Log then self.state.Log(reason..'-cancel','Combat: %s cancels %s',reason,clip) end
    self.anim:Stop(self.handle,reason=='move' and .18 or .10)
    self.clip,self.handle=nil,nil
    self.hitOpen,self.hitPending,self.cancelOpen=false,false,false
    self.motion,self.motionDebt,self.motionScale=Vector3.ZERO,0,1
    self.buffer,self.pending=nil,nil
    -- Moving out of recovery keeps the chain alive for the usual window; a jump resets it.
    if reason=='jump' then self.combo,self.comboUntil=0,nil
    elseif not self.comboUntil then self.comboUntil=self.age+.75 end
    self.state.SetBusy(false)
    return true
end
function C:BowParameters(pitch)
    if self.clip=='bow_release' or self.clip=='bow_cancel'
        or (self.bowCancelHandle and self.anim:IsPlaying('bow_cancel')) then
        return self.bowPoseCharge or 0,self.bowPosePitch or 0
    end
    return self.state.GetWeapon()=='bow' and self.charge or 0,math.max(-35,math.min(35,pitch or 0))
end
function C:CanCancel()
    return not self.clip or self.cancelOpen or (self.clip=='plunge_land' and self.age-(self.landedAt or self.age)>=.25-1e-8) or self.clip=='sword_heavy_charge'
        or self.clip=='bow_hold' or self.clip=='bow_draw' or self.clip=='sword_draw' or self.clip=='sword_sheath'
        or self.clip=='bow_equip' or self.clip=='bow_sheath'
end
function C:Facing()
    if self.clip=='bow_release' then return self.bowPoseFacing end
    if self.plunging or self.clip=='plunge_land' then return self.moveDir end
    return self.clip and (self.clip:find('sword_light_',1,true) or self.clip=='sword_heavy_release' or self.clip=='sword_heavy_charge') and self.moveDir or nil
end
-- Borrowed ground/velocity record is refreshed by the controller without rays.
function C:Air()
    if self.o.airState then return self.o.airState(self.airState) end
    return nil
end
function C:StartPlunge(air)
    if self.plunging or self.clip=='plunge_land' or self.state.GetWeapon()~='sword'
        or air.onGround or air.invalid or (air.height or 0)<.6 then return false end
    if not self:CanCancel() then return false end
    if not self.stamina:Spend('plunge') then return false,'stamina' end
    if self.handle then self.anim:Stop(self.handle,.04) end
    if self.o.locomotion then self.o.locomotion:Cancel('attack') end
    self.state.Activity(true);self.rig:SetPose('hand')
    self.moveDir=Flat(self.o.forward(),Vector3.FORWARD)
    self.combo,self.comboUntil,self.pending,self.hold,self.charge=0,nil,nil,0,0
    self.releaseFull,self.autoFire=false,false
    if not self:Play('plunge_start',.04) then return false end
    self.plunging,self.plungePeak,self.plungeLanded=true,air.y,false
    self.plungeVelocity=Vector3(air.vx or 0,0,air.vz or 0)
    self.plungeAge,self.plungeSpeed=0,0
    if self.rig.SetPlunging then self.rig:SetPlunging(false) end
    self.buffer=nil
    return true
end
function C:UpdatePlunge(dt)
    if not self.plunging then return end
    local air=self:Air()
    if not air or air.invalid then self:Cancel('void');return end
    self.plungePeak=math.max(self.plungePeak or air.y,air.y)
    if not air.onGround then
        local old=self.plungeAge or 0
        self.plungeAge=old+math.max(0,dt or 0)
        self.plungeSpeed=dt and dt>0 and (C.PlungeDistance(self.plungeAge)-C.PlungeDistance(old))/dt or 0
        -- Vector3 是值类型：整体写回速度，分量赋值只会修改副本。
        local velocity=self.plungeVelocity
        self.plungeVelocity=Vector3(velocity.x,-self.plungeSpeed,velocity.z)
        if self.rig.SetPlunging then self.rig:SetPlunging(self.plungeSpeed>0) end
        if self.anim.SetParam and self.handle then
            self.anim:SetParam('plungeSpeed',self.plungeSpeed/C.PLUNGE.terminalSpeed)
            self.anim:SetParam('plungeTuck',math.max(0,1-(air.height or 1)/.4))
        end
        return
    end
    if self.rig.SetPlunging then self.rig:SetPlunging(false) end
    self.plunging,self.plungeLanded=false,true
    self.plungeMultiplier=math.min(2.2,1.4+math.max(0,self.plungePeak-air.y)*.1)
    if self.handle then self.anim:Stop(self.handle,0) end
    self:Play('plunge_land',0)
    self.swingSerial=self.swingSerial+1
    self.hitForward=self.moveDir
    self.landedAt=self.age
    self:Envelope('plunge:'..self.swingSerial,.03,.12,0,Vector3(0,-1,0),.10)
    if self.o.camera then self.o.camera:Land() end
    if self.rig.ImpactFx then self.rig:ImpactFx(self.o.position(),self.moveDir,true)
    elseif self.o.impactRing then self.o.impactRing(self.o.position(),self.moveDir) end
    local sound=self.soundOpts
    sound.pos,sound.tier,sound.pitch,sound.hitId=self.o.position(),'heavy',.8,'plunge:'..self.swingSerial
    self:Sound('hit_heavy',sound);sound.material='stone';self:Sound('arrow_hit',sound)
    sound.tier,sound.pitch,sound.material,sound.hitId=nil,nil,nil,nil
end
function C:Action(kind,axis,entryFrom)
    if self.dead then return false,'dead' end
    if self.comboCooldownUntil and self.age<self.comboCooldownUntil-1e-8 then return false,'recovery' end
    if kind~='light' and kind~='heavy' and kind~='hold' then return false,'unknown-action' end
    if not self.state.InCombat() then return false,'explore' end
    local air=self:Air()
    if self.state.GetWeapon()=='sword' and air and not air.onGround and (air.height or 0)>=.6 then return self:StartPlunge(air) end
    if self.plunging then return false,'air-attack' end
    if self.o.locomotion and self.o.locomotion:IsRunning() then self.o.locomotion:Cancel('attack') end
    if self.clip=='plunge_land' and self:CanCancel() then
        self.anim:Stop(self.handle,.04);self.clip,self.handle=nil,nil
    end
    if self.clip and self.cancelOpen and (self.clip:find('sword_light_',1,true) or self.clip=='sword_heavy_release') then
        if kind=='light' and Data.Clips[self.clip].comboEntry then entryFrom=self.handle end
        self.anim:Stop(self.handle,entryFrom and .08 or .04); self.clip,self.handle=nil,nil
    end
    if self.state.TransitionRemaining()>0 then return false end
    if self.clip then return false end
    if self.state.GetPose()~='hand' then
        self.combo=0
        if not self.state.Activity(true) then return false end
        self.pending,self.pendingReleased=kind,false
        self.hold,self.charge=0,0
        self.autoFire=kind=='heavy' and self.state.GetWeapon()=='bow'
        if self.state.GetWeapon()=='bow' then
            -- Equip and draw begin together; no queued short tap after taking bow.
            self.pending=nil
            self.drawElapsed,self.power,self.drawFullReached=0,0,false
            return self:Play('bow_draw',.04)
        end
        self:Play(self.state.GetWeapon()=='sword' and 'sword_draw' or 'bow_equip')
        return true
    end
    self.state.Activity(true)
    local intent=axis or self.inputAxis or Vector3.ZERO
    if intent:LengthSquared()<.18*.18 then intent=self.o.intent and self.o.intent() or self.o.forward() end
    self.moveDir=Flat(intent,Vector3.FORWARD)
    if self.state.GetWeapon()=='sword' and self.o.assist then
        self.moveDir,self.strikeTarget=self.o.assist(self.moveDir,kind~='hold')
        self.moveDir=self.moveDir or Flat(intent,Vector3.FORWARD)
    end
    local bow=self.state.GetWeapon()=='bow'
    if bow then
        self.charge,self.autoFire,self.pendingReleased=0,kind=='heavy',kind=='light'
        self.drawElapsed,self.power=0,0
        self.drawFullReached,self.fireCrystal,self.fireCharge=false,false,nil
        return self:Play('bow_draw')
    elseif kind=='heavy' and self.stamina:Spend('heavy') then
        self.autoFire=false; self.combo=0
        return self:Play('sword_heavy_release') and self:LimitLunge('sword_heavy_release')
    elseif kind=='hold' then self.hold,self.charge,self.fullCharged=0,0,false; return self:Play('sword_heavy_charge')
    else
        -- Light stage; also the fallback when a cross slash cannot be paid for.
        if self.comboUntil and self.age>self.comboUntil then self.combo=0 end
        self.comboUntil=nil
        self.combo=self.combo%C.COMBO_LENGTH+1
        return self:Play(COMBO[self.combo].id,entryFrom and .08 or nil,entryFrom) and self:LimitLunge(COMBO[self.combo].id)
    end
end
-- Dashes and leaps stop STOP_GAP short of the nearest target in front instead
-- of carrying the player through it; with no target the full authored step plays.
local STOP_GAP=1.0
function C:LimitLunge(id)
    self.motionScale=1
    local total=0
    for _,m in ipairs(Data.Clips[id].motion) do total=total+m.forward end
    if total<=0 then return true end
    local target=self.strikeTarget
    if not target and self.o.enemies then
        local _,nearest=C.SelectMeleeTarget(self.o.position(),self.moveDir or self.o.forward(),self.o.enemies(),self.o.cast)
        target=nearest
    end
    if target and target.position then
        local p=self.o.position()
        local dx,dz=target.position.x-p.x,target.position.z-p.z
        self.motionScale=math.max(0,math.min(1,(math.sqrt(dx*dx+dz*dz)-STOP_GAP)/total))
    end
    return true
end
function C:Release()
    if self.clip=='sword_heavy_charge' then
        local heavy=self.hold>=HEAVY_HOLD-1e-8 -- gesture classification, not a damage window
        self.holdSource=nil;self.releaseFull=false
        local entryFrom=not heavy and self.handle or nil
        self.anim:Stop(self.handle,entryFrom and .08 or 0); self.clip=nil
        self:Action(heavy and 'heavy' or 'light',nil,entryFrom)
    elseif self.clip=='bow_hold' or self.clip=='bow_draw' then
        local power=(self.charge*self.charge+2*self.charge)/3
        if power<.1 or not self:WeaponInHand() then
            self:Cancel('weak-release');return
        end
        self.fireCharge=self.charge
        self.fireCrystal=self.autoFire==true
        local shot=self.fireSnapshot
        shot.u,shot.power,shot.critical=self.charge,power,self.charge>=1
        shot.pitch=math.max(-35,math.min(35,self.o.aimPitch and self.o.aimPitch() or 0))
        shot.facing=Flat(self.o.forward(),Vector3.FORWARD)
        if self.o.captureBowShot then self.o.captureBowShot(shot) end
        for key in pairs(shot.stats) do shot.stats[key]=nil end
        for key,value in pairs(self.rig:GetStats()) do shot.stats[key]=value end
        if self.fireCrystal then shot.stats.crystalRadius,shot.stats.crystalDamageMultiplier=.8,.25 end
        self:Play('bow_release')
        self.pendingFire=shot -- release authority; the clip's fire cue cannot create a second shot
    elseif self.pending=='hold' then self.pending,self.pendingReleased='light',true end
end
-- Group envelopes start at FIRST contact: later targets raise the maximum,
-- never restart or add shakes. Bounded storage, including long-lived arrows.
function C:Envelope(key,amp,duration,fov,dir,stop)
    local group=self.feedbackGroups[key]
    if not group then
        self.feedbackWrite=self.feedbackWrite%32+1
        group=self.feedbackPool[self.feedbackWrite]
        if group.key~=nil then self.feedbackGroups[group.key]=nil end
        group.key,group.at,group.amp,group.duration,group.fov,group.stop=key,self.age,0,0,0,0
        local d=dir or Vector3.RIGHT
        local v=group.dir;v.x,v.y,v.z=d.x,d.y,d.z;group.dir=v
        self.feedbackGroups[key]=group
    end
    group.amp=math.max(group.amp,amp or 0)
    group.duration=math.max(group.duration,duration or 0)
    group.fov=math.max(group.fov,fov or 0)
    group.stop=math.max(group.stop,stop or 0)
    self.hitstop=math.max(self.hitstop,group.at+group.stop-self.age)
    return group
end
-- Borrowed pooled event: synchronous consumers copy fields they retain.
-- One event per successful settlement; hit_on alone cannot fabricate impacts.
function C:Feedback(enemy,info,result,weak,arrow)
    if not result.hit then return end
    self.eventWrite=self.eventWrite%#self.eventPool+1
    local e=self.eventPool[self.eventWrite]
    e.swingId=info.swingId or ('sword:'..self.swingSerial)
    e.weapon=arrow and (info.kind=='crystal' and 'crystal' or 'bow') or 'sword'
    e.tier=arrow and (ARROW_TIERS[info.tier] or 'arrow_weak') or (info.heavy and 'heavy' or (COMBO[info.combo] or COMBO[1]).tier)
    e.material=result.material or info.material or 'soft'
    e.part,e.pos,e.dir,e.normal=result.part or info.part,info.pos,info.dir,info.normal
    e.broke,e.staggered,e.killed=result.broke==true or result.partBroken~=nil,result.staggered==true,result.killed==true
    e.weak,e.damage,e.poise=weak==true or result.weak==true,result.damage or info.dmg,info.poise or 0
    e.combo,e.full=arrow and 0 or (info.combo or 0),info.full==true
    e.critical=info.critical==true or (not arrow and e.weak)
    e.resolved,e.presentationConsumed,e.player=result.resolved~=false,false,false
    local f=info.dir or Vector3.FORWARD
    local x,y,z
    if arrow then x,y,z=f.x,f.y,f.z
    elseif info.plunge or e.combo==3 or e.combo==C.COMBO_LENGTH then x,y,z=f.x*.3,-1,f.z*.3
    else
        local sign=e.combo==2 and -1 or 1
        x,y,z=f.z*sign,info.heavy and -.3 or 0,-f.x*sign
    end
    local length=math.sqrt(x*x+y*y+z*z)
    if length<1e-8 then x,y,z,length=1,0,0,1 end
    local v=e.impactDir;v.x,v.y,v.z=x/length,y/length,z/length;e.impactDir=v
    local profile=Profile(e,info,arrow)
    e.profileId,e.flash,e.flashPeak=profile.id,profile.flash,profile.peak
    e.kind,e.enemy='hit',enemy
    if self.observe then self.observe('hit',{clip=info.clip,damage=e.damage,weapon=e.weapon,enemy=enemy,age=self.age}) end
    self.lastHitAt,self.lastHitWeak=self.age,e.weak
    if self.state.Log then self.state.Log('hit:'..tostring(enemy.id)..':'..tostring(e.part),
        'Combat: hit %s part=%s dmg=%.2f poise=%.2f',enemy.id or 'enemy',e.part or 'body',e.damage,e.poise) end
    local stop,amp,duration,fov=profile.stop,profile.amp,profile.duration,profile.fov
    if arrow then
        stop=(e.broke or e.staggered) and .10 or (e.weak and .06 or .03)
        amp,duration,fov=0,0,0
        if not enemy.boss and not enemy.dead and enemy.Knockback then
            enemy:Knockback(info,info.critical and .16 or .08)
            if enemy.knock then enemy.knock.duration=.10 end
        elseif enemy.boss and e.staggered and enemy.knock then
            -- Arrow stagger keeps the boss reaction pose, without the legacy
            -- melee .6m root displacement scheduled by its settlement.
            enemy.knock.active=false
        end
    end
    e.stop,e.attackerStop=stop,not arrow and stop or 0
    self:Envelope(e.swingId,amp,duration,fov,e.impactDir,e.attackerStop)
    enemy.hitStop=math.max(result.priorHitStop or enemy.hitStop or 0,stop)
    -- Only the paired deferred path invokes the consumer. Legacy arrows have
    -- already presented during ApplyHit and must never emit a second burst.
    if info.deferPresentation and enemy.OnHitEvent then e.presentationConsumed=enemy:OnHitEvent(e)==true end
    if not arrow and self.rig.HitImpulse then self.rig:HitImpulse(e) end
    self.lastProfile,self.lastStop,self.lastFlash,self.lastPresented=e.profileId,e.stop,e.flash,e.presentationConsumed
    self.target,self.targetAt=enemy,self.age
    if e.broke then
        self.partNotice=self.partNoticePool
        self.partNotice.part,self.partNotice.untilTime=result.partBroken or e.part,self.age+1.2
    end
    if e.weak then self.weakUntil=self.age+1.2 end
    if (enemy.training or self.state.GetSetting('damageNumbers')) and e.damage then
        self.numberWrite=self.numberWrite%12+1
        local number=self.numberPool[self.numberWrite]
        for i=#self.numbers,1,-1 do if self.numbers[i]==number then table.remove(self.numbers,i) end end
        local durationN=enemy.training and 1.2 or .7
        number.pos,number.value,number.untilTime,number.duration=e.pos,math.floor(e.damage+.5),self.age+durationN,durationN
        number.screenVisible=false
        self.numbers[#self.numbers+1]=number
    end
    -- W3 already owns enemy reaction/particles inside the successful settlement.
    local soundOpts=e.audio
    soundOpts.pos,soundOpts.material,soundOpts.tier,soundOpts.hitId=e.pos,e.material,e.tier,e.swingId
    if e.broke then self:Sound('armor_break',soundOpts)
    elseif e.material=='stone' and e.part and e.part:find('stone_',1,true)==1 then self:Sound('deflect_stone',soundOpts)
    elseif arrow then self:Sound('arrow_hit',soundOpts)
    else
        if e.weak or e.material=='core' or e.material=='weakpoint' then soundOpts.tier='critical' end
        if e.weak then soundOpts.material='weakpoint' end
        self:Sound(e.weak and 'hit_core' or (e.material=='armor' and 'hit_armor' or 'hit_soft'),soundOpts)
    end
    soundOpts.tier,soundOpts.material=e.tier,e.material
    if e.tier=='heavy' or e.tier=='third' then self:Sound('hit_heavy',soundOpts) end
    if self.o.feedback then self.o.feedback(e) end
end
function C:ApplyHit(info)
    if self.dead or self.invuln>0 or (self.protection and next(self.protection)) or (self.o.protected and self.o.protected()) then return {hit=false} end
    self.state.OnPlayerHit()
    self:Cancel('hit')
    self.hp=math.max(0,self.hp-info.dmg)
    if self.state.Log then self.state.Log('player-hit','Combat: player hit dmg=%.2f hp=%.2f',info.dmg,self.hp) end
    self.invuln=.8
    self:Envelope('player:'..self.age,.025,.10,0,info.dir,0)
    self:Sound('player_hurt')
    self.moveDir=Flat(info.dir or -self.o.forward(),-self.o.forward())
    self.knock=.6
    if self.o.feedback then self.o.feedback({kind='hit',player=true,pos=self.o.position()+Vector3(0,.8,0),dir=info.dir or -self.o.forward(),material='soft',tier='heavy'}) end
    if self.hp<=0 then
        self.dead=true; self.state.SetDead(true); self:Play('death')
    else self:Play('hit_light') end
    return {hit=true,killed=self.dead}
end
function C:Events()
    -- Never call Poll recursively: its storage is reused. Play/Stop may queue
    -- closing events but the next explicit drain safely consumes those.
    local events=self.anim:Poll()
    self.draining=true
    for _,e in ipairs(events) do
        self.protection=self.protection or {}
        if e.name=='protect_on' then self.protection[e.handle]=true
        elseif e.name=='protect_off' then self.protection[e.handle]=nil end
        if e.handle==self.handle then
        if self.observe then self.observe('event',{name=e.name,clip=e.clip,t=e.t,age=self.age}) end
        if e.name=='hit_on' then
            self.cut=(self.cut or 0)+1
            if self.cut>1 then
                -- Cross slash second cut: fresh targets, hitstop group and whoosh.
                self.swingSerial=self.swingSerial+1
                for key in pairs(self.damaged) do self.damaged[key]=nil end
                local sound=self.soundOpts
                sound.pos,sound.tier,sound.pitch=self.o.position(),3,.82
                self:Sound('sword_whoosh',sound);sound.pitch,sound.tier=nil,nil
            end
            self.hitOpen,self.hitPending,self.hitClip=true,true,e.clip
            if self.rig.BeginSlash then self.rig:BeginSlash(self.combo,e.clip=='sword_heavy_release') end
            self.hitForward=self.hitForward or Flat(self.moveDir or self.o.forward(),Vector3.FORWARD)
        elseif e.name=='hit_off' then
            self.hitOpen=false; self.trailUntil=self.age+.06
            local stage=COMBO[self.combo]
            if stage and stage.id==e.clip then
                local clip=Data.Clips[e.clip]
                self.comboUntil=self.age+(clip.dur-clip.phases.active[2])+.45
                if stage.cooldown then self.comboCooldownUntil=self.age+stage.cooldown end
                if stage.impactRing then
                    if self.rig.ImpactFx then self.rig:ImpactFx(self.o.position(),self.hitForward or self.o.forward(),false)
                    elseif self.o.impactRing then self.o.impactRing(self.o.position(),self.hitForward or self.o.forward()) end
                    if self.o.camera then self.o.camera:Land() end
                end
            end
            if e.clip=='sword_light_3'  and self.o.camera then self.o.camera:Land() end
        elseif e.name=='cancel_open' then self.cancelOpen=true
        elseif e.name=='cancel_close' then self.cancelOpen=false
        elseif e.name=='charge_full' or e.name=='draw_full' then
            if e.name=='charge_full' and not self.fullCharged then
                self.charge,self.fullCharged=1,true; self:Flash('full_charge');self:Sound('sword_full')
            end
            self.fullAt=self.age
            if e.name=='draw_full' and self.charge>=1 and not self.drawFullReached then
                self.drawFullReached=true; self.bowFullAt=self.age; self:Sound('bow_full')
            end
        elseif e.name=='weapon_ready' then
            if not self.rig.PopEvents then self:Flash('draw'); self:Sound('blade_draw') end
            if self.clip:find('weapon_swap_',1,true) then
                self.state.FinishTransition(); self.rig:SetPose(self.state.GetPose())
            else self.rig:SetPose('hand') end
        elseif e.name=='weapon_stowed' or e.name=='weapon_drop' then
            if e.name=='weapon_stowed' and not self.rig.PopEvents then self:Flash('sheath'); self:Sound('blade_sheath') end
            if not self.clip:find('weapon_swap_',1,true) then
                self.rig:SetPose(e.name=='weapon_drop' and 'hidden' or 'back')
            end
        elseif e.name=='draw_start' then self.rig:SetPose('hand')
        elseif e.name=='draw_min' then
            self:Play('bow_hold')
        elseif e.name=='recover_end' then
            if self.state.Log then self.state.Log('clip-finish:'..self.clip,'Combat: clip %s finish',self.clip) end
            self.anim:Stop(self.handle,0); self.clip,self.handle=nil,nil
            self.charge,self.autoFire=0,false
        elseif e.name=='fire' then
            self:StopDrawSound()
            -- Release owns a single snapshot; this animation cue never queues ammo.
        elseif e.name=='respawn_ready' then
            self.anim:Stop(nil,0)
            self.clip,self.handle=nil,nil
            self.hp,self.dead,self.invuln=100,false,1
            if self.state.Log then self.state.Log('player-respawn','Combat: player respawn hp=100') end
            self.state.SetDead(false); self.state.Exit('respawn')
            if self.o.respawn then self.o.respawn() end
            self:Play('getup')
        elseif e.name=='clip_finished' then
            local finished=self.clip
            if self.state.Log then self.state.Log('clip-finish:'..finished,'Combat: clip %s finish',finished) end
            self.clip,self.handle=nil,nil
            if finished=='plunge_start' and self.plunging then self:Play('plunge_loop',.08)
            elseif finished=='sword_draw' or finished=='bow_equip' then
                local pending,released=self.pending,self.pendingReleased
                local heldTime=self.hold
                self.pending,self.pendingReleased=nil,false
                if pending then self:Action(pending) else self.state.SetBusy(false) end
                if pending=='hold' then self.hold=heldTime end
                if released and self.clip=='bow_draw' then self.pendingReleased=true end
            elseif finished=='bow_draw' then self:Play('bow_hold')
            elseif finished=='knockdown' then self:Play('getup')
            elseif finished=='getup' then self.state.SetBusy(false)
            else self.charge,self.autoFire=0,false; self.state.SetBusy(false) end
        end
    end end
    self.draining=false
end
-- A single edge survives until its action becomes cancellable.
function C:ConsumeBuffer(axis)
    if not self.buffer then return end
    if self.age>self.bufferUntil+1e-8 then self.buffer=nil;return end
    local kind=self.buffer
    if self:Action(kind,axis) and self.buffer==kind then self.buffer=nil end
end
---@param dt number
---@param controls table attack/heavy held, attackTap edges, axis world-space, allowed
function C:Update(dt,controls)
    local inputStart=Perf.Begin()
    Perf.Context(self.swingSerial,self.combo,self.clip)
    local foot=self.o.locomotion
    if foot then foot:Begin(dt,controls,self) end
    self.inputAxis=controls.axis
    self.age=self.age+dt; self.invuln=math.max(0,self.invuln-dt)
    if self.state.InCombat() and self:WeaponInHand() then
        -- Sword rests low along the forearm; bow keeps the neutral stance.
        local stance=self.state.GetWeapon()=='sword' and 'stance_combat_sword' or 'stance_combat'
        if not self.anim:IsPlaying(stance) then
            if self.stanceHandle then self.anim:Stop(self.stanceHandle,.15) end
            self.stanceHandle=self.anim:Play(stance,{fadeIn=.15})
        end
    elseif self.stanceHandle then
        local idleStow=self.state.InCombat() and self.state.GetWeapon()=='sword'
            and self.state.GetPose()=='back' and not self.clip
        -- 原地全息收剑：低位手臂缓缓回到空手站姿，不加动作锁或重播起手。
        self.anim:Stop(self.stanceHandle,idleStow and .45 or .08)
        self.stanceHandle=nil
    end
    self.shakeAge=self.shakeAge+dt
    local inCombat=self.state.InCombat()
    self.stamina:Update(dt,inCombat,foot~=nil and foot:IsRunning())
    -- Exhausted: sprint is refused until the bar recovers (combat only).
    if inCombat and controls.runIntent and not self.stamina:CanSprint() then
        controls.runIntent=false
        if foot and foot:IsRunning() then foot:Cancel('stamina') end
    end
    local attack,heavy=controls.attack==true,controls.heavy==true
    -- The sword's heavy is a long press of attack; the right button is bow-only.
    local swordHeavy=self.state.GetWeapon()=='sword'
    if swordHeavy then heavy=false end
    if not controls.allowed then
        if not self.suspended then
            -- A death/getup animation must finish while its input is disabled.
            if not controls.selecting and not self.dead and self.clip~='getup' then self:Cancel('blocked') end
            self.suspended=true
        end
        self.blocked=true; attack,heavy=false,false
    else self.suspended=false end
    if self.blocked and not controls.attack and not controls.heavy then self.blocked=false end
    local canInput=controls.allowed and not self.blocked and not self.dead and self.state.InCombat()
    if canInput and controls.jump and controls.onGround~=false then self:JumpCancel() end
    if canInput and self.cancelOpen and ((controls.axis and controls.axis:LengthSquared()>.18*.18) or controls.runIntent) then
        self:RecoveryCancel('move')
    end
    if controls.allowed and not self.dead then self:UpdatePlunge(dt) end
    local animDt=math.max(0,dt-self.hitstop)
    if canInput and not self.plunging then
        if not swordHeavy and ((heavy and not self.lastHeavy) or controls.heavyTap) then
            self.releaseFull=false;self.buffer,self.bufferAt,self.bufferUntil='heavy',self.age,self.age+BUFFER
            self.holdSource=nil
        end
        if (attack and not self.lastAttack) or controls.attackTap then
            self.buffer=(self.state.GetWeapon()=='bow' or (not self.clip and attack)) and 'hold' or 'light'
            self.bufferAt,self.bufferUntil=self.age,self.age+BUFFER
            self.holdSource='attack'
            self.pressAt,self.pressHeavy=self.age,false
        end
        -- Mid-combo long press: queue the cross slash after the current stage.
        if swordHeavy and attack and self.pressAt and not self.pressHeavy and self.age-self.pressAt>=HEAVY_HOLD-1e-8
            and self.clip and self.clip:find('sword_light_',1,true) then
            self.pressHeavy=true
            self.buffer,self.bufferAt,self.bufferUntil='heavy',self.age,self.age+1.2
        end
        self:ConsumeBuffer(controls.axis)
        if self.clip=='sword_heavy_charge' or (self.clip=='sword_draw' and self.pending=='hold') then
            self.hold=self.hold+dt
            -- No charge levels: holding long enough fires the cross slash at once.
            if self.clip=='sword_heavy_charge' and attack and self.hold>=HEAVY_HOLD-1e-8 then
                self.pressHeavy=true;self:Release()
            end
        end
        if self.clip=='bow_hold' or self.clip=='bow_draw' then
            self.drawElapsed=self.drawElapsed+dt
            local drawDuration=self.rig:GetStats().draw or 1
            self.charge=self.drawElapsed+1e-9>=drawDuration and 1 or self.drawElapsed/drawDuration
            self.power=(self.charge*self.charge+2*self.charge)/3
            self.anim:SetParam('p',self.charge)
            if self.charge>=1 and not self.drawFullReached then
                self.drawFullReached=true;self.bowFullAt=self.age;self:Sound('bow_full')
                if self.rig.FlashBowFull then self.rig:FlashBowFull() end
            end
        end
        if self.autoFire and self.drawFullReached and self.clip=='bow_hold' and self.charge>=1 then self:Release() end
        if self.lastAttack and not attack and not self.autoFire then self:Release() end
    end
    Perf.Context(self.swingSerial,self.combo,self.clip)
    Perf.Finish('input',inputStart)
    local motionStart=Perf.Begin()
    self.lastAttack,self.lastHeavy=attack,heavy
    self.hitstop=math.max(0,self.hitstop-dt)
    self.motionChecked=false
    local stepDt=animDt
    local moveDir=self.moveDir or self.o.forward() --[[@as Vector3]]
    -- Sound timing derives from the authored active boundary, not a hit table.
    if self.clip and (self.clip:find('sword_light_',1,true) or self.clip=='sword_heavy_release') then
        local clip=require('combat.AnimClips').Clips[self.clip]
        local threshold=math.max(0,clip.phases.active[1]-.02)
        self.whooshTime=self.whooshTime+stepDt*(clip.speedStat and self.rig:GetStats()[clip.speedStat] or 1)*(self.anim.timeScale or 1)
        if not self.whoosh and self.whooshTime>=threshold then
            self.whoosh=true
            local row=COMBO[self.combo]
            local sound=self.soundOpts
            sound.pos,sound.tier,sound.pitch=self.o.position(),self.combo>0 and ((self.combo-1)%3+1) or 3,row and row.pitch or .9
            self:Sound('sword_whoosh',sound)
            sound.pitch,sound.tier=nil,nil
        end
    end
    -- W4 smooths arm ownership during advancement, so this must precede GetMotion.
    self.anim:SetParam('weaponInHand',self:WeaponInHand() and 1 or 0)
    local metres=self.anim:GetMotion(stepDt,dt)
    local attacking=self.clip and (self.clip:find('sword_light_',1,true) or self.clip=='sword_heavy_release')
    if attacking then metres=metres*(self.motionScale or 1) end
    if (attacking or not self.clip) and animDt>0 then
        metres=metres+(self.motionDebt or 0);self.motionDebt=0
    end
    self.motion=moveDir*metres
    if (attacking or not self.clip) and self.o.attackMotion and metres>0 then
        local stopped,debt
        self.motion,stopped,debt=self.o.attackMotion(self.motion)
        self.motionDebt=not stopped and (debt or 0) or 0
        self.motionChecked=true -- already footprint/wall checked, do not re-run endpoint guard
    end
    Perf.Finish('motion',motionStart)
    if self.fovAge then self.fovAge=self.fovAge+dt end
    local recoveryStart=Perf.Begin()
    self:Events()
    Perf.Finish('recovery',recoveryStart)
    if not self.clip and canInput then self:ConsumeBuffer(controls.axis) end
    if foot then foot:Finish(dt,controls,self) end
    if self.knock and self.knock>0 and not self.dead then
        local amount=math.min(self.knock,dt*2.4)
        self.motion=self.motion+(self.moveDir or Vector3.ZERO)*amount; self.knock=self.knock-amount
    end
    self.state.SetBusy(self.clip~=nil or controls.selecting==true)
end
-- Unified selection entry. Preserve authored sword/bow swaps and draw events;
-- time is the existing casting mode, not a third WeaponRig mesh.
function C:SelectLoadout(target)
    if target~='time' and target~='sword' and target~='bow' then return false end
    if self.dead or not self:CanCancel() then return false end
    local selected=self.state.GetSelection()
    if selected==target then return true end
    if self.state.TransitionRemaining()>0 then return false end
    if target=='time' then
        self:Cancel('loadout') -- discard pending charge/fire/hit before mode change
        self.state.SetBusy(false)
        self.state.Exit('loadout')
        return true
    end
    if selected~='time' then return self:Swap(target) end
    self:Cancel('loadout')
    self.state.SetBusy(false)
    if not self.state.SetWeapon(target) or not self.state.Enter('loadout') then return false end
    -- Match ordinary swap completion: selected weapon rests on the back;
    -- its next attack owns the existing draw animation and hand-state change.
    return true
end
function C:Swap(targetWeapon)
    if targetWeapon~=nil and targetWeapon~='sword' and targetWeapon~='bow' then return false end
    if self.dead then return false end
    local old=self.state.GetWeapon()
    local nextWeapon=targetWeapon or (old=='sword' and 'bow' or 'sword')
    if nextWeapon==old then return true end -- confirmation of the current slot is a no-op
    if not self:CanCancel() or self.dead then return false end
    self.state.BeginSwapPerf()
    self.state.SetBusy(false)
    local ok=self.state.SetWeapon(nextWeapon)
    if ok then
        self:Cancel('swap')
        self.rig:SetPose('hidden') -- never resurrect the old weapon while swapping
        self:Play('weapon_swap_'..old..'_to_'..nextWeapon)
    end
    self.state.EndSwapPerf(ok)
    return ok
end
function C:MoveScale()
    if self.dead or self.suspended or self.clip=='getup' or self.clip=='death' then return 0 end
    if self.clip and (self.clip:find('hit_',1,true) or self.clip=='knockdown') then return 0 end
    if self.plunging or self.clip=='plunge_land' then return 0 end
    if self.clip=='sword_heavy_charge' then return .4 end
    if self.clip=='bow_hold' or self.clip=='bow_draw' then return self.rig:GetStats().move or .5 end
    if self.clip and (self.clip:find('sword_light_',1,true) or self.clip=='sword_heavy_release') then return 0 end
    return 1
end
-- One geometry source for settlement and the brief range boundary.
function C.MeleeZone(id,position,forward,reach,slam,out)
    out=out or {origin=Vector3(0,0,0),source=Vector3(0,0,0)}
    local stage
    for _,row in ipairs(COMBO) do if row.id==id then stage=row;break end end
    local offset=stage and stage.offset or 0
    -- Engine Vector3 table fields are values: component writes target a copy.
    out.origin=Vector3(position.x+forward.x*offset,position.y,position.z+forward.z*offset)
    out.source=Vector3(position.x,position.y+.9,position.z)
    out.forward=forward
    local cross=id=='sword_heavy_release'
    out.radius=(slam and 2 or (cross and 2.3 or (stage and stage.radius or 1.8)))*math.max(.1,reach or 1)
    out.angle=slam and 90 or (cross and 170 or (stage and stage.angle or 120))
    out.low,out.high=-.3,2
    return out
end
function C:StrikeZones()
    local id=self.hitPending and self.hitClip or self.clip
    if self.dead or not id or not (id:find('sword_light_',1,true) or id=='sword_heavy_release' or id=='plunge_land') then return nil end
    if id=='plunge_land' then
        if not (self.hitOpen or self.hitPending) then return nil end
        local out=self.strikeZone
        out.origin=self.o.position();out.source=out.origin+Vector3(0,.4,0)
        out.forward=self.hitForward or self.o.forward()
        out.radius,out.angle,out.low,out.high=2.4,360,-.3,1.5
        return out,nil,true
    end
    local phase=require('combat.AnimClips').Clips[id].phases.active
    local t=self.whooshTime or 0
    if not (self.hitOpen or self.hitPending) and t>=phase[1] then return nil end
    local position=self.o.position()
    local direction=self.hitForward or self.moveDir or self.o.forward()
    local reach=self.rig:GetStats().reach
    self.strikeZone=C.MeleeZone(id,position,direction,reach,false,self.strikeZone)
    return self.strikeZone,nil,self.hitOpen or self.hitPending
end
-- Samples the same sector, including both radial edges. The caller must assign
-- the returned Vector3: native vector arguments are passed by value.
function C.ZoneBoundary(zone,index,segments,out)
    local half=math.rad(zone.angle*.5)
    local angle,radius
    if index<=segments then angle=-half+2*half*index/segments;radius=zone.radius
    else angle=index<=segments+4 and -half or half;radius=zone.radius*((index-segments-1)%4)/4 end
    local x,z=math.sin(angle)*radius,math.cos(angle)*radius
    local f=zone.forward
    out.x,out.y,out.z=zone.origin.x+x*f.z+z*f.x,zone.origin.y+.04,zone.origin.z+z*f.z-x*f.x
    return out
end
-- Still called after the physical actor/base animation update. hitPending covers
-- a low-FPS frame which contains both hit_on and hit_off exactly once.
function C:AfterPose()
    if self.settlingContact then return end -- hit/feedback callbacks may reenter
    if self.pendingFire~=nil then
        local shot=self.pendingFire
        if not self.dead and self.o.fire then
            local fired=self.o.fire(shot.u,shot.stats,self.fireCrystal,shot)
            if fired then
                if self.rig.ReleaseBow then self.rig:ReleaseBow() end
            else self.bowFailedUntil=self.age+.10 end
        end
        self.pendingFire=nil
    end
    if not (self.hitOpen or self.hitPending) or self.dead then
        self.previousHit=nil
        if self.o.environmentMelee then self.o.environmentMelee(self,false) end
        return
    end
    local environmentSwing,environmentHandle=self.swingSerial,self.handle
    local zone,slam=self:StrikeZones()
    -- R8 conservative P0 path: keep the proven gameplay sector/reach and draw
    -- its actual one-frame slash sample, including a hitch across hit_on/off.
    -- This is NOT a blade-contact narrowphase; physical blade alignment remains
    -- a Web acceptance item rather than silently reducing gameplay reach.
    if zone and self.hitPending and self.rig.ShowContactArc then self.rig:ShowContactArc(zone) end
    self.hitPending=false
    if not zone then return end
    local stats=self.rig:GetStats()
    local position=self.o.position()
    local direction=self.hitForward or Flat(self.o.forward(),Vector3.FORWARD)
    local enemies=self.o.enemies and self.o.enemies() or {}
    local queryStart=Perf.Begin()
    for enemy in pairs(self.queryShapes) do self.queryShapes[enemy]=nil end
    local contacts=Hit.QueryZone(enemies,zone,self.queryHits,self.queryPool,self.damaged,self.queryShapes)
    if slam then
        for _,contact in ipairs(Hit.QueryZone(enemies,slam,self.slamHits,self.slamPool,self.damaged,self.queryShapes)) do contacts[#contacts+1]=contact end
        table.sort(contacts,Hit.DistanceLess)
    end
    Perf.Finish('QueryZone',queryStart)
    local hitStart=Perf.Begin()
    for _,contact in ipairs(contacts) do
        local enemy,part=contact.enemy,contact.shape.id
        -- Stone projectiles are distinct targets; a deflection cannot consume the body hit.
        local key=Hit.TargetKey(enemy,part)
        if not self.damaged[key] and Hit.Visible(position+Vector3(0,.9,0),contact.pos,self.o.cast) then
            local plunge=self.hitClip=='plunge_land'
            local heavy=self.hitClip=='sword_heavy_release' or plunge
            local stage=COMBO[self.combo] or COMBO[1]
            local info={dmg=(stats.attack or 10)*(plunge and 1.6*(self.plungeMultiplier or 1.4) or (heavy and 1.3 or stage.damage)),
                poise=(stats.poise or 6)*(plunge and 3 or (heavy and 1.6 or stage.poise)),
                armorBreak=(stats.armorBreak or 1)*(plunge and 2 or (heavy and self.releaseFull and 1.5 or 1)),knockback=stage.knockback,
                plunge=plunge,part=part,material=contact.shape.material or 'soft',normal=contact.normal,
                deferPresentation=type(enemy.OnHitEvent)=='function',full=not plunge and heavy and self.releaseFull==true,
                swingId='sword:'..self.swingSerial,tier=heavy and 'heavy' or stage.tier,kind='sword',clip=self.hitClip,pos=contact.pos,dir=direction,source='player',heavy=heavy,combo=self.combo}
            self.settlingContact=true
            local ok,message=pcall(C.SettleContact,self,enemy,info,key,contact.shape.weak,self.swingSerial)
            self.settlingContact=false
            if not ok then error(message,0) end
        end
    end
    Perf.Finish('HitEvent',hitStart)
    if self.o.environmentMelee then
        -- Enemy callbacks may cancel, kill or replace this attack before the
        -- environment pass. Never excavate with that stale contact pose.
        self.o.environmentMelee(self,not self.dead and not self.blocked
            and self.swingSerial==environmentSwing and self.handle==environmentHandle)
    end
end
-- Keep info/result as independent snapshots: enemy/FX callbacks may retain
-- them. The borrowed QueryZone contacts are never exposed to those callbacks.
function C:SettleContact(enemy,info,key,weak,swing)
    local result=Hit.Apply(enemy,info)
    if result.hit then
        if self.swingSerial==swing then self.damaged[key]=true end
        self:Feedback(enemy,info,result,weak,false)
    end
end
function C:ShakeOffset(right,up)
    if self.state.GetSetting('cameraShake')==false then return Vector3.ZERO end
    right,up=right or Vector3.RIGHT,up or Vector3.UP
    local peak,dir=0,Vector3.RIGHT
    for _,g in pairs(self.feedbackGroups) do
        local age=self.age-g.at
        if g.duration>0 and age>=0 and age<g.duration then
            local u=age/g.duration
            local k=g.amp*math.sin(math.pi*u)
            if k>peak then peak,dir=k,g.dir end
        end
    end
    local x,y=dir:DotProduct(right),dir:DotProduct(up)
    local length=math.sqrt(x*x+y*y)
    if length<.05 then x,y,length=.8,-.6,1 end
    local k=math.min(.03,peak)/length
    local v=self.shakeVector
    v.x,v.y,v.z=(right.x*x+up.x*y)*k,(right.y*x+up.y*y)*k,(right.z*x+up.z*y)*k
    self.shakeVector=v
    return v -- borrowed, consumed synchronously by the camera
end
function C:FovOffset()
    if self.state.GetSetting('cameraFov')==false then return 0 end
    local peak=0
    for _,g in pairs(self.feedbackGroups) do
        local age=self.age-g.at
        if age<.12 then peak=math.max(peak,g.fov*(1-age/.12)) end
    end
    return peak
end

-- PC debug helpers live outside Spawner: no encounters or puzzle state are changed.
function C.NewTrainingDummy(position,node)
    local dummy={id='training_dummy',training=true,position=position,node=node,hp=9999,maxHP=9999,
        active=true,dead=false,aggro=false,config={height=1.8},parts={}}
    local shapes={{id='body',center=position+Vector3(0,1,0),radius=.6,weak=false,enabled=true}}
    function dummy:GetHurtShapes() return shapes end
    function dummy:ApplyHit(info)
        self.hp=math.max(0,self.hp-info.dmg)
        local weapon=info.kind=='sword' and 'sword' or 'bow'
        if self.debugHits then print(string.format('Dummy hit: %s %s dmg=%.2f part=%s',weapon,info.tier or info.clip or 'unknown',info.dmg,info.part or 'body')) end
        return {hit=true,killed=false}
    end
    function dummy:Update() self.hp=9999 end
    function dummy:Destroy() self.active=false; if self.node then self.node:Remove() end end
    return dummy
end

-- Terrain is authoritative; a caller may additionally reject building collisions.
function C.DebugDestination(enemies,terrain,index,clear)
    local labels={'苔壳虫组','哨灵','石甲兽'}
    local target
    for _,enemy in ipairs(enemies) do
        local id=enemy.id or ''
        if (index==1 and id:find('moss_',1,true)) or (index==2 and id:find('sentry_',1,true))
            or (index==3 and enemy.boss) then target=enemy; break end
    end
    if not target then return nil,nil,labels[index] end
    local anchor=target.home or target.position
    local radius=index==3 and 14 or 7
    for ring=0,2 do for i=0,15 do
        local angle=math.pi*2*i/16
        local x,z=anchor.x+math.sin(angle)*(radius+ring*2),anchor.z+math.cos(angle)*(radius+ring*2)
        local y=terrain.GroundHeight(x,z)
        if y and terrain.IsSafeGround(x,y,z) and terrain.HasGround(x,z,2) then
            local pos=Vector3(x,y+.1,z)
            local separated=true
            for _,other in ipairs(enemies) do
                local q=other.position or other.home
                if q and (pos-q):Length()<3 then separated=false; break end
            end
            if separated and (not clear or clear(pos)) then return pos,anchor,labels[index] end
        end
    end end
    return nil,anchor,labels[index]
end

function C.PreviewPhase(id,t)
    local clip=require('combat.AnimClips').Clips[id]
    if t<clip.phases.anticipation[2] then return 'anticipation' end
    if t<clip.phases.active[2] then return 'active' end
    return 'recovery'
end
function C.PreviewEvents(events,from,to)
    local names={}
    for _,e in ipairs(events) do
        local seconds=e.t*require('combat.AnimClips').Clips[e.clip].dur
        if seconds<=to+1e-8 and (seconds>from+1e-8 or (from<0 and seconds==0)) then names[#names+1]=e.name end
    end
    return #names>0 and table.concat(names,', ') or '—'
end
-- Rebuild the isolated preview clock; replayed events never enter CombatMoves.Events.
function C.SeekPreview(anim,id,t,previous,params)
    local clip=require('combat.AnimClips').Clips[id]
    t=math.max(0,math.min(clip.dur,t))
    anim:Stop(nil,0); anim:Poll()
    anim:Play(id,{fadeIn=0,fadeOut=0,params=params})
    anim:SetParam('p',params and params.p or t/math.max(.01,clip.dur))
    anim:Update(t,t)
    local from=previous<t and previous or t-1/30-1e-8
    return t,C.PreviewEvents(anim:Poll(),from,t)
end

-- Adapt the existing bounded dust emitter without owning another particle pool.
-- Touch only this emission's serials; preserve enemy slots/key-event reserves.
function C.EmitDustStreak(pool,owner,pos,dir,ground,maxCount)
    if not pool or not pool.slots or not pool.Hide then return 0 end
    -- A run footprint borrows this dust material. Reserve six admissions before
    -- the pool emits its fixed burst, then keep one; never evict hit/telegraph FX.
    if maxCount==1 and pool.count and pool.count+6>(pool.limit or 64)-(pool.reserved or 16) then return 0 end
    local originY=ground(pos)
    if not originY then return 0 end
    local first=pool.serial
    pool:Emit(owner,{pos=pos,dir=dir,normal=Vector3.UP,material='stone',kind='dust'})
    local count=0
    for _,slot in ipairs(pool.slots) do
        if slot.active and slot.owner==owner and slot.serial>first then
            local i=slot.serial-first
            local at=pos-dir*((i-1)*.18) --[[@as Vector3]]
            local y=i<=(maxCount or 4) and ground(at) or nil
            if not y then pool:Hide(slot)
            else
                count=count+1
                slot.x,slot.y,slot.z=at.x,y+.025,at.z
                slot.vx,slot.vy,slot.vz,slot.gravity=0,.04,0,0
                slot.sx,slot.sy,slot.sz=.025+i*.005,.025,.025+i*.005
                slot.ttl=.12+i*.02
                if slot.node then slot.node.position=Vector3(slot.x,slot.y,slot.z); slot.node.scale=Vector3(slot.sx,slot.sy,slot.sz) end
            end
        end
    end
    return count
end

-- One existing six-slot burst reshaped into a landing ring; no geometry/node creation.
function C.EmitImpactRing(pool,owner,pos,dir)
    if not pool or not pool.slots then return 0 end
    local first=pool.serial
    RING_EVENT.pos,RING_EVENT.dir,RING_EVENT.normal=pos,dir,Vector3.UP
    pool:Emit(owner,RING_EVENT)
    local count=0
    for _,slot in ipairs(pool.slots) do
        if slot.active and slot.owner==owner and slot.serial>first then
            count=count+1
            local angle=(slot.serial-first-1)*math.pi/3
            local x,z=math.sin(angle),math.cos(angle)
            slot.x,slot.y,slot.z=pos.x+x*.35,pos.y+.04,pos.z+z*.35
            slot.vx,slot.vy,slot.vz=x*2.5,.65,z*2.5
            slot.ttl=.25;slot.gravity=4
            if slot.node then slot.node.position=Vector3(slot.x,slot.y,slot.z) end
        end
    end
    return count
end

-- Hand-only pool lets combat remove white hand motes immediately without
-- deleting ongoing freeze/rewind effects from TimeFX's shared spell pools.
function C.UpdateHandFX(fx,motes,dt,pos,color,glow)
    if glow<=0 then fx.handGlow,fx.handAcc=0,0 end
    fx:Update(dt,nil,color,glow) -- keep spell FX ticking; bypass its shared hand emitter
    fx.handLight.position=pos
    fx.handLight.enabled=glow>0
    fx.handL.brightness=glow>0 and 1.6*fx.handGlow or 0
    fx.handL.color=color
    motes:Update(dt)
    if glow<=0 then motes:Clear(); fx.handAcc,motes.handAcc=0,0; return end
    local budget=(motes.handAcc or 0)+48*fx.handGlow*math.min(dt,.1)
    local count=math.floor(budget); motes.handAcc=budget-count
    for i=1,math.min(count,#motes.free) do
        local a=(i+(motes.tick or 0))*2.399963
        local d=Vector3(math.sin(a),math.cos(a*.7),math.cos(a))*.16
        motes:Spawn{pos=pos+d,vel=-d*2+Vector3(0,.3,0),life=.4,size=.06,colors={color}}
    end
    motes.tick=(motes.tick or 0)+count
end
return C
