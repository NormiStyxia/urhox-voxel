local Base = require('combat.enemies.EnemyBase')
local Silk = require('combat.enemies.actors.NestWeaverSilk')
local Weaver = setmetatable({}, {__index=Base})
Weaver.__index = Weaver
local S = Base.State
local min, max, sin = math.min, math.max, math.sin
local hook = {name='hook_scissor', warning='fan', telegraph=.56, duration=.42, recover=.62,
    range=1.85, hitRange=1.02, damage=9, poise=8, cosine=.5, jumpable=true}
local silk = {name='silk_cast', warning='line', telegraph=.92, duration=.62, recover=.86,
    range=7.2, damage=12, poise=9}
local SILK_SPEED, SILK_RADIUS = 12, .36 -- Includes the player's horizontal radius.
local HOVER = 1.43
local sideOf = {wing_r=1,wing_l=-1,leg_front_r=1,leg_front_l=-1,leg_middle_r=1,leg_middle_l=-1,
    leg_rear_r=1,leg_rear_l=-1,shell_r=1,shell_l=-1,nest_r=1,nest_l=-1,antenna_r=1,antenna_l=-1}
local legPhase = {leg_front_r=0,leg_middle_l=0,leg_rear_r=0,leg_front_l=math.pi,
    leg_middle_r=math.pi,leg_rear_l=math.pi}
local function unit(t) return min(1,max(0,t)) end

local function posePart(e,id,p)
    local side = sideOf[id] or 0
    local wing = id=='wing_l' or id=='wing_r'
    local shell = id=='shell_r' or id=='shell_l'
    local nest = id=='nest_r' or id=='nest_l'
    local antenna = id=='antenna_r' or id=='antenna_l'
    local front = id=='leg_front_r' or id=='leg_front_l'
    local phase = legPhase[id]
    if e.dead then
        local fold = unit(e.deathTime/.28)
        local fall = unit((e.deathTime-.12)/.59)
        local drain = unit((e.deathTime-.20)/.90)
        if wing then
            p.roll,p.yaw=side*(12-40*fall),side*48*fall
        elseif phase then
            p.roll,p.yaw,p.y = -side*49*fold, -side*(front and 42 or 20)*fold, .09*fold
        elseif shell then
            p.roll,p.x,p.y = side*(42-71*fall),side*.19*fall,-.21*fall*fall
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
    if wing then
        local beat=(state==S.STAGGER and e.holdAge or e.poseAge)*26
        local stroke=sin(beat)
        p.roll=side*(12+40*stroke-12*hit)
        p.pitch=6*stroke
        p.yaw=side*(4+6*math.cos(beat))
    elseif phase then
        p.pitch,p.roll,p.y=24+4*sin(e.poseAge*5+phase),-side*13,.045
        if front and e.attack==hook and (wind+strike+release)>0 then
            local sweep = strike*unit(time/.115)
            local spread = wind+strike*(1-sweep)
            p.yaw = side*(34*spread-49*(sweep+release))
            p.pitch,p.z = -23*spread+8*(sweep+release), .055*(sweep+release)
            p.sz = 1+.23*(sweep+release)
        end
    elseif shell then
        local opening = e.attack==silk and (wind+strike*(1-.50*unit(time/silk.duration))+.5*release) or 0
        p.roll=side*(42+21*opening-16*hit)
        p.yaw=-side*(23+9*opening)
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
    voxelSize=.08,sculpt={},hp=40,poise=100,radius=.57,height=1.36,speed=2.65,aggro=10,leash=24,attackDistance=silk.range,
    defaultPart='body',parts={{id='body',x=0,y=.54,z=0,radius=.62,material='armor'},
        {id='head',x=0,y=.78,z=.51,radius=.31,material='soft'}},attacks={hook,silk}}

-- Hurt centres on the opened elytra and mobile wings are carried by exactly
-- the same part pivots as the rendered mesh (root-space metres).
for _,side in ipairs({-1,1}) do
    local suffix=side==1 and '_r' or '_l'
    local parts=Weaver.Config.parts
    parts[#parts+1]={id='wing'..suffix,material='soft',radius=.22,
        pivot={side*.28,.76,.12},offset={side*.90,0,-.41}}
    parts[#parts+1]={id='shell'..suffix,material='armor',radius=.32,
        pivot={side*.20,.896,.32},offset={side*.29,-.09,-.53}}
    parts[#parts+1]={id='nest'..suffix,material='soft',radius=.22,
        pivot={side*.624,.496,0},offset={side*.07,-.18,.06}}
end
function Weaver:SyncShapes()
    Base.SyncShapes(self)
    local pose=self.shapePose
    if not pose or self.dead or not self.active then return end
    for i,spec in ipairs(self.config.parts) do
        if spec.pivot then
            pose.x,pose.y,pose.z,pose.pitch,pose.yaw,pose.roll=0,0,0,0,0,0
            pose.sx,pose.sy,pose.sz=1,1,1
            posePart(self,spec.id,pose)
            local r,p,a=math.rad(pose.roll),math.rad(pose.pitch),math.rad(pose.yaw)
            local x,y,z=spec.offset[1]*pose.sx,spec.offset[2]*pose.sy,spec.offset[3]*pose.sz
            x,y=x*math.cos(r)-y*sin(r),x*sin(r)+y*math.cos(r)
            y,z=y*math.cos(p)-z*sin(p),y*sin(p)+z*math.cos(p)
            x,z=x*math.cos(a)+z*sin(a),z*math.cos(a)-x*sin(a)
            x,y,z=x+spec.pivot[1]+pose.x,y+spec.pivot[2]+pose.y,z+spec.pivot[3]+pose.z
            self.hurtShapes[i].center=Vector3(self.position.x+self.fz*x+self.fx*z,
                self.position.y+self.poseY+y,self.position.z-self.fx*x+self.fz*z)
        end
    end
end

function Weaver.New(scene,world,terrain,combat,position,id)
    local self=setmetatable(Base.Create(scene,world,terrain,combat,Weaver.Config,position,id),Weaver)
    self.nextSilk=0
    self.floorY=position.y
    self.position=Vector3(position.x,position.y+HOVER,position.z)
    self.shapePose={}
    self.thread={active=false,travel=0}
    if scene and world then
        local node=scene:CreateChild('nest_silk_'..self.id)
        node.enabled=false
        self.thread.node=node
        self.thread.endNode=scene:CreateChild('nest_fallen_silk_'..self.id)
        self.thread.endNode.enabled=false
    end
    self.thread.fxMesh=Silk.New(self.thread.node,self.thread.endNode)
    self:SyncShapes()
    if self.visual then self.visual.root.position=self.position end
    return self
end

function Weaver:SelectAttack()
    local target=self.lastTarget or self.aimPoint
    local near=(target.x-self.position.x)^2+(target.z-self.position.z)^2 <= hook.range^2
    self.attackIndex=near and 1 or 2
    self.attack=self.config.attacks[self.attackIndex]
end

-- Position is the flying root in world metres. Ground height is a separate
-- anchor for clearance, ground warnings and the landing after a lethal hit.
function Weaver:Move(dx,dz)
    local d=math.sqrt(dx*dx+dz*dz)
    if d<.00001 then return true end
    local x,z=self.position.x+dx,self.position.z+dz
    local ground=self:SafeHeight(x,z)
    self.moveBlocked,self.blockReason=false,''
    if not ground or ground-self.floorY>.70 then
        self.moveBlocked,self.blockReason=true,'edge'; return false
    end
    for _,obstacle in ipairs(self.obstacles) do
        if (x-obstacle.x)^2+(z-obstacle.z)^2<(self.radius+obstacle.radius)^2 then
            self.moveBlocked,self.blockReason=true,'pillar'; return false
        end
    end
    if self.world then
        local ray=Ray(Vector3(self.position.x,self.position.y+.52,self.position.z),Vector3(dx/d,0,dz/d))
        if self.world:RaycastSingle(ray,d+self.radius).hit then
            self.moveBlocked,self.blockReason=true,'wall'; return false
        end
    end
    self.position=Vector3(x,self.position.y+ground-self.floorY,z)
    self.floorY=ground
    return true
end

function Weaver:Chase(dt,target,distance)
    self:Face(target)
    if distance<=hook.range or (distance<=silk.range and self.poseAge>=self.nextSilk) then self:StartAttack()
    else
        local drift=.37*sin(self.poseAge*2.4)
        self:Move((self.fx+drift*self.fz)*self.config.speed*dt,(self.fz-drift*self.fx)*self.config.speed*dt)
    end
end

local function hoverHeight(e)
    return HOVER+.16*sin(e.poseAge*3.5)+.04*sin(e.poseAge*8)
end
local function smooth(t) t=unit(t);return t*t*(3-2*t) end
local function diveHeight(e,t)
    local top=e.castHeight or HOVER
    return top+(.21-top)*smooth(t/.18)
end
local function place(e,height)
    e.position=Vector3(e.position.x,e.floorY+height,e.position.z)
end

local function showThread(t,from,to,aim,progress)
    local length=max(.001,to-from)
    Silk.Update(t.fxMesh,aim,progress,length)
    if not t.node then return end
    local middle=(from+to)*.5
    t.node.enabled=true
    t.node.position=Vector3(t.x+t.fx*middle,t.y+t.fy*middle,t.z+t.fz*middle)
    t.node.rotation=Quaternion(-math.deg(math.asin(t.fy)),math.deg(math.atan(t.fx,t.fz)),0)
    t.node.scale=Vector3(SILK_RADIUS,SILK_RADIUS,length)
end
local function aimThread(e)
    local t=e.thread
    local target=e.lockedAim or e.aimPoint
    t.x,t.y,t.z=e.position.x+.69*e.fx,e.position.y+.77,e.position.z+.69*e.fz
    local dx,dy,dz=target.x-t.x,target.y+.76-t.y,target.z-t.z
    local d=math.sqrt(dx*dx+dy*dy+dz*dz)
    if d<.001 then t.fx,t.fy,t.fz=e.fx,0,e.fz else t.fx,t.fy,t.fz=dx/d,dy/d,dz/d end
    t.range=silk.range
    t.blocked=false
    if e.world then
        local wall=e.world:RaycastSingle(Ray(Vector3(t.x,t.y,t.z),Vector3(t.fx,t.fy,t.fz)),t.range)
        if wall.hit and wall.distance<=t.range then t.range=max(0,wall.distance); t.blocked=true end
    end
    if t.fy<-.001 then
        local ground=(t.y-e.floorY)/-t.fy
        if ground<=t.range then t.range=ground; t.blocked=true end
    end
end

function Weaver:UpdatePose()
    Base.UpdatePose(self)
    local h=hoverHeight(self)
    if self.state==S.TELEGRAPH then
        local u=smooth(self.stateTime/(self.attack.telegraph-.18))
        h=self.windHeight+(self.castHeight-self.windHeight)*u
    elseif self.state==S.ATTACK then
        h=self.attack==hook and diveHeight(self,self.stateTime) or self.castHeight
    elseif self.state==S.RECOVER and self.recoverHeight then
        h=self.recoverHeight+(h-self.recoverHeight)*smooth(self.stateTime/.58)
    elseif self.state==S.STAGGER then h=self.holdHeight or h end
    place(self,h)
    self.poseY=0
    if self.visual then
        for _,node in pairs(self.visual.warnings) do node.position=Vector3(0,.055-h,0) end
    end
    if self.state==S.TELEGRAPH and self.attack==silk then
        if self.directionLocked and not self.lockedAim then
            local aim=self.aimPoint
            self.lockedAim=Vector3(aim.x,aim.y,aim.z)
        end
        aimThread(self)
        local t=self.thread
        self.warning.radius=.69+t.range*math.sqrt(t.fx*t.fx+t.fz*t.fz)
        showThread(t,0,t.range,true,self.stateTime/silk.telegraph)
    end
end

function Weaver:BeginAttack()
    if self.attack~=silk then return end
    self.nextSilk=self.poseAge+3.4
    local t=self.thread
    aimThread(self)
    t.active,t.travel=true,0
    showThread(t,0,.05,false,0)
end
function Weaver:ClearExtras()
    self.thread.active=false
    self.thread.endAge=nil
    if self.thread.endNode then self.thread.endNode.enabled=false end
    Silk.Hide(self.thread.fxMesh)
    if self.thread.node then self.thread.node.enabled=false end
    if self.dead and not self.dropHeight then self.dropHeight=max(0,self.position.y-self.floorY) end
end
local function landFibres(e,distance)
    local t=e.thread
    t.endX,t.endY,t.endZ=t.x+t.fx*distance,t.y+t.fy*distance,t.z+t.fz*distance
    t.endAge=0
    Silk.EndFrame(t.fxMesh,0)
    if t.endNode then
        t.endNode.enabled=true
        t.endNode.position=Vector3(t.endX,t.endY,t.endZ)
        t.endNode.rotation=Quaternion(-math.deg(math.asin(t.fy)),math.deg(math.atan(t.fx,t.fz)),0)
        t.endNode.scale=Vector3(.33,.33,.30)
    end
end
function Weaver:TickExtras(_,_,dt)
    local t=self.thread
    if not t.endAge then return end
    t.endAge=t.endAge+dt
    local u=min(1,t.endAge/.32)
    Silk.EndFrame(t.fxMesh,u)
    if t.endNode then
        t.endNode.position=Vector3(t.endX,max(self.floorY+.04,t.endY-.28*u*u),t.endZ)
        t.endNode.enabled=u<1
    end
    if u>=1 then t.endAge=nil end
end
function Weaver:TickKnock(dt)
    if not self.dead then return Base.TickKnock(self,dt) end
    local age=self.deathTime+dt
    place(self,max(0,(self.dropHeight or HOVER)-5.8*age*age))
    return false
end

-- Entry of a swept thread into the player's vertical cylinder. Intersect the
-- horizontal circle interval with the vertical slab and the wall-clipped step.
local function silkContact(t,target,start,finish)
    local dx,dz=target.x-t.x,target.z-t.z
    local horiz=t.fx*t.fx+t.fz*t.fz
    if horiz>.00001 then
        local dot=dx*t.fx+dz*t.fz
        local disc=dot*dot-horiz*(dx*dx+dz*dz-SILK_RADIUS^2)
        if disc<0 then return end
        local r=math.sqrt(disc)
        start,finish=max(start,(dot-r)/horiz),min(finish,(dot+r)/horiz)
    elseif dx*dx+dz*dz>SILK_RADIUS^2 then return end
    local low,high=target.y-.04-t.y,target.y+1.64-t.y
    if math.abs(t.fy)>.00001 then
        local a,b=low/t.fy,high/t.fy
        start,finish=max(start,min(a,b)),min(finish,max(a,b))
    elseif low>0 or high<0 then return end
    if start<=finish then return start end
end
function Weaver:AttackStep(dt,target,knocked)
    if self.attack==hook then
        local time=self.stateTime
        local step=.81*(smooth(time/.23)-smooth((time-dt)/.23))
        if step>0 and not knocked then self:Move(self.fx*step,self.fz*step) end
        -- Contacts occur only near the bottom of the dive, at claw height.
        if time>=.14 and time-dt<=.27 then
            place(self,diveHeight(self,min(time,.27)))
            local tipY=self.position.y+.25
            if tipY>=target.y-.10 and tipY<=target.y+1.65 then
                self:DamagePlayer(target,hook.hitRange,hook.cosine,false)
            end
        end
        return
    end
    local t=self.thread
    if not t.active then return end
    local start=t.travel
    local finish=min(t.range,start+dt*SILK_SPEED)
    if self.world and finish>start then
        local origin=Vector3(t.x+start*t.fx,t.y+start*t.fy,t.z+start*t.fz)
        local wall=self.world:RaycastSingle(Ray(origin,Vector3(t.fx,t.fy,t.fz)),finish-start)
        if wall.hit then t.blocked=true; t.range=start+max(0,wall.distance); finish=min(finish,t.range) end
    end
    local contact=silkContact(t,target,start,finish)
    if contact and contact<t.range then
        self.attackHit=true
        self:ClearExtras()
        landFibres(self,contact)
        local info=self.damageInfo
        info.dmg,info.poise=silk.damage,silk.poise
        info.pos=Vector3(t.x+t.fx*contact,t.y+t.fy*contact,t.z+t.fz*contact)
        info.dir=Vector3(t.fx,t.fy,t.fz)
        if self.combat.DamagePlayer then self.combat.DamagePlayer(info) end
        return
    end
    t.travel=finish
    if finish>=t.range then
        self:ClearExtras()
        if t.blocked then landFibres(self,finish) end
    else showThread(t,max(0,finish-.94),finish,false,self.stateTime/silk.duration) end
end
function Weaver:SetState(state)
    local height=self.position.y-self.floorY
    if state==S.TELEGRAPH then
        self.lockedAim=nil
        self.windHeight,self.castHeight=height,HOVER+(self.attack==hook and .44 or .28)
    elseif state==S.STAGGER then self.holdHeight,self.holdAge=height,self.poseAge
    elseif state==S.RECOVER then self.recoverHeight=height end
    if state==S.STAGGER or self.state==S.TELEGRAPH or self.state==S.ATTACK then
        if not (state==S.RECOVER and self.thread.endAge) then self:ClearExtras() end
    end
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
    self.nextSilk,self.floorY=0,self.home.y
    return Base.Reset(self)
end

function Weaver:Destroy()
    Base.Destroy(self)
    if self.thread.node then self.thread.node:Remove(); self.thread.node=nil end
    if self.thread.endNode then self.thread.endNode:Remove(); self.thread.endNode=nil end
    self.thread.fxMesh.groups={}
end
return Weaver
