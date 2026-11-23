local Base = require('combat.enemies.EnemyBase')
local Weaver = setmetatable({}, {__index=Base})
Weaver.__index = Weaver
local S = Base.State
local min, max, sin = math.min, math.max, math.sin
local hook = {name='hook_scissor', warning='fan', telegraph=.56, duration=.29, recover=.62,
    range=1.40, hitRange=1.02, damage=9, poise=8, cosine=.5, jumpable=true}
local silk = {name='silk_cast', warning='line', telegraph=.92, duration=.62, recover=.86,
    range=7.2, damage=12, poise=9}
local SILK_SPEED, SILK_RADIUS = 12, .36 -- Includes the player's horizontal radius.
local sideOf = {leg_front_r=1,leg_front_l=-1,leg_middle_r=1,leg_middle_l=-1,
    leg_rear_r=1,leg_rear_l=-1,shell_r=1,shell_l=-1,nest_r=1,nest_l=-1,antenna_r=1,antenna_l=-1}
local legPhase = {leg_front_r=0,leg_middle_l=0,leg_rear_r=0,leg_front_l=math.pi,
    leg_middle_r=math.pi,leg_rear_l=math.pi}
local function unit(t) return min(1,max(0,t)) end

local function posePart(e,id,p)
    local side = sideOf[id] or 0
    local shell = id=='shell_r' or id=='shell_l'
    local nest = id=='nest_r' or id=='nest_l'
    local antenna = id=='antenna_r' or id=='antenna_l'
    local front = id=='leg_front_r' or id=='leg_front_l'
    local phase = legPhase[id]
    if e.dead then
        local fold = unit(e.deathTime/.28)
        local fall = unit((e.deathTime-.12)/.59)
        local drain = unit((e.deathTime-.20)/.90)
        if phase then
            p.roll,p.yaw,p.y = -side*49*fold, -side*(front and 42 or 20)*fold, .09*fold
        elseif shell then
            p.roll,p.x,p.y = -side*35*fall,side*.19*fall,-.21*fall*fall
        elseif nest then
            p.y,p.sy,p.sx,p.sz = -.10*drain,1-.69*drain,1-.32*drain,1-.32*drain
        elseif antenna then p.pitch = 53*fall
        elseif id=='head' then p.pitch,p.y = 17*fold,-.08*fall end
        return
    end
    local time,state=e.stateTime,e.state
    local wind,strike,release=0,0,0
    if state==S.TELEGRAPH then wind=unit(time/e.attack.telegraph)
    elseif state==S.ATTACK then strike=1
    elseif state==S.RECOVER then release=1-unit(time/e.attack.recover) end
    local hit = unit(1-e.reaction.recoilAge/.18)
    if phase then
        if state==S.CHASE or state==S.PATROL then
            local beat=e.poseAge*(state==S.CHASE and 12 or 5)+phase
            p.pitch,p.y=14*sin(beat),.065*max(0,math.cos(beat))
        elseif front and e.attack==hook then
            local sweep = strike*unit(time/.115)
            local spread = wind+strike*(1-sweep)
            p.yaw = side*(34*spread-49*(sweep+release))
            p.pitch,p.z = -23*spread+8*(sweep+release), .055*(sweep+release)
            p.sz = 1+.23*(sweep+release)
        end
    elseif shell then
        local opening = e.attack==silk and (wind+strike*(1-.50*unit(time/silk.duration))+.5*release) or 0
        p.roll=side*(47*opening-16*hit)
        p.y=.045*opening
    elseif nest then
        local charge=e.attack==silk and (wind+strike*(1-unit(time/.22))) or 0
        p.x,p.y=side*.095*charge,.07*charge
        p.sx,p.sy,p.sz=1+.18*charge,1+.18*charge,1+.18*charge
    elseif id=='fiber_collar' then
        p.roll=hit*(8*math.cos(e.reaction.recoilAge*85))
        p.z=-.04*hit
    elseif antenna then
        p.pitch=4*sin(e.poseAge*3+side*.35)-13*wind+8*release
    elseif id=='head' then
        p.y=.012*sin(e.poseAge*3)
        p.pitch=-9*wind+7*(strike+release)
    end
end

Weaver.Config={kind='nest_weaver',enemy='beetle',name='织巢虫',model='NestWeaver',posePart=posePart,
    voxelSize=.08,sculpt={},hp=40,poise=100,radius=.57,height=1.36,speed=2.0,aggro=10,leash=24,attackDistance=silk.range,
    defaultPart='body',parts={{id='body',x=0,y=.54,z=0,radius=.62,material='armor'},
        {id='head',x=0,y=.78,z=.51,radius=.31,material='soft'}},attacks={hook,silk}}

function Weaver.New(scene,world,terrain,combat,position,id)
    local self=setmetatable(Base.Create(scene,world,terrain,combat,Weaver.Config,position,id),Weaver)
    self.nextSilk=0
    self.thread={active=false,travel=0}
    if scene and world then
        local node=scene:CreateChild('nest_silk_'..self.id)
        local mesh=node:CreateComponent('StaticModel')
        local mat=Material:new()
        mat:SetTechnique(0,cache:GetResource('Technique','Techniques/NoTextureUnlit.xml'))
        mat:SetShaderParameter('MatDiffColor',Variant(Color(1,.81,.43,1)))
        mesh:SetModel(cache:GetResource('Model','Models/Box.mdl'))
        mesh:SetMaterial(mat)
        node.enabled=false
        self.thread.node=node
    end
    return self
end

function Weaver:SelectAttack()
    local target=self.lastTarget or self.aimPoint
    local near=(target.x-self.position.x)^2+(target.z-self.position.z)^2 <= hook.range^2
    self.attackIndex=near and 1 or 2
    self.attack=self.config.attacks[self.attackIndex]
end

function Weaver:Chase(dt,target,distance)
    self:Face(target)
    if distance<=hook.range or (distance<=silk.range and self.poseAge>=self.nextSilk) then self:StartAttack()
    else self:Move(self.fx*self.config.speed*dt,self.fz*self.config.speed*dt) end
end

function Weaver:BeginAttack()
    if self.attack~=silk then return end
    self.nextSilk=self.poseAge+3.4
    local t=self.thread
    t.active,t.travel=true,0
    t.x,t.y,t.z=self.position.x,self.position.y+.66,self.position.z
    t.fx,t.fz=self.fx,self.fz
    if t.node then
        t.node.position=Vector3(t.x,t.y,t.z)
        t.node.rotation=Quaternion(self.yaw,Vector3.UP)
        t.node.scale=Vector3(.075,.075,.08)
        t.node.enabled=true
    end
end

function Weaver:ClearExtras()
    self.thread.active=false
    if self.thread.node then self.thread.node.enabled=false end
end

function Weaver:AttackStep(dt,target,knocked)
    if self.attack==hook then
        -- Carry the shoulder into reach while the hook remains attached to it.
        local from=unit((self.stateTime-dt-.035)/.11)
        local step=.38*(unit((self.stateTime-.035)/.11)-from)
        if step>0 and not knocked then self:Move(self.fx*step,self.fz*step) end
        -- Test even if a coarse update crosses the whole contact window.
        if self.stateTime>=.08 and self.stateTime-dt<=.18 then
            self:DamagePlayer(target,hook.hitRange,hook.cosine,hook.jumpable)
        end
        return
    end
    local t=self.thread
    if not t.active then return end
    local start=t.travel
    local finish=min(silk.range,start+dt*SILK_SPEED)
    local blocked=false
    if self.world and finish>start then
        local origin=Vector3(t.x+start*t.fx,t.y,t.z+start*t.fz)
        local wall=self.world:RaycastSingle(Ray(origin,Vector3(t.fx,0,t.fz)),finish-start)
        if wall.hit then finish=start+min(finish-start,max(0,wall.distance)); blocked=true end
    end
    local dx,dz=target.x-t.x,target.z-t.z
    local along,across=dx*t.fx+dz*t.fz,dx*t.fz-dz*t.fx
    if math.abs(across)<=SILK_RADIUS and target.y<=t.y+.04 and target.y+1.6>=t.y-.04 then
        local reach=math.sqrt(SILK_RADIUS^2-across^2)
        local contact=max(start,along-reach)
        if along+reach>=start and contact<=finish and (not blocked or contact<finish) then
            self.attackHit=true
            self:ClearExtras()
            local info=self.damageInfo
            info.dmg,info.poise=silk.damage,silk.poise
            info.pos,info.dir=Vector3(t.x+t.fx*contact,t.y,t.z+t.fz*contact),Vector3(t.fx,0,t.fz)
            if self.combat.DamagePlayer then self.combat.DamagePlayer(info) end
            return
        end
    end
    t.travel=finish
    if blocked or finish>=silk.range then self:ClearExtras()
    elseif t.node then
        local length=min(.94,finish)
        local center=finish-length*.5
        t.node.position=Vector3(t.x+t.fx*center,t.y,t.z+t.fz*center)
        t.node.scale=Vector3(.075,.075,max(.08,length))
    end
end

function Weaver:SetState(state)
    if self.state==S.ATTACK and state~=S.ATTACK then self:ClearExtras() end
    return Base.SetState(self,state)
end

function Weaver:SetActive(active)
    Base.SetActive(self,active)
    if not active and not self.dead then
        self.aggro=false
        self.state,self.stateTime=S.IDLE,0
    end
end

function Weaver:Reset()
    self.nextSilk=0
    return Base.Reset(self)
end

function Weaver:Destroy()
    Base.Destroy(self)
    if self.thread.node then self.thread.node:Remove(); self.thread.node=nil end
end
return Weaver
