local Base=require('combat.enemies.EnemyBase')
---@class StoneBeast: EnemyBase
local Beast=setmetatable({}, {__index=Base})
Beast.__index=Beast
-- Part armor is local tuning; total HP/poise/timings are the design's fixed values.
Beast.Config={kind='stone_beast',enemy='beast',name='石甲兽',boss=true,hp=600,poise=100,radius=1.15,height=2.5,
    speed=2.0,aggro=13,leash=30,attackDistance=9,defaultPart='back_armor',voxelSize=.112,
    parts={
        {id='head',material='armor',x=0,y=1.15,z=1.05,radius=.50,armor=70,weak=true},
        {id='foreleg_l',material='armor',x=-.65,y=.45,z=.68,radius=.35,armor=40},
        {id='foreleg_r',material='armor',x=.65,y=.45,z=.68,radius=.35,armor=40},
        {id='back_armor',material='armor',x=0,y=1.30,z=-.25,radius=.85,armor=70},
        {id='core',material='core',x=0,y=1.45,z=-.15,radius=.37,armor=35,weak=true,hidden=true},
    },
    attacks={
        {name='charge',telegraph=.6,duration=.6,recover=1.0,travel=9,range=9,hitRange=1.5,warning='line',damage=22,poise=22},
        {name='sweep',telegraph=.7,duration=.18,recover=.85,range=3.2,cosine=.5,warning='fan',damage=18,poise=15},
        {name='stomp',telegraph=1.1,duration=.15,recover=1.0,range=4,jumpable=true,warning='ring',damage=20,poise=20},
    },
    sculpt={
        {'body',0,.91,-.15,.72,.48,1.12,216,217,219},
        {'back_armor',0,1.39,-.30,.77,.31,1.05,218,216,219},
        {'core',0,1.38,-.15,.34,.30,.42,221,222,219},
        {'head',0,1.08,1.12,.46,.38,.51,216,217,220},
        {'jaw',0,.84,1.29,.35,.15,.34,218,216,219},
        {'foreleg_l',-.63,.43,.69,.26,.43,.28,216,217,219},
        {'foreleg_r',.63,.43,.69,.26,.43,.28,216,217,219},
        {'rear_l',-.58,.41,-.91,.25,.41,.29,218,216,219},
        {'rear_r',.58,.41,-.91,.25,.41,.29,218,216,219},
        {'tail',0,.66,-1.40,.20,.18,.25,218,216,220},
    }}
function Beast.New(scene,world,terrain,combat,position,id)
    local self=setmetatable(Base.Create(scene,world,terrain,combat,Beast.Config,position,id),Beast)
    -- Per-instance stage-two attacks; never mutate shared config tables.
    self.fastStomp={name='stomp',telegraph=1.1*.85,duration=.15,recover=.85,range=4,
        jumpable=true,warning='ring',damage=20,poise=20}
    self.secondCharge={name='charge',telegraph=.6*.85,duration=.6,recover=.85,travel=9,
        range=9,hitRange=1.5,warning='line',damage=22,poise=22}
    self.rageAttacks={}
    for i,a in ipairs(Beast.Config.attacks) do
        local rage={}
        for k,v in pairs(a) do rage[k]=v end
        rage.telegraph,rage.recover=a.telegraph*.85,a.recover*.85
        self.rageAttacks[i]=rage
    end
    self.doubleCharge=false
    self.pendingTrip,self.chargeWillTrip,self.chargeStunned=false,false,false
    self.phasePulse=0
    self.ragePending,self.rageActive,self.rageDone=false,false,false
    self.rageTime,self.rageRoared=0,false
    self.phaseImpact={pos=Vector3.ZERO,dir=Vector3.UP,normal=Vector3.UP,material='armor',tier='light',kind='phase'}
    return self
end
function Beast:OnBreak(id)
    if id=='foreleg_l' or id=='foreleg_r' then self.pendingTrip=true end
end
function Beast:OnDamaged()
    if self.hp>0 and self.hp<self.maxHP*.5 and self.phase==1 then
        self.phase,self.ragePending=2,true
        self.doubleCharge=false
        -- A simultaneous poise break takes precedence; rage waits for stand-up.
        if self.state~=Base.State.STAGGER then self:SetState(Base.State.RECOVER) end
    end
end
function Beast:CanTelegraph()
    return not self.ragePending and not self.rageActive and Base.CanTelegraph(self)
end
function Beast:TickPresentation(dt,target)
    if self.state==Base.State.STAGGER then return false end
    if self.ragePending then
        self.ragePending,self.rageActive,self.rageTime,self.rageRoared=false,true,0,false
        self:SetState(Base.State.RECOVER)
    end
    if not self.rageActive then return false end
    self.rageTime=math.min(1.2,self.rageTime+dt)
    self.phasePulse=1-self.rageTime/1.2
    if not self.rageRoared and self.rageTime+1e-8>=.45 then
        self.rageRoared=true
        self:EmitEvent('boss_roar')
        self:EmitEvent('camera_shake')
        if self.parts.back_armor.broken and self.particles then
            self.phaseImpact.pos=self.hurtShapes[4].center
            self.particles:Emit(self,self.phaseImpact)
        end
    end
    if self.rageTime>=1 then
        local distance=self:Face(target)
        if distance>self.config.attackDistance then
            self:Move(self.fx*self.config.speed*dt,self.fz*self.config.speed*dt)
        end
    end
    if self.rageTime+1e-8>=1.2 then
        self.rageActive,self.rageDone,self.phasePulse=false,true,0
        self.attackIndex=0 -- next charge has a fresh, complete telegraph
        self:SetState(Base.State.CHASE)
    end
    return true
end
function Beast:SelectAttack()
    Base.SelectAttack(self)
    if self.phase==2 then self.attack=self.rageAttacks[self.attackIndex] end
    self.doubleCharge=self.phase==2 and self.attack.name=='charge'
end
function Beast:Chase(dt,target,distance)
    self:Face(target)
    -- Charge starts the cycle; close distance for the later sweep/stomp.
    local nextIndex=self.attackIndex%3+1
    local reach=nextIndex==1 and 9 or (nextIndex==2 and 3.2 or 4)
    if distance<=reach then self:StartAttack()
    else
        local speed=self.config.speed*(self.phase==2 and 1.15 or 1)
        self:Move(self.fx*speed*dt,self.fz*speed*dt)
    end
end
function Beast:BeginAttack()
    self.chargeStunned=false
    if self.attack.name=='charge' then
        self.chargeWillTrip,self.pendingTrip=self.pendingTrip,false
    end
end
function Beast:FinishAttack()
    if self.attack.name=='charge' and self.chargeWillTrip then
        self.chargeWillTrip=false
        self:Stumble(1) -- one extra stumble, not a full-body 3s down/damage multiplier
    else Base.FinishAttack(self) end
end
function Beast:Stagger(seconds,down)
    local entered=Base.Stagger(self,seconds,down)
    if entered then
        self.doubleCharge=false
        if self.chargeWillTrip then self.pendingTrip=true; self.chargeWillTrip=false end
    end
    return entered
end
function Beast:AttackStep(dt,target)
    if self.state~=Base.State.ATTACK then return end
    if self.attack.name=='charge' then
        local step=math.min(9-self.attackTravel,15*dt)
        local moved=self:Move(self.fx*step,self.fz*step)
        self.attackTravel=self.attackTravel+step
        if not moved then
            self.doubleCharge=false
            if self.chargeWillTrip then self.pendingTrip=true; self.chargeWillTrip=false end
            if (self.blockReason=='pillar' or self.blockReason=='wall') and not self.chargeStunned then
                self.chargeStunned=true; self:Stagger(2.5,true)
            else self:SetState(Base.State.RECOVER) end
            return
        end
        self:DamagePlayer(target,1.5,nil,false)
    else
        self:DamagePlayer(target,self.attack.range,self.attack.cosine,self.attack.jumpable)
    end
end
function Beast:AfterRecover()
    if self.doubleCharge then
        if not self:CanTelegraph() then return end
        local target=self.combat.PlayerPos and self.combat.PlayerPos() or self.lastTarget
        if target then self:Face(target) end
        self.attack=self.secondCharge
        if self:SetState(Base.State.TELEGRAPH) then self.doubleCharge=false end
    else Base.AfterRecover(self) end
end
function Beast:TickExtras(dt,target)
    self.lastTarget=target
    if self.hitStop<=0 and self.state==Base.State.TELEGRAPH and self.attack.name=='stomp' then
        if self.stateTime<self.attack.telegraph*.3 then self:Move(-self.fx*dt*1.4,-self.fz*dt*1.4) end
    end
end
function Beast:UpdatePose()
    Base.UpdatePose(self)
    if self.rageActive and not self.down then
        local t=self.rageTime
        if t<.2 then self.poseY=-.12*t/.2; self.posePitch=8*t/.2
        elseif t<.45 then self.poseY=-.12; self.posePitch=8-20*(t-.2)/.25
        elseif t<.7 then self.poseY=-.10; self.posePitch=-12
        else
            local settle=math.max(0,1-(t-.7)/.3)
            self.poseY,self.posePitch=-.1*settle,-12*settle
        end
        return
    end
    if self.state==Base.State.TELEGRAPH and self.attack.name=='stomp' then
        self.poseY=math.max(0,math.sin(self.warning.progress*math.pi))*1.1
    end
end
function Beast:Reset()
    local reset=Base.Reset(self)
    if reset then
        self.doubleCharge,self.phasePulse=false,0
        self.ragePending,self.rageActive,self.rageDone=false,false,false
        self.rageTime,self.rageRoared=0,false
        self.pendingTrip,self.chargeWillTrip,self.chargeStunned=false,false,false
    end
    return reset
end
return Beast
