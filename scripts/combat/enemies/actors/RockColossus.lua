local Base = require('combat.enemies.EnemyBase')
local Fault=require('combat.enemies.actors.RockColossusFault')
local S = Base.State
local Colossus = setmetatable({}, {__index = Base})
Colossus.__index = Colossus

local sweep = {name='quarry_sweep', telegraph=.78, duration=.40, recover=.82,
    range=2.85, cosine=.5, warning='fan', damage=15, poise=13}
local slam = {name='quarry_fault', telegraph=1.12, duration=1.42, recover=1.05,
    range=6.25, pillarCount=Fault.COUNT, warning='line', damage=21, poise=20}
local SWEEP_START, SWEEP_END = .10, .24
local IMPACT=Fault.IMPACT
-- Base.CanDamage pads ranges by the player capsule. The marker is its outer limit.
local CAPSULE = .32

Colossus.Config = {kind='rock_colossus', model='RockColossus', enemy='beast', name='岩甲巨兽',
    hp=300, radius=.90, height=3.8, speed=1.55, aggro=11, leash=26,
    attackDistance=sweep.range, defaultPart='torso', attacks={sweep,slam}, voxelSize=.10, sculpt={},
    parts={
        {id='torso', material='stone', x=0,y=2.04,z=.15,radius=.76},
        {id='head', material='stone', x=0,y=3.16,z=.18,radius=.43},
        {id='crystal', material='core', x=1.45,y=3.49,z=.42,radius=.25,weak=true,weakMultiplier=1.85},
        {id='fist_r', material='armor', x=1.98,y=1.02,z=.47,radius=.57},
        {id='fist_l', material='stone', x=-1.75,y=1.30,z=.23,radius=.33},
        {id='upper_arm_r',material='armor',x=1.48,y=2.90,z=.12,radius=.44},
        {id='upper_arm_l',material='armor',x=-1.48,y=2.90,z=.12,radius=.44},
        {id='leg_r',material='stone',x=.65,y=.59,z=.25,radius=.34},
        {id='leg_l',material='stone',x=-.65,y=.59,z=.25,radius=.34},
    }}

local function ramp(t, start, finish)
    return math.max(0, math.min(1, (t-start)/(finish-start)))
end
local function ease(t, start, finish)
    local u = ramp(t, start, finish)
    return u*u*(3-2*u)
end

-- All pivots are siblings. Carry the wrist and crystal around the shoulder pivot
-- with the same Y-X swing so they stay seated while the right arm rises overhead.
local function shoulder(id, p, pitch, yaw, lift)
    local dx, dy, dz = 0, 0, 0
    if id == 'fist_r' then dx,dy,dz = .75,-.90,.10
    elseif id == 'crystal' then dx,dy,dz = .40,.40,.20 end
    local a,b = math.rad(pitch), math.rad(yaw)
    local ca,sa,cb,sb = math.cos(a),math.sin(a),math.cos(b),math.sin(b)
    local y,z = dy*ca-dz*sa, dy*sa+dz*ca
    p.x,p.y,p.z = dx*cb+z*sb-dx, y-dy+lift, z*cb-dx*sb-dz
    p.pitch,p.yaw = pitch,yaw
end

-- Final y offsets put the rotated stones on the floor. The quartz stays on
-- its broken shoulder while the torso falls, then drops off and lands last.
local fallen = { -- release, land, travel XYZ, pitch
    torso       ={.28,.67,  0,   -1.00,-.38,-90},
    head        ={.39,.78, -.33,-2.60,-.94,-90},
    leg_l       ={.08,.36, -.12,-.70, .10, 90},
    leg_r       ={.10,.39,  .13,-.70, .09, 90},
    upper_arm_l ={.34,.71, -.57,-2.20,-.24,-90},
    fist_l      ={.32,.65, -.40, -1.40, .23, 90},
    upper_arm_r ={.40,.81,  .60,-2.20,-.26,-90},
    fist_r      ={.37,.68,  .45, -.90, .26, 90},
    crystal     ={.73,1.04, .91,-2.70,-.37, 90},
}
local function deathPose(id,p,t)
    local frame=fallen[id]
    if not frame then return end
    local knee=ease(t,.04,.34)
    local drop=ease(t,frame[1],frame[2])
    local isLeg=id=='leg_r' or id=='leg_l'
    local squat=isLeg and .08 or .30
    if id=='crystal' then squat=.74 end
    p.x,p.z=frame[3]*drop,frame[5]*drop
    p.y=-squat*knee*(1-drop)+frame[4]*drop
    p.pitch=(isLeg and 16 or 8)*knee*(1-drop)+frame[6]*drop
end

function Colossus.Config.posePart(enemy,id,p)
    if enemy.dead then deathPose(id,p,enemy.deathTime); return end
    local state,t=enemy.state,enemy.stateTime
    local right=id=='upper_arm_r' or id=='fist_r' or id=='crystal'
    local legs=id=='leg_r' or id=='leg_l'
    if state==S.TELEGRAPH or state==S.ATTACK or state==S.RECOVER then
        local wind,stroke,hold=1,0,1
        if state==S.TELEGRAPH then wind=ease(t,0,enemy.attack.telegraph*.8)
        elseif state==S.ATTACK then
            local endTime=enemy.attack==slam and IMPACT or SWEEP_END
            stroke=ease(t,0,endTime)
        else stroke,hold=1,1-ease(t,.12,enemy.attack.recover) end
        local ready=wind*(1-stroke)*hold
        local follow=stroke*hold
        if enemy.attack==slam then
            if right then shoulder(id,p,-151*ready-17*follow,-12*ready,-.561*follow)
            elseif id=='torso' or id=='head' then p.pitch=-12*ready+20*follow; p.y=.08*ready-.19*follow
            elseif legs then p.pitch=9*follow; p.z=.06*follow
            else p.pitch=-19*ready-31*follow; p.z=.15*follow end
        else
            if right then shoulder(id,p,-69*ready-76*follow,68*ready-74*follow,.06*(ready+follow))
            elseif id=='torso' or id=='head' then p.yaw=18*ready-24*follow; p.roll=-4*ready+6*follow
            elseif not legs then p.pitch=17*ready-20*follow end
        end
    else
        local walking=state==S.CHASE or state==S.PATROL
        local beat=math.sin(enemy.poseAge*(walking and 5.8 or 2.1))
        if right then shoulder(id,p,(walking and 10 or 2)*beat,0,.014*beat)
        elseif legs and walking then
            local step=(id=='leg_r' and 1 or -1)*beat
            p.pitch=14*step; p.y=.09*math.max(0,step); p.z=.12*step
        elseif id=='torso' or id=='head' then p.y=.023*(walking and math.abs(beat) or beat)
        elseif not legs then p.pitch=(walking and -12 or -2)*beat end
    end
    local recoil=1-ramp(enemy.reaction.recoilAge,0,.20)
    if right then p.x=p.x+.10*recoil; p.y=p.y+.07*recoil; p.roll=p.roll+10*recoil
    elseif id=='torso' then p.x=p.x-.06*recoil; p.yaw=p.yaw-9*recoil end
end

function Colossus.New(scene,world,terrain,combat,position,id)
    local self=setmetatable(Base.Create(scene,world,terrain,combat,Colossus.Config,position,id),Colossus)
    self.fault=Fault.New(scene)
    self.shapePose={}
    self.chips={kind='phase',material='stone',dir=Vector3.UP,normal=Vector3.UP}
    self.dust={kind='dust', material='stone', dir=Vector3.UP, normal=Vector3.UP, tier='light'}
    return self
end

-- Carry the archery spheres through the same part and body transforms as the model.
local movingPivots={fist_r={1.65,1.80,.10}, crystal={1.30,3.10,.20}, fist_l={-1.65,1.80,.10},
    upper_arm_l={-.90,2.70,0},upper_arm_r={.90,2.70,0},torso={0,1.50,0},head={0,2.8,0},
    leg_r={.65,1.3,0},leg_l={-.65,1.3,0}}
function Colossus:SyncShapes()
    Base.SyncShapes(self)
    if not self.active or self.dead then return end
    local recoil=math.max(0,1-self.reaction.recoilAge/.12)
    local roll=math.rad(self.poseRoll)
    local pitch=math.rad(self.posePitch+self.reaction.bodyPitch*recoil)
    local yaw=math.rad(self.reaction.bodyYaw*recoil)
    local cr,sr,cp,sp,cy,sy=math.cos(roll),math.sin(roll),math.cos(pitch),math.sin(pitch),math.cos(yaw),math.sin(yaw)
    for _,h in ipairs(self.hurtShapes) do
        local pivot=movingPivots[h.id]
        if pivot then
            local p=self.shapePose
            p.x,p.y,p.z,p.pitch,p.yaw,p.roll=0,0,0,0,0,0
            self.config.posePart(self,h.id,p)
            local spec=self.parts[h.id].spec
            local dx,dy,dz=spec.x-pivot[1],spec.y-pivot[2],spec.z-pivot[3]
            local roll,pitch,yaw=math.rad(p.roll),math.rad(p.pitch),math.rad(p.yaw)
            local x,y=dx*math.cos(roll)-dy*math.sin(roll),dx*math.sin(roll)+dy*math.cos(roll)
            local z=y*math.sin(pitch)+dz*math.cos(pitch)
            local ly=pivot[2]+p.y+y*math.cos(pitch)-dz*math.sin(pitch)
            local lx=pivot[1]+p.x+x*math.cos(yaw)+z*math.sin(yaw)
            local lz=pivot[3]+p.z+z*math.cos(yaw)-x*math.sin(yaw)
            lx,ly=lx*cr-ly*sr,lx*sr+ly*cr
            ly,lz=ly*cp-lz*sp,ly*sp+lz*cp
            lx,lz=lx*cy+lz*sy+self.posePivot*sr,lz*cy-lx*sy
            h.center=Vector3(self.position.x+lx*self.fz+lz*self.fx,
                self.position.y+self.poseY+ly+self.posePivot*(1-cr), self.position.z-lx*self.fx+lz*self.fz)
        end
    end
end

function Colossus:Chase(dt,target,distance)
    self:Face(target)
    local nextAttack=self.config.attacks[self.attackIndex%2+1]
    if distance<=nextAttack.range then self:StartAttack()
    else self:Move(self.fx*self.config.speed*dt,self.fz*self.config.speed*dt) end
end

function Colossus:BeginAttack()
    self.impacted=false
end

function Colossus:AttackStep(dt,target)
    local t=self.stateTime
    if self.attack==sweep then
        if t>=SWEEP_START and t-dt<SWEEP_END then
            self:DamagePlayer(target,sweep.range-CAPSULE,sweep.cosine,false)
        end
        return
    end
    if not self.fault.active then return end
    if t>=IMPACT and not self.impacted then
        self.impacted=true
        self:EmitEvent('stagger_land'); self:EmitEvent('camera_shake')
    end
    self.fault:Step(self,t,dt,target)
end

function Colossus:DamageScale(info,part)
    if (info.kind=='arrow' or info.kind=='crystal') and part.spec.material=='armor' then return .55 end
    return 1
end

function Colossus:UpdatePose()
    Base.UpdatePose(self)
    if self.attack==slam and self.state==S.TELEGRAPH then
        -- The actor owns a full-size, ground-conforming marker for this attack.
        self.warning.kind='fault_strip'
        self.fault:Brush(self.warning.progress)
    end
end

function Colossus:SetState(state)
    if self.fault and self.fault.active and state~=S.ATTACK and state~=S.TELEGRAPH then
        self:ClearExtras()
    end
    local changed=Base.SetState(self,state)
    if changed and state==S.TELEGRAPH and self.attack==slam then
        self.directionLocked=true
        self.fault:Lock(self)
    end
    return changed
end

function Colossus:ClearExtras()
    self.impacted=false
    if self.fault then self.fault:Clear() end
    if self.particles then self.particles:ClearOwner(self) end
    self.warning.visible=false
    if self.dead then self.poseY,self.posePitch,self.poseRoll=0,0,0 end
end

function Colossus:Destroy()
    Base.Destroy(self)
    if self.fault then self.fault:Destroy();self.fault=nil end
end

function Colossus:SetActive(active)
    if not active and not self.dead and (self.state==S.TELEGRAPH or self.state==S.ATTACK) then
        self:SetState(S.IDLE)
    end
    Base.SetActive(self,active)
end

return Colossus
