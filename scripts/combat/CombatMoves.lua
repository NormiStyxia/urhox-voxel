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
function C.ClipSlidePath(p,motion,radius,ground,clear)
    local height=C.SlideFootprint(p,radius,ground)
    if not height then return Vector3.ZERO,true end
    local flat=Vector3(motion.x,0,motion.z)
    local length=flat:Length()
    if length<1e-8 then return Vector3.ZERO,false end
    local dir=flat/length
    local done=0
    while done<length-1e-8 do
        local amount=math.min(.10,length-done)
        local base=Vector3(p.x+dir.x*done,height,p.z+dir.z*done)
        local function Safe(distance)
            local q=base+dir*distance
            local h=C.SlideFootprint(q,radius,ground)
            if not h or math.abs(h-height)>.20+1e-6
                or (clear and not clear(base,Vector3(q.x,h,q.z),radius+.10)) then return nil end
            return h
        end
        local nextHeight=Safe(amount)
        if not nextHeight then
            local lo,hi=0,amount
            while hi-lo>.02 do
                local mid=(lo+hi)*.5
                if Safe(mid) then lo=mid else hi=mid end
            end
            return dir*(done+lo),true
        end
        done,height=done+amount,nextHeight
    end
    return flat,false
end
---@param opts table
---@return PlayerCombatMoves
function C.New(opts)
    return setmetatable({o=opts,anim=opts.anim,state=opts.state,rig=opts.rig,hp=100,maxHP=100,
        age=0,invuln=0,hitstop=0,dodgeCool=0,charge=0,hold=0,combo=0,
        motion=Vector3.ZERO,buffer=nil,bufferUntil=0,hitOpen=false,hitPending=false,
        iframe=false,cancelOpen=false,damaged={},dead=false,blocked=false,
        lastAttack=false,lastHeavy=false,shake=0,shakeAge=0,shakeDuration=0,
        eventPool={{},{},{},{},{},{},{},{}},eventWrite=0,swingSerial=0,feedbackGroups={},
        slideShots={},slideShotPool={{},{}},slideShotWrite=0,slideShotAt=-1},C)
end
-- Injected sound port keeps offline simulations engine-independent.
function C:Sound(name,opts)
    if self.o.audio then return self.o.audio.Play(name,opts or {pos=self.o.position()}) end
end
function C:StopDrawSound()
    if self.drawSound and self.o.audio then self.o.audio.Stop(self.drawSound) end
    self.drawSound=nil
end
function C:Flash(kind)
    if self.rig.Flash then self.rig:Flash(kind) end
end
function C:Play(id,fadeIn)
    local stats=self.rig:GetStats()
    -- Scale the clip clock; charge_full remains the sole full-charge signal.
    local speed=id=='sword_heavy_charge' and 1/math.max(.1,stats.chargeMultiplier or 1) or 1
    local params
    if id=='dodge_slide' then
        local f=self.slideFacing or self.o.forward()
        local d=self.moveDir or -f
        params={moveX=d.x*f.z-d.z*f.x,moveZ=d:DotProduct(f),bow=self.state.GetWeapon()=='bow' and 1 or 0}
    end
    local handle=self.anim:Play(id,{stats=stats,speed=speed,fadeIn=fadeIn,params=params})
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
    self.hitOpen,self.hitPending,self.cancelOpen,self.iframe=false,false,false,false
    self.damaged,self.previousHit,self.hitForward={},nil,nil
    self.state.SetBusy(true)
    return true
end
function C:Cancel(reason,keepProtection)
    if self.o.camera then self.o.camera:Cancel() end
    local cancelledHandle=self.handle
    self:StopDrawSound()
    self:BrakeSlide()
    self.slideFacing,self.slideStopped,self.slideImages=nil,false,false
    self.slideMotionFrame=false
    self.slideShots={}
    for _,shot in ipairs(self.slideShotPool) do shot.time=nil end
    self.slideFovAge=nil
    self.combo,self.comboUntil,self.slideFollowUntil,self.followDistance=0,nil,nil,nil
    self.perfectUntil,self.strikePerfect=nil,false
    if self.clip=='bow_draw' or self.clip=='bow_hold' or self.pendingFire~=nil then
        self.cancelUntil=self.age+1.2
        if self.state.Log then self.state.Log('arrow-cancel','Combat: arrow cancel %s',reason or 'unknown') end
    end
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
-- Cancellation uses the authored events: light1/2 hit_off, light3 +.08,
-- heavy +.16, equipment swap .20. No duplicate numeric attack-window table.
function C:CanDodge()
    return self.clip~='dodge_slide' and self:CanCancel()
end
function C:EndSlide()
    self:BrakeSlide()
    self.anim:Stop(self.handle,.04)
    self.clip,self.handle,self.iframe,self.cancelOpen=nil,nil,false,false
    self.slideFacing,self.slideImages=nil,false
    self.state.SetBusy(false)
end
function C:BrakeSlide()
    if not self.slideDustOpen then return end
    self.slideDustOpen=false
    self:Sound('dodge_land')
    if self.o.dust then self.o.dust(2,self.moveDir) end
    if self.state.Log then self.state.Log('dodge-land','Combat: sfx dodge_land') end
end
function C:Facing()
    if self.clip=='dodge_slide' then return self.slideFacing end
    return self.clip and self.state.GetWeapon()=='sword' and self.moveDir or nil
end
-- Snapshot only the authored .04-.16 interval, at most two pooled records.
-- The optional rig pose port returns its actual active weapon pivot in world
-- space; no inferred grip orientation or counterfeit sword clip identifier.
function C:SlideAfterimages(position,rotation)
    if self.slideImages and self.clip=='dodge_slide' and position and rotation
        and self.age-self.slideShotAt>=.04-1e-8 then
        self.slideShotAt=self.age
        self.slideShotWrite=self.slideShotWrite%2+1
        local shot=self.slideShotPool[self.slideShotWrite]
        shot.clip,shot.time,shot.position,shot.rotation='dodge_slide',self.age,position,rotation
        shot.life=.08
    end
    self.slideShots[1],self.slideShots[2]=nil,nil
    for i=0,1 do
        local shot=self.slideShotPool[(self.slideShotWrite-i-1)%2+1]
        local age=shot.time and self.age-shot.time or 1
        if age>=0 and age<.08-1e-8 then
            shot.age,shot.alpha=age,1-age/.08
            self.slideShots[#self.slideShots+1]=shot
        end
    end
    return self.slideShots
end
function C:Action(kind,axis)
    if self.dead or not self.state.InCombat() then return false end
    if kind=='dodge' then
        if self.dodgeCool>1e-8 or not self:CanDodge() then return false end
        if self.o.slideStart and not self.o.slideStart() then return false end
        local combo=self.combo
        local queued=self.buffer~='dodge' and self.buffer or nil
        local queuedAt=self.bufferAt
        local facing=Flat(self.o.forward(),Vector3.FORWARD)
        local dir=axis or Vector3.ZERO
        dir=dir:LengthSquared()>=.18*.18 and Flat(dir,-facing) or -facing
        self:Cancel('dodge',true) -- discard shot; retain independent getup tail
        self.state.Activity(true)
        self.moveDir,self.slideFacing=dir,facing
        self.rig:SetActive(self.state.GetWeapon()); self.rig:SetPose('hand')
        if not self:Play('dodge_slide',.04) then return false end
        -- Clear the previous strike before the first slide snapshot at .04s.
        -- Scene restores the quality/combat trail switch on its next pose pass.
        if self.rig.SetTrail then self.rig:SetTrail(false) end
        if self.o.camera then self.o.camera:Slide(self.moveDir) end
        self.dodgeCool,self.dodgeAt,self.slideElapsed=.50,self.age,0
        self.combo,self.comboUntil,self.slideFollowUntil=combo,self.age+.60,self.age+.60
        self.perfectUsed,self.slideStopped,self.pending=false,false,nil
        self.iframe=true
        if self.state.GetSetting('dodgeFov') then self.slideFovAge=0 end
        if queued and queuedAt and self.age-queuedAt<=.06 and self.state.GetWeapon()=='sword' then
            self.buffer,self.bufferAt,self.bufferUntil=queued,queuedAt,self.age+.22
        end
        return true
    end
    local follow=self.slideFollowUntil and self.age<=self.slideFollowUntil
    if self.clip=='dodge_slide' then
        if not self.cancelOpen then return false end
        self:EndSlide()
        follow=true
    elseif self.clip and self.cancelOpen and self.clip:find('sword_light_',1,true) then
        self.anim:Stop(self.handle,.04); self.clip,self.handle=nil,nil
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
    if follow then
        if self.o.camera then self.o.camera:Follow() end
        self.followDistance=0; self.slideFollowUntil=nil
    else self.followDistance=nil end
    local bow=self.state.GetWeapon()=='bow'
    if bow then
        self.charge,self.autoFire,self.pendingReleased=0,kind=='heavy',kind=='light'
        self.drawFullReached,self.fireCrystal,self.fireCharge=false,false,nil
        return self:Play('bow_draw',follow and .04 or nil)
    elseif kind=='heavy' then self.autoFire=false; self.combo=0; return self:Play('sword_heavy_release')
    elseif kind=='hold' then self.hold,self.charge,self.fullCharged=0,0,false; return self:Play('sword_heavy_charge')
    else
        if self.comboUntil and self.age>self.comboUntil then self.combo=0 end
        self.comboUntil=nil
        self.combo=self.combo%3+1
        return self:Play('sword_light_'..self.combo,follow and .04 or nil)
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
-- Group envelopes start at FIRST contact: later targets raise the maximum,
-- never restart or add shakes. Bounded storage, including long-lived arrows.
function C:Envelope(key,amp,duration,fov,dir,stop)
    local group=self.feedbackGroups[key]
    if not group then
        local oldestKey,oldest,count=nil,math.huge,0
        for k,g in pairs(self.feedbackGroups) do
            count=count+1
            if g.at<oldest then oldestKey,oldest=k,g.at end
        end
        if count>=32 then self.feedbackGroups[oldestKey]=nil end
        group={at=self.age,amp=0,duration=0,fov=0,stop=0,dir=dir or Vector3.RIGHT}
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
    e.tier=arrow and ('arrow_'..(info.tier or 'weak')) or (info.heavy and 'heavy' or (info.combo==3 and 'third' or 'light'))
    e.material=result.material or info.material or 'soft'
    e.part,e.pos,e.dir,e.normal=result.part or info.part,info.pos,info.dir,info.normal
    e.broke,e.staggered,e.killed=result.broke or result.partBroken~=nil,result.staggered==true,result.killed==true
    e.weak,e.damage,e.poise=weak==true or result.weak==true,result.damage or info.dmg,info.poise or 0
    e.kind,e.enemy='hit',enemy
    if self.observe then self.observe('hit',{clip=info.clip,damage=e.damage,weapon=e.weapon,enemy=enemy,age=self.age}) end
    self.lastHitAt,self.lastHitWeak=self.age,e.weak
    if self.state.Log then self.state.Log('hit:'..tostring(enemy.id)..':'..tostring(e.part),
        'Combat: hit %s part=%s dmg=%.2f poise=%.2f',enemy.id or 'enemy',e.part or 'body',e.damage,e.poise) end
    local stop=e.broke and .10 or (info.heavy and .08 or .04)
    local amp,duration,fov=.01,.06,0
    if e.tier=='third' then amp,duration=.015,.08 end
    if info.heavy then amp,duration,fov=.025,.10,2 end
    if e.broke or e.staggered then amp,duration=.03,.12 end
    if arrow then
        stop=info.full and e.weak and .12 or .03
        amp,duration,fov=0,0,0
        if info.full and e.weak then amp,duration=.008,.05 end
    end
    self:Envelope(e.swingId,amp,duration,fov,e.dir,(not arrow or (info.full and e.weak)) and stop or 0)
    enemy.hitStop=math.max(result.priorHitStop or enemy.hitStop or 0,stop)
    self.target,self.targetAt=enemy,self.age
    if e.broke then self.partNotice={part=result.partBroken or e.part,untilTime=self.age+1.2} end
    if e.weak then self.weakUntil=self.age+1.2 end
    if (enemy.training or self.state.GetSetting('damageNumbers')) and e.damage then
        self.numbers=self.numbers or {}
        if #self.numbers>=12 then table.remove(self.numbers,1) end
        local durationN=enemy.training and 1.2 or .7
        self.numbers[#self.numbers+1]={pos=e.pos,value=math.floor(e.damage+.5),untilTime=self.age+durationN,duration=durationN}
    end
    -- W3 already owns enemy reaction/particles inside the successful settlement.
    local soundOpts=e.audio or {}; e.audio=soundOpts
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
    if self.iframe and self.clip=='dodge_slide' and not self.perfectUsed and (self.slideElapsed or 0)<.10 then
        self.perfectUntil,self.perfectUsed=self.age+.8,true
    end
    if self.dead or self.iframe or self.invuln>0 or (self.protection and next(self.protection)) or (self.o.protected and self.o.protected()) then return {hit=false} end
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
            self.hitOpen,self.hitPending,self.hitClip=true,true,e.clip
            self.hitForward=Flat(self.o.forward(),Vector3.FORWARD)
            self.strikePerfect=self.perfectUntil and self.age<=self.perfectUntil
            self.perfectUntil=nil
        elseif e.name=='hit_off' then
            self.hitOpen=false; self.trailUntil=self.age+.06
            if e.clip=='sword_light_3' and self.o.camera then self.o.camera:Land() end
        elseif e.name=='cancel_open' then self.cancelOpen=true
        elseif e.name=='cancel_close' then self.cancelOpen=false
        elseif e.name=='dust_streak' then
            if self.o.dustStreak then self.o.dustStreak(self.moveDir or self.o.forward()) end
        elseif e.name=='dust_start' or e.name=='dust_stop' then
            local start=e.name=='dust_start'
            if start then
                self.slideDustOpen=true
                self:Sound('dodge')
                if self.o.dust then self.o.dust(3,self.moveDir) end
                if self.state.Log then self.state.Log('dodge-start','Combat: sfx dodge_start') end
            else self:BrakeSlide() end
        elseif e.name=='afterimage_on' then self.slideImages=true
        elseif e.name=='afterimage_off' then self.slideImages=false
        elseif e.name=='move_end' then self.slideStopped=true
        elseif e.name=='iframe_on' then self.iframe=true
        elseif e.name=='iframe_off' then self.iframe=false
        elseif e.name=='charge_full' or e.name=='draw_full' then
            if e.name=='charge_full' then self.charge,self.fullCharged=1,true; self:Flash('full_charge') end
            self.fullAt=self.age
            if e.name=='draw_full' and not self.drawFullReached then
                self.drawFullReached=true; self.bowFullAt=self.age; self:Sound('bow_full')
                if self.o.camera then self.o.camera:Full() end
            end
        elseif e.name=='weapon_ready' then
            if not self.rig.PopEvents then self:Flash('draw'); self:Sound('blade_draw') end
            if self.clip:find('weapon_swap_',1,true) then
                self.rig:SetActive(self.state.GetWeapon()); self.rig:SetPose('back'); self.state.FinishTransition()
            else self.rig:SetPose('hand') end
        elseif e.name=='weapon_stowed' or e.name=='weapon_drop' then
            if e.name=='weapon_stowed' and not self.rig.PopEvents then self:Flash('sheath'); self:Sound('blade_sheath') end
            self.rig:SetPose(e.name=='weapon_drop' and 'hidden' or 'back')
        elseif e.name=='draw_start' then self.rig:SetPose('hand')
        elseif e.name=='draw_min' then
            self:Play('bow_hold')
            if self.pendingReleased then self.pendingReleased=false; self:Release() end
        elseif e.name=='recover_end' then
            if self.state.Log then self.state.Log('clip-finish:'..self.clip,'Combat: clip %s finish',self.clip) end
            self.anim:Stop(self.handle,0); self.clip,self.handle=nil,nil
            self.charge,self.autoFire=0,false
        elseif e.name=='fire' then
            self:StopDrawSound()
            self.pendingFire=self.fireCharge or 0
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
            self.clip,self.handle,self.iframe=nil,nil,false
            if finished=='dodge_slide' then self.slideFacing,self.slideImages=nil,false end
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
-- Single buffered edge. Preserve a latch across the frame containing .22;
-- ConsumeBuffer is called again after Poll so there is no extra idle frame.
function C:ConsumeBuffer(axis,atBoundary)
    if not self.buffer then return end
    local latch=self.clip=='dodge_slide' and self.buffer~='dodge'
        and self.bufferUntil>=self.dodgeAt+.22-1e-8
    local valid=self.age<=self.bufferUntil+1e-8 or (atBoundary and self.cancelOpen and latch)
    if not valid then
        if latch and not self.cancelOpen and (self.slideElapsed or 0)<.22 then return end
        self.buffer=nil; return
    end
    local kind=self.buffer
    if self:Action(kind,axis) and self.buffer==kind then self.buffer=nil end
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
    if controls.allowed and not self.dead and self.state.InCombat() and controls.dodge then
        if not self:Action('dodge',controls.axis) then
            self.buffer,self.bufferAt,self.bufferUntil='dodge',self.age,self.age+BUFFER
        end
        canInput=false -- old held attack cannot be inherited by the new slide
    end
    if canInput then
        if ((heavy and not self.lastHeavy) or controls.heavyTap) and self.buffer~='dodge' then
            self.releaseFull=false; self.buffer,self.bufferAt,self.bufferUntil='heavy',self.age,self.age+BUFFER
        end
        if (attack and not self.lastAttack) or controls.attackTap then
            if self.buffer~='dodge' then
                local sliding=self.clip=='dodge_slide'
                -- Bow accepts a NEW press after cancel_open; it never resumes old charge.
                if not sliding or self.state.GetWeapon()=='sword' or self.cancelOpen then
                    self.buffer=(self.state.GetWeapon()=='bow' or (not self.clip and attack)) and 'hold' or 'light'
                    self.bufferAt,self.bufferUntil=self.age,self.age+BUFFER
                    if sliding and self.state.GetWeapon()=='sword' and (self.slideElapsed or 0)<=.06 then
                        self.bufferUntil=math.max(self.bufferUntil,self.dodgeAt+.22)
                    end
                end
            end
        end
        self:ConsumeBuffer(controls.axis)
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
    local sliding=self.clip=='dodge_slide'
    self.slideMotionFrame=sliding
    local stepDt=sliding and dt or animDt
    if sliding and self.buffer and self.buffer~='dodge' and (self.slideElapsed or 0)<.22
        and self.age-dt<=self.bufferUntil then
        stepDt=math.min(stepDt,.22-self.slideElapsed)
    end
    if sliding and controls.axis and controls.axis:LengthSquared()>=.18*.18
        and self.slideElapsed<.26 then stepDt=math.min(stepDt,.26-self.slideElapsed) end
    local moveDir=self.moveDir or self.o.forward() --[[@as Vector3]]
    -- Sound timing derives from the authored active boundary, not a hit table.
    if not self.whoosh and self.clip and (self.clip:find('sword_light_',1,true) or self.clip=='sword_heavy_release') then
        local clip=require('combat.AnimClips').Clips[self.clip]
        local threshold=math.max(0,clip.phases.active[1]-.02)
        self.whooshTime=self.whooshTime+stepDt*(clip.speedStat and self.rig:GetStats()[clip.speedStat] or 1)*(self.anim.timeScale or 1)
        if self.whooshTime>=threshold then
            self.whoosh=true; self:Sound('sword_whoosh',{pos=self.o.position(),tier=self.combo>0 and self.combo or 3})
        end
    end
    local metres=self.anim:GetMotion(stepDt,sliding and stepDt or dt)
    if sliding then
        self.slideElapsed=(self.slideElapsed or 0)+stepDt
        if self.slideStopped then metres=0 end
    elseif self.followDistance and self.clip and self.clip:find('sword_light_',1,true) then
        metres=math.min(metres,math.max(0,.35-self.followDistance))
        self.followDistance=self.followDistance+metres
    end
    self.motion=moveDir*metres
    if sliding and self.o.slideMotion and metres>0 then
        self.motion,self.slideStopped=self.o.slideMotion(self.motion)
    elseif self.clip and (self.clip:find('sword_light_',1,true) or self.clip=='sword_heavy_release')
        and self.o.attackMotion and metres>0 then
        self.motion=self.o.attackMotion(self.motion)
        self.slideMotionFrame=true -- already footprint/wall checked, do not re-run endpoint guard
    end
    if self.fovAge then self.fovAge=self.fovAge+dt end
    self:Events()
    if sliding then
        self.iframe=self.clip=='dodge_slide' and self.slideElapsed<.20-1e-8
        if controls.allowed and not self.dead then
            self:ConsumeBuffer(controls.axis,true)
            if self.clip=='dodge_slide' and self.slideElapsed>=.26 and controls.axis
                and controls.axis:LengthSquared()>=.18*.18 then self:EndSlide() end
        end
        if stepDt<dt then
            local remaining=dt-stepDt
            -- The old impulse cannot leak into the incoming attack. Advance
            -- independent protection/afterimage clocks, not a second root move.
            self.anim:GetMotion(0,remaining)
            self:Events()
        end
    end
    if self.slideFovAge then self.slideFovAge=self.slideFovAge+dt end
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
    if self.dead or self.suspended or self.clip=='getup' or self.clip=='dodge_slide' or self.clip=='death' then return 0 end
    if self.clip and (self.clip:find('hit_',1,true) or self.clip=='knockdown') then return 0 end
    if self.clip=='sword_heavy_charge' then return .4 end
    if self.clip=='bow_hold' or self.clip=='bow_draw' then return self.rig:GetStats().move or .5 end
    if self.clip and self.clip:find('sword_light_',1,true) then return .2 end
    return 1
end
-- Snapshot the strike's facing at hit_on; translate its zone with the actual
-- controller position every active frame. Neither rig pose nor blade length is
-- a prerequisite for melee settlement (the weapon path remains visual only).
function C.MeleeZone(id,position,forward,reach,slam)
    local offset=id=='sword_light_3' and .4 or 0
    return {origin=position+forward*offset,source=position+Vector3(0,.9,0),forward=forward,
        radius=(slam and 2 or 1.8)*math.max(.1,reach or 1),
        angle=slam and 90 or (id=='sword_heavy_release' and 360 or (id=='sword_light_3' and 100 or 120)),
        low=-.3,high=2}
end
-- Still called after the physical actor/base animation update. hitPending covers
-- a low-FPS frame which contains both hit_on and hit_off exactly once.
function C:AfterPose()
    if self.pendingFire~=nil then
        if not self.dead and self.o.fire then self.o.fire(self.pendingFire,self.rig:GetStats(),self.fireCrystal) end
        self.pendingFire=nil
    end
    if not (self.hitOpen or self.hitPending) or self.dead then self.previousHit=nil; return end
    self.hitPending=false
    local stats=self.rig:GetStats()
    local position=self.o.position()
    local direction=self.hitForward or Flat(self.o.forward(),Vector3.FORWARD)
    local enemies=self.o.enemies and self.o.enemies() or {}
    local zone=C.MeleeZone(self.hitClip,position,direction,stats.reach)
    local contacts=Hit.QueryZone(enemies,zone)
    if self.hitClip=='sword_heavy_release' then
        local phase=require('combat.AnimClips').Clips.sword_heavy_release.phases.active
        -- Final third of the EXISTING active interval extends the forward slam;
        -- it does not open another damage window or reset the swing hit ledger.
        if (self.whooshTime or 0)>=phase[1]+(phase[2]-phase[1])*2/3 then
            local slam=C.MeleeZone(self.hitClip,position,direction,stats.reach,true)
            for _,contact in ipairs(Hit.QueryZone(enemies,slam)) do contacts[#contacts+1]=contact end
            table.sort(contacts,function(a,b)return a.distance2<b.distance2 end)
        end
    end
    for _,contact in ipairs(contacts) do
        local enemy,part=contact.enemy,contact.shape.id
        -- Stone projectiles are distinct targets; a deflection cannot consume the body hit.
        local key=(part and part:find('stone_',1,true)==1) and (tostring(enemy)..part) or enemy
        if not self.damaged[key] and Hit.Visible(position+Vector3(0,.9,0),contact.pos,self.o.cast) then
            local heavy=self.hitClip=='sword_heavy_release'
            local perfect=self.strikePerfect
            local info={dmg=(stats.attack or 10)*(heavy and (self.releaseFull and 2.2 or 1.6) or 1),
                poise=(stats.poise or 6)*(heavy and (self.releaseFull and 2.5 or 1.8) or 1)*(perfect and 1.5 or 1),
                armorBreak=(stats.armorBreak or 1)*(heavy and self.releaseFull and 1.5 or 1),knockback=self.combo==3 and .55 or .1,
                part=part,material=contact.shape.material or 'soft',normal=contact.normal,
                swingId='sword:'..self.swingSerial,tier=heavy and 'heavy' or (self.combo==3 and 'third' or 'light'),kind='sword',clip=self.hitClip,pos=contact.pos,dir=direction,source='player',heavy=heavy,combo=self.combo}
            local result=Hit.Apply(enemy,info)
            if result.hit then
                self.damaged[key]=true; self:Feedback(enemy,info,result,contact.shape.weak,false)
            end
        end
    end
end
function C:ShakeOffset()
    if self.state.GetSetting('cameraShake')==false then return Vector3.ZERO end
    local peak,dir=0,Vector3.RIGHT
    for _,g in pairs(self.feedbackGroups) do
        local age=self.age-g.at
        if g.duration>0 and age<g.duration then
            local k=g.amp*(1-age/g.duration)^2
            if k>peak then peak,dir=k,g.dir end
        end
    end
    return dir:Normalized()*(math.sin(self.age*127)*peak)
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
        print(string.format('Dummy hit: %s %s dmg=%.2f part=%s',weapon,info.tier or info.clip or 'unknown',info.dmg,info.part or 'body'))
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
function C.EmitDustStreak(pool,owner,pos,dir,ground)
    if not pool or not pool.slots or not pool.Hide then return 0 end
    local originY=ground(pos)
    if not originY then return 0 end
    local first=pool.serial
    pool:Emit(owner,{pos=pos,dir=dir,normal=Vector3.UP,material='stone',kind='dust'})
    local count=0
    for _,slot in ipairs(pool.slots) do
        if slot.active and slot.owner==owner and slot.serial>first then
            local i=slot.serial-first
            local at=pos-dir*((i-1)*.18)
            local y=i<=4 and ground(at) or nil
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
