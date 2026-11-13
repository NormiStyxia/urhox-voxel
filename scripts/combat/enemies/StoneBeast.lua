local Base=require('combat.enemies.EnemyBase')
---@class StoneBeast: EnemyBase
local Beast=setmetatable({}, {__index=Base})
Beast.__index=Beast
-- Part armor is local tuning; total HP/poise/timings are the design's fixed values.
Beast.Config={kind='stone_beast',name='石甲兽',boss=true,hp=600,poise=100,radius=1.15,height=2.5,
    speed=2.0,aggro=13,leash=30,attackDistance=9,defaultPart='back_armor',voxelSize=.112,
    parts={
        {id='head',x=0,y=1.15,z=1.05,radius=.50,armor=70,weak=true},
        {id='foreleg_l',x=-.65,y=.45,z=.68,radius=.35,armor=40},
        {id='foreleg_r',x=.65,y=.45,z=.68,radius=.35,armor=40},
        {id='back_armor',x=0,y=1.30,z=-.25,radius=.85,armor=70},
        {id='core',x=0,y=1.45,z=-.15,radius=.37,armor=35,weak=true,hidden=true},
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
    return self
end
function Beast:OnBreak(id)
    if id=='foreleg_l' or id=='foreleg_r' then self.pendingTrip=true end
end
function Beast:OnDamaged()
    if self.hp<self.maxHP*.5 and self.phase==1 then
        self.phase,self.phasePulse=2,1
        -- Phase and armor are separate: cracked visuals do not break/expose the core.
    end
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
    self.phasePulse=math.max(0,self.phasePulse-dt)
    if self.hitStop<=0 and self.state==Base.State.TELEGRAPH and self.attack.name=='stomp' then
        if self.stateTime<self.attack.telegraph*.3 then self:Move(-self.fx*dt*1.4,-self.fz*dt*1.4) end
    end
end
function Beast:UpdatePose()
    Base.UpdatePose(self)
    if self.state==Base.State.TELEGRAPH and self.attack.name=='stomp' then
        self.poseY=math.max(0,math.sin(self.warning.progress*math.pi))*1.1
    end
end
function Beast:Reset()
    local reset=Base.Reset(self)
    if reset then
        self.doubleCharge,self.phasePulse=false,0
        self.pendingTrip,self.chargeWillTrip,self.chargeStunned=false,false,false
    end
    return reset
end
return Beast
