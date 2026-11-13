-- Player combat. Animation events are the only hit/cancel/iframe/fire clock.
-- Dependencies are injected so collision, cancellation and death can run offline.
local Hit=require('combat.Hit')
---@class PlayerCombatMoves
---@field o table
---@field anim table Animation port (real CombatAnim or offline event stub).
---@field state table
---@field rig table
---@field moveDir Vector3|nil
---@field motion Vector3
---@field partNotice {part:string,untilTime:number}|nil
local C={}; C.__index=C
local BUFFER=.160
local function Flat(v,fallback)
    local d=Vector3(v.x,0,v.z)
    return d:LengthSquared()>.0001 and d:Normalized() or fallback
end
---@param opts table
---@return PlayerCombatMoves
function C.New(opts)
    return setmetatable({o=opts,anim=opts.anim,state=opts.state,rig=opts.rig,hp=100,maxHP=100,
        age=0,invuln=0,hitstop=0,dodgeCool=0,charge=0,hold=0,combo=0,
        motion=Vector3.ZERO,buffer=nil,bufferUntil=0,hitOpen=false,hitPending=false,
        iframe=false,cancelOpen=false,damaged={},dead=false,blocked=false,
        lastAttack=false,lastHeavy=false,shake=0,shakeAge=0,shakeDuration=0},C)
end
function C:Play(id)
    local stats=self.rig:GetStats()
    -- Scale the clip clock; charge_full remains the sole full-charge signal.
    local speed=id=='sword_heavy_charge' and 1/math.max(.1,stats.chargeMultiplier or 1) or 1
    local handle=self.anim:Play(id,{stats=stats,speed=speed})
    if not handle then return false end
    self.clip,self.handle=id,handle
    self.hitOpen,self.hitPending,self.cancelOpen,self.iframe=false,false,false,false
    self.damaged,self.previousHit={},nil
    self.state.SetBusy(true)
    return true
end
function C:Cancel(reason,keepProtection)
    local cancelledHandle=self.handle
    if self.clip=='bow_draw' or self.clip=='bow_hold' then self.cancelUntil=self.age+1.2 end
    self.buffer,self.pending,self.clip,self.handle=nil,nil,nil,nil
    self.pendingFire=nil
    self.trailUntil=0
    self.autoFire,self.pendingReleased=false,false
    if not keepProtection then self.protection={} end
    self.drawFullReached,self.fireCrystal,self.fireCharge,self.fullCharged=false,false,nil,false
    self.hitOpen,self.hitPending,self.cancelOpen,self.iframe=false,false,false,false
    self.hold,self.charge,self.motion,self.knock=0,0,Vector3.ZERO,0
    self.lastAttack,self.lastHeavy,self.blocked=false,false,true
    if keepProtection then
        if cancelledHandle then self.anim:Stop(cancelledHandle,0) end
    else self.anim:Stop(nil,0) end
    self.rig:SetActive(self.state.GetWeapon()); self.rig:SetPose(self.state.GetPose())
    if not self.draining and not keepProtection then self.anim:Poll() end
    self.state.SetBusy(false)
    if self.o.clear then self.o.clear(reason) end
end
function C:CanCancel()
    return not self.clip or self.cancelOpen or self.clip=='sword_heavy_charge'
        or self.clip=='bow_hold' or self.clip=='bow_draw' or self.clip=='sword_draw' or self.clip=='sword_sheath'
        or self.clip=='bow_equip' or self.clip=='bow_sheath'
end
function C:Action(kind,axis)
    if self.dead or not self.state.InCombat() then return false end
    if kind=='dodge' then
        if self.dodgeCool>0 or not self:CanCancel() then return false end
        self:Cancel('dodge',true) -- discard shot, retain an independent getup protection tail
        self.blocked=true -- require held attack to lift before accepting another
        self.state.Activity(true)
        self.moveDir=Flat(axis or Vector3.ZERO,-self.o.forward())
        if self.handle then self.anim:Stop(self.handle,0); self.clip=nil end
        self.rig:SetActive(self.state.GetWeapon())
        if self:Play('dodge_roll') then self.dodgeCool=.6; self.dodgeAt=self.age; self.perfectUsed=false; self.pending=nil; return true end
        return false
    end
    if self.state.TransitionRemaining()>0 then return false end
    if self.clip then return false end
    if self.state.GetPose()~='hand' then
        if not self.state.Activity(true) then return false end
        self.pending,self.pendingReleased=kind,false
        self.hold,self.charge=0,0
        self.autoFire=kind=='heavy' and self.state.GetWeapon()=='bow'
        self.rig:SetPose('back')
        self:Play(self.state.GetWeapon()=='sword' and 'sword_draw' or 'bow_equip')
        return true
    end
    self.state.Activity(true)
    if self.state.GetWeapon()=='sword' and kind~='hold' and self.o.assist then self.o.assist() end
    self.moveDir=self.o.forward()
    local bow=self.state.GetWeapon()=='bow'
    if bow then
        self.charge,self.autoFire,self.pendingReleased=0,kind=='heavy',kind=='light'
        self.drawFullReached,self.fireCrystal,self.fireCharge=false,false,nil
        return self:Play('bow_draw')
    elseif kind=='heavy' then self.autoFire=false; self.combo=0; return self:Play('sword_heavy_release')
    elseif kind=='hold' then self.hold,self.charge,self.fullCharged=0,0,false; return self:Play('sword_heavy_charge')
    else
        self.combo=self.combo%3+1
        return self:Play('sword_light_'..self.combo)
    end
end
function C:Release()
    if self.clip=='sword_heavy_charge' then
        local heavy=self.hold>=.45 -- gesture classification, not a damage window
        self.releaseFull=self.charge>=1
        self.anim:Stop(self.handle,0); self.clip=nil
        self:Action(heavy and 'heavy' or 'light')
    elseif self.clip=='bow_hold' then
        self.fireCharge=self.charge
        self.fireCrystal=self.autoFire==true
        self:Play('bow_release')
    elseif self.clip=='bow_draw' then self.pendingReleased=true
    elseif self.pending=='hold' then self.pending,self.pendingReleased='light',true end
end
function C:Feedback(enemy,info,result,weak,arrow)
    local heavy=info.heavy==true
    local stop=result.partBroken and .10 or (heavy and .08 or .04)
    if arrow then stop=(info.full and weak) and .12 or .03 end
    if not arrow or (info.full and weak) then self.hitstop=math.max(self.hitstop,stop) end
    enemy.hitStop=math.max(enemy.hitStop or 0,stop)
    self.shake,self.shakeAge,self.shakeDuration=heavy and .025 or .01,0,heavy and .10 or .06
    self.shakeDir=info.dir
    if heavy then self.fovAge=0 end
    self.target,self.targetAt=enemy,self.age
    if result.partBroken then self.partNotice={part=result.partBroken,untilTime=self.age+1.2} end
    if weak then self.weakUntil=self.age+1.2 end
    if self.state.GetSetting('damageNumbers') and result.damage then
        self.numbers=self.numbers or {}
        if #self.numbers>=12 then table.remove(self.numbers,1) end
        self.numbers[#self.numbers+1]={pos=info.pos,value=math.floor(result.damage+.5),untilTime=self.age+.7}
    end
    if self.o.feedback then self.o.feedback(info.pos,heavy,result) end
end
function C:ApplyHit(info)
    if self.iframe and self.clip=='dodge_roll' and not self.perfectUsed and self.age-(self.dodgeAt or -1)<=.1 then
        self.perfectUntil,self.perfectUsed=self.age+.8,true
    end
    if self.dead or self.iframe or self.invuln>0 or (self.protection and next(self.protection)) or (self.o.protected and self.o.protected()) then return {hit=false} end
    self.state.OnPlayerHit()
    self:Cancel('hit')
    self.hp=math.max(0,self.hp-info.dmg)
    self.invuln=.8
    self.shake,self.shakeAge,self.shakeDuration=.025,0,.10
    self.shakeDir=info.dir
    self.moveDir=Flat(info.dir or -self.o.forward(),-self.o.forward())
    self.knock=.6
    if self.o.feedback then self.o.feedback(self.o.position()+Vector3(0,.8,0),true,{hit=true,player=true}) end
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
        if e.name=='hit_on' then
            self.hitOpen,self.hitPending,self.hitClip=true,true,e.clip
            self.strikePerfect=self.perfectUntil and self.age<=self.perfectUntil
            self.perfectUntil=nil
        elseif e.name=='hit_off' then self.hitOpen=false; self.trailUntil=self.age+.06
        elseif e.name=='cancel_open' then self.cancelOpen=true
        elseif e.name=='cancel_close' then self.cancelOpen=false
        elseif e.name=='iframe_on' then self.iframe=true
        elseif e.name=='iframe_off' then self.iframe=false
        elseif e.name=='charge_full' or e.name=='draw_full' then
            if e.name=='charge_full' then self.charge,self.fullCharged=1,true end
            self.fullAt=self.age
            if e.name=='draw_full' then self.drawFullReached=true end
        elseif e.name=='weapon_ready' then
            if self.clip:find('weapon_swap_',1,true) then
                self.rig:SetActive(self.state.GetWeapon()); self.rig:SetPose('back'); self.state.FinishTransition()
            else self.rig:SetPose('hand') end
        elseif e.name=='weapon_stowed' or e.name=='weapon_drop' then self.rig:SetPose(e.name=='weapon_drop' and 'hidden' or 'back')
        elseif e.name=='draw_start' then self.rig:SetPose('hand')
        elseif e.name=='draw_min' then
            self:Play('bow_hold')
            if self.pendingReleased then self.pendingReleased=false; self:Release() end
        elseif e.name=='recover_end' then
            self.anim:Stop(self.handle,0); self.clip,self.handle=nil,nil
            self.charge,self.autoFire=0,false
        elseif e.name=='fire' then
            self.pendingFire=self.fireCharge or 0
        elseif e.name=='respawn_ready' then
            self.anim:Stop(nil,0)
            self.clip,self.handle=nil,nil
            self.hp,self.dead,self.invuln=100,false,1
            self.state.SetDead(false); self.state.Exit('respawn')
            if self.o.respawn then self.o.respawn() end
            self:Play('getup')
        elseif e.name=='clip_finished' then
            local finished=self.clip
            self.clip,self.handle,self.iframe=nil,nil,false
            if finished=='sword_draw' or finished=='bow_equip' then
                local pending,released=self.pending or 'light',self.pendingReleased
                local heldTime=self.hold
                self.pending,self.pendingReleased=nil,false; self:Action(pending)
                if pending=='hold' then self.hold=heldTime end
                if released and self.clip=='bow_draw' then self.pendingReleased=true end
            elseif finished=='bow_draw' then self:Play('bow_hold'); if self.pendingReleased then self:Release() end
            elseif finished=='knockdown' then self:Play('getup')
            elseif finished=='getup' then self.state.SetBusy(false)
            else self.charge,self.autoFire=0,false; self.state.SetBusy(false) end
        end
    end end
    self.draining=false
end
---@param dt number
---@param controls table attack/heavy held, attackTap/dodge edges, axis world-space, allowed
function C:Update(dt,controls)
    self.age=self.age+dt; self.invuln=math.max(0,self.invuln-dt)
    if self.state.InCombat() and not self.anim:IsPlaying('stance_combat') then self.anim:Play('stance_combat') end
    self.dodgeCool=math.max(0,self.dodgeCool-dt); self.shakeAge=self.shakeAge+dt
    local attack,heavy=controls.attack==true,controls.heavy==true
    if not controls.allowed then
        if not self.suspended then
            -- A death/getup animation must finish while its input is disabled.
            if not self.dead and self.clip~='getup' then self:Cancel('blocked') end
            self.suspended=true
        end
        self.blocked=true; attack,heavy=false,false
    else self.suspended=false end
    if self.blocked and not controls.attack and not controls.heavy then self.blocked=false end
    local canInput=controls.allowed and not self.blocked and not self.dead and self.state.InCombat()
    local animDt=math.max(0,dt-self.hitstop)
    if canInput then
        if controls.dodge then self.buffer,self.bufferUntil='dodge',self.age+BUFFER end
        if ((heavy and not self.lastHeavy) or controls.heavyTap) and self.buffer~='dodge' then
            self.releaseFull=false; self.buffer,self.bufferUntil='heavy',self.age+BUFFER
        end
        if (attack and not self.lastAttack) or controls.attackTap then
            if self.buffer~='dodge' then self.buffer,self.bufferUntil=(not self.clip and attack) and 'hold' or 'light',self.age+BUFFER end
        end
        if self.buffer and self.age<=self.bufferUntil then
            if self.buffer=='light' and self.cancelOpen and self.clip and self.clip:find('sword_light_',1,true) then
                self.anim:Stop(self.handle,0); self.clip=nil
            end
            if self:Action(self.buffer,controls.axis) then self.buffer=nil end
        elseif self.buffer then self.buffer=nil end
        if self.clip=='sword_heavy_charge' or (self.clip=='sword_draw' and self.pending=='hold') then
            self.hold=self.hold+dt
            self.charge=self.fullCharged and 1 or math.min(.999,self.hold/math.max(.1,self.rig:GetStats().chargeMultiplier or 1))
        end
        if self.clip=='bow_hold' or self.clip=='bow_draw' then
            self.charge=math.min(1,self.charge+animDt/(self.rig:GetStats().draw or .7)); self.anim:SetParam('p',self.charge)
        end
        if self.autoFire and self.drawFullReached and self.clip=='bow_hold' and self.charge>=1 then self:Release() end
        if self.lastAttack and not attack and not self.autoFire then self:Release() end
    end
    self.lastAttack,self.lastHeavy=attack,heavy
    self.hitstop=math.max(0,self.hitstop-dt)
    local moveDir=self.moveDir or self.o.forward() --[[@as Vector3]]
    self.motion=moveDir*self.anim:GetMotion(animDt,dt)
    if self.fovAge then self.fovAge=self.fovAge+dt end
    self:Events()
    if self.knock and self.knock>0 and not self.dead then
        local amount=math.min(self.knock,dt*2.4)
        self.motion=self.motion+(self.moveDir or Vector3.ZERO)*amount; self.knock=self.knock-amount
    end
    self.state.SetBusy(self.clip~=nil)
end
function C:Swap()
    if not self:CanCancel() or self.dead then return false end
    local old,pose=self.state.GetWeapon(),self.state.GetPose()
    self.state.SetBusy(false)
    local nextWeapon=old=='sword' and 'bow' or 'sword'
    local ok=self.state.SetWeapon(nextWeapon)
    if ok then
        self:Cancel('swap')
        self.rig:SetActive(old); self.rig:SetPose(pose)
        self:Play('weapon_swap_'..old..'_to_'..nextWeapon)
    end
    return ok
end
function C:MoveScale()
    if self.dead or self.suspended or self.clip=='getup' or self.clip=='dodge_roll' or self.clip=='death' then return 0 end
    if self.clip and (self.clip:find('hit_',1,true) or self.clip=='knockdown') then return 0 end
    if self.clip=='sword_heavy_charge' then return .4 end
    if self.clip=='bow_hold' or self.clip=='bow_draw' then return self.rig:GetStats().move or .5 end
    if self.clip and self.clip:find('sword_light_',1,true) then return .2 end
    return 1
end
-- After base pose -> anim Apply -> rig Update, query the actual blade capsule.
function C:AfterPose()
    if self.pendingFire~=nil then
        if not self.dead and self.o.fire then self.o.fire(self.pendingFire,self.rig:GetStats(),self.fireCrystal) end
        self.pendingFire=nil
    end
    if not (self.hitOpen or self.hitPending) or self.dead then self.previousHit=nil; return end
    self.hitPending=false
    local hit,stats=self.rig:GetHit(),self.rig:GetStats()
    if not hit.length then return end
    local a=hit.origin --[[@as Vector3]]
    local direction=hit.dir --[[@as Vector3]]
    local b=a+direction*(hit.length*(stats.reach or 1))
    local enemies=self.o.enemies and self.o.enemies() or {}
    local contacts=Hit.Query(enemies,a,b,hit.radius or .12)
    if self.previousHit then
        for _,c in ipairs(Hit.Query(enemies,self.previousHit,b,hit.radius or .12)) do contacts[#contacts+1]=c end
    end
    self.previousHit=b
    for _,contact in ipairs(contacts) do
        local enemy,part=contact.enemy,contact.shape.id
        -- Stone projectiles are distinct targets; a deflection cannot consume the body hit.
        local key=(part and part:find('stone_',1,true)==1) and (tostring(enemy)..part) or enemy
        if not self.damaged[key] and Hit.Visible(self.o.position()+Vector3(0,.9,0),contact.pos,self.o.cast) then
            local heavy=self.hitClip=='sword_heavy_release'
            local perfect=self.strikePerfect
            local info={dmg=(stats.attack or 10)*(heavy and (self.releaseFull and 2.2 or 1.6) or 1),
                poise=(stats.poise or 6)*(heavy and (self.releaseFull and 2.5 or 1.8) or 1)*(perfect and 1.5 or 1),
                armorBreak=(stats.armorBreak or 1)*(heavy and self.releaseFull and 1.5 or 1),knockback=self.combo==3 and .55 or .1,
                part=part,kind='sword',pos=contact.pos,dir=self.o.forward(),source='player',heavy=heavy,combo=self.combo}
            local result=Hit.Apply(enemy,info)
            if result.hit then
                self.damaged[key]=true; self:Feedback(enemy,info,result,contact.shape.weak,false)
            end
        end
    end
end
function C:ShakeOffset()
    if self.shakeAge>=self.shakeDuration or self.shakeDuration<=0 then return Vector3.ZERO end
    local k=2^(-10*self.shakeAge/self.shakeDuration)*self.shake
    return (self.shakeDir or Vector3(1,0,0)):Normalized()*(math.sin(self.age*127)*k)
end
return C
