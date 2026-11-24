local Base = require('combat.enemies.EnemyBase')
local Optics=require('combat.enemies.actors.RuinConstructFX')
local Construct = setmetatable({}, {__index=Base})
Construct.__index = Construct

local bolt = {name='crystal_bolt', telegraph=.68, duration=.18, recover=1.0,
    range=12, warning='line', damage=9, poise=6}
local beam = {name='locked_beam', telegraph=1.20, duration=.56, recover=2.30,
    range=13, warning='line', damage=15, poise=12}
local LOCK_TIME, BOLT_SPEED = .55, 12
local function clamp(v) return math.max(0, math.min(1, v)) end

local function aperture(e)
    if not e.venting or e.state~=Base.State.RECOVER then return 0 end
    return math.min(clamp(e.stateTime/.18),clamp((beam.recover-e.stateTime)/.30))
end

local function posePart(enemy, id, p)
    local arm = id=='arm_r' or id=='arm_l'
    local plate=id=='plate_r' or id=='plate_l'
    local side = (id=='arm_r' or id=='satellite_r' or id=='plate_r') and 1 or -1
    if enemy.dead then
        local time = enemy.deathTime
        local disconnect = clamp(time/.18)
        local fall = clamp((time-.10)/.68)^2
        local settle = clamp((time-.78)/.32)
        if id=='core' or id=='neck' then
            p.z = -.22*disconnect
            p.sx,p.sy,p.sz = 1-.95*disconnect,1-.95*disconnect,1-.95*disconnect
        elseif plate then
            p.x,p.y,p.roll=side*.34*fall,-.70*fall,side*30*fall
        elseif arm then
            p.y,p.x,p.roll = -.77*fall+.04*math.sin(settle*math.pi),side*.16*fall,side*(18*fall-4*settle)
        elseif id=='crown' then
            p.y,p.roll,p.yaw = -.64*fall,-19*fall+4*settle,22*fall
        elseif id=='satellite_l' or id=='satellite_r' then
            p.y,p.roll = -.8*fall,side*33*fall
        else
            p.y,p.pitch = -.14*fall,5*fall
        end
        return
    end

    local t = enemy.poseAge
    local moving = enemy.state==Base.State.CHASE or enemy.state==Base.State.PATROL
    local cycle = moving and 6*t or 2.4*t
    p.y = .032*math.sin(cycle)
    local charge, kick = 0, 0
    if enemy.state==Base.State.TELEGRAPH then charge=clamp(enemy.stateTime/enemy.attack.telegraph)
    elseif enemy.state==Base.State.ATTACK then charge,kick=1,1-clamp(enemy.stateTime/enemy.attack.duration)
    elseif enemy.state==Base.State.RECOVER then charge=1-clamp(enemy.stateTime/.45) end
    local both = enemy.attack==beam
    if plate then
        p.x=side*.52*aperture(enemy)
    elseif arm then
        local aim = (both or side==1) and charge or 0
        p.pitch = (moving and 13 or 4)*math.sin(cycle+side*.9)*(1-aim)-83*aim
        p.x = both and -side*.53*aim or 0
        p.y = p.y+.05*aim
        p.z = .10*aim
        if both or side==1 then p.z=p.z-.16*kick end
    elseif id=='core' then
        local recoil = 1-clamp(enemy.reaction.recoilAge/.16)
        p.z = .15*aperture(enemy)-.17*recoil-.08*kick
        p.yaw = 6*math.sin(2*t)*(1-charge)
    elseif id=='crown' then
        p.y,p.yaw = p.y+.06*charge,12*math.sin(t)+24*charge
    elseif id=='satellite_r' or id=='satellite_l' then
        p.y,p.roll = p.y+.065*math.sin(cycle+.8*side)+.09*charge,side*(5+14*charge)
    end
end

Construct.Config = {kind='ruin_construct', name='遗迹构装体', enemy='sentry', model='RuinConstruct',
    hp=58,poise=100,radius=.62,height=2.4,speed=2.1,aggro=14,leash=30,attackDistance=11,
    ranged=true,voxelSize=.08,sculpt={},defaultPart='torso',posePart=posePart,
    parts={{id='torso',material='stone',x=0,y=1.44,z=-.13,radius=.35},
        {id='plate_l',material='armor',x=-.16,y=1.44,z=.37,radius=.235},
        {id='plate_r',material='armor',x=.16,y=1.44,z=.37,radius=.235},
        {id='core',material='core',x=0,y=1.44,z=.16,radius=.21,weak=true,weakMultiplier=2.4},
        {id='arm_l',material='stone',x=-.80,y=1.12,z=0,radius=.22,pivot={-.80,1.44,0}},
        {id='arm_r',material='stone',x=.80,y=1.12,z=0,radius=.22,pivot={.80,1.44,0}},
        {id='satellite_l',material='stone',x=-.88,y=1.96,z=0,radius=.13},
        {id='satellite_r',material='stone',x=.88,y=1.96,z=0,radius=.13},
        {id='lower_body',material='stone',x=0,y=.66,z=0,radius=.21},
        {id='neck',material='core',x=0,y=2.00,z=0,radius=.10},
        {id='crown',material='stone',x=0,y=2.28,z=.30,radius=.11,pivot={0,2.28,.04}}},attacks={bolt,beam}}

-- The visible octahedron and beam are allocated once, facing local +Z.
function Construct:PartEnabled(p)
    return p.id~='core' or aperture(self)>0
end

function Construct:DamageScale(info,part)
    if part.spec.id=='plate_l' or part.spec.id=='plate_r' then return .35 end
    if info.kind=='sword' and aperture(self)==0 and info.dir and info.dir.x*self.fx+info.dir.z*self.fz<-.5 then return .35 end
    return 1
end

local function rotate(x,y,z,pitch,yaw,roll)
    local p,yw,r=math.rad(pitch),math.rad(yaw),math.rad(roll)
    x,y=x*math.cos(r)-y*math.sin(r),x*math.sin(r)+y*math.cos(r)
    y,z=y*math.cos(p)-z*math.sin(p),y*math.sin(p)+z*math.cos(p)
    return x*math.cos(yw)+z*math.sin(yw),y,z*math.cos(yw)-x*math.sin(yw)
end

-- Apply the same local translation and body recoil as EnemyModelVisual. The
-- query runs before render too, so it cannot read last frame's node matrices.
function Construct:SyncShapes()
    Base.SyncShapes(self)
    local reaction=self.reaction
    local k=1-clamp(reaction.recoilAge/.12)
    local pitch=math.rad((self.posePitch or 0)+reaction.bodyPitch*k)
    local yaw=math.rad(reaction.bodyYaw*k)
    local roll=math.rad(self.poseRoll)
    self.queryPose=self.queryPose or {}
    local pose=self.queryPose
    for _,h in ipairs(self.hurtShapes) do
        local spec=self.parts[h.id].spec
        pose.x,pose.y,pose.z=0,0,0
        pose.pitch,pose.yaw,pose.roll=0,0,0
        posePart(self,h.id,pose)
        local x,y,z=spec.x,spec.y,spec.z
        if spec.pivot then
            local q=spec.pivot
            x,y,z=rotate(x-q[1],y-q[2],z-q[3],pose.pitch,pose.yaw,pose.roll)
            x,y,z=x+q[1],y+q[2],z+q[3]
        end
        x,y,z=x+pose.x,y+pose.y,z+pose.z
        x,y=x*math.cos(roll)-y*math.sin(roll),x*math.sin(roll)+y*math.cos(roll)
        y,z=y*math.cos(pitch)-z*math.sin(pitch),y*math.sin(pitch)+z*math.cos(pitch)
        x,z=x*math.cos(yaw)+z*math.sin(yaw),z*math.cos(yaw)-x*math.sin(yaw)
        x=x+self.posePivot*math.sin(roll)
        y=y+self.poseY+self.posePivot*(1-math.cos(roll))
        h.center=Vector3(self.position.x+x*self.fz+z*self.fx,self.position.y+y,self.position.z-x*self.fx+z*self.fz)
    end
end

local function crystal(scene, material)
    local node=scene:CreateChild('construct_bolt')
    local mesh=node:CreateComponent('CustomGeometry')
    mesh:BeginGeometry(0,TRIANGLE_LIST)
    local rim={Vector3(.5,0,-.15),Vector3(0,.5,-.15),Vector3(-.5,0,-.15),Vector3(0,-.5,-.15)}
    for i=1,4 do
        local a,b=rim[i],rim[i%4+1]
        mesh:DefineVertex(a); mesh:DefineVertex(Vector3(0,0,.5)); mesh:DefineVertex(b)
        mesh:DefineVertex(b); mesh:DefineVertex(Vector3(0,0,-.5)); mesh:DefineVertex(a)
    end
    mesh:Commit()
    mesh:SetMaterial(material)
    node.enabled=false
    return node
end

local function unlit(color)
    local material=Material:new()
    material:SetTechnique(0,cache:GetResource('Technique','Techniques/NoTextureUnlit.xml'))
    material:SetShaderParameter('MatDiffColor',Variant(color))
    return material
end

function Construct.New(scene,world,terrain,combat,position,id)
    local self=setmetatable(Base.Create(scene,world,terrain,combat,Construct.Config,position,id),Construct)
    if scene then
        self.crystalMaterial=unlit(Color(.35,1,.94,1))
        self.crystalMaterial:SetCullMode(CULL_NONE)
        self.boltNode=crystal(scene,self.crystalMaterial)
        self.optics=Optics.New(scene)
    end
    self:SyncShapes()
    return self
end

local function unobstructed(self, origin, direction, distance)
    if self.world and distance>0 then
        local hit=self.world:RaycastSingle(Ray(origin,direction),distance)
        if hit.hit then return math.max(0,math.min(distance,hit.distance)),hit end
    end
    return distance
end

local function drawRay(node,origin,direction,length,width)
    if not node then return end
    node.enabled=length>.001
    if not node.enabled then return end
    local mid=origin+direction*(length*.5)
    node.position=mid
    node:LookAt(mid+direction)
    node.scale=Vector3(width,width,length)
end

-- Closest horizontal point on the finite segment, then intersect the upright
-- player body at that height. Both attacks use exactly the visible segment.
local function contacts(self,target,origin,dir,length,radius)
    local dx,dz=target.x-origin.x,target.z-origin.z
    local lo,hi=0,length
    local bottom,top=target.y-radius,target.y+1.6+radius
    if math.abs(dir.y)>.00001 then
        local a,b=(bottom-origin.y)/dir.y,(top-origin.y)/dir.y
        lo,hi=math.max(lo,math.min(a,b)),math.min(hi,math.max(a,b))
        if hi<lo then return false end
    elseif origin.y<bottom or origin.y>top then return false end
    local horizontal=dir.x*dir.x+dir.z*dir.z
    local along=horizontal>1e-8 and math.max(lo,math.min(hi,(dx*dir.x+dz*dir.z)/horizontal)) or lo
    if (dx-along*dir.x)^2+(dz-along*dir.z)^2>(.32+radius)^2 then return false end
    -- A capsule overlapping the clipped endpoint still cannot take damage
    -- through a wall. Only candidate hits need this second ray.
    local delta=Vector3(dx,along*dir.y,dz)
    local distance=math.sqrt(dx*dx+delta.y*delta.y+dz*dz)
    return distance<.001 or unobstructed(self,origin,delta*(1/distance),distance)>=distance-.001
end

function Construct:EmitAttackCue(phase)
    if phase=='danger' and self.attack==bolt then
        self.boltAim=Vector3(self.aimPoint.x,self.aimPoint.y+.85,self.aimPoint.z)
    end
    Base.EmitAttackCue(self,phase)
end

local function impact(self,attack,origin,direction)
    local info=self.damageInfo
    info.dmg,info.poise,info.pos,info.dir=attack.damage,attack.poise,origin,direction
    if self.combat.DamagePlayer then self.combat.DamagePlayer(info) end
end

-- Clip the centre and the outer envelope before exposing the beam to either
-- rendering or gameplay. Also check the run from the chest to the emitter.
local function beamReach(self,source,dir,distance)
    local result,wall=unobstructed(self,source,dir,distance)
    local r=Optics.radius
    for i=0,7 do
        local a=i*math.pi/4
        local dx,dy=r*math.cos(a),r*math.sin(a)
        local nextLength,hit=unobstructed(self,source+Vector3(dir.z*dx,dy,-dir.x*dx),dir,result)
        if hit and (not wall or nextLength<result) then wall=hit end
        result=nextLength
    end
    return result,wall
end

function Construct:DrawBeam(fire,progress)
    if self.optics then
        self.optics:Draw(self.beamOrigin,self.beamDir,self.beamLength,self.poseAge,progress,self.directionLocked,fire,self.beamWall,self.stateTime/beam.duration)
    end
end

function Construct:TraceBeam()
    local dir=self.beamDir
    local source=self.beamOrigin-dir*.58
    local reach,wall=beamReach(self,source,dir,beam.range+.58)
    self.beamLength,self.beamWall=math.max(0,reach-.58),wall
end

function Construct:BeginAttack()
    if self.attack==beam then
        if self.beamOrigin then
            self:TraceBeam()
            self.emitted=self.beamLength>.01
            self:DrawBeam(true,1)
        end
        return
    end
    local offset=Vector3(.80*self.fz+.62*self.fx,0,-.80*self.fx+.62*self.fz)
    local source=self.position+Vector3(0,1.38,0)
    local reach=math.sqrt(.80^2+.62^2)
    if unobstructed(self,source,offset*(1/reach),reach)<reach then return end
    local pos=source+offset
    local aim=(self.boltAim or self.aimPoint+Vector3(0,.85,0))-pos
    local length=math.sqrt(aim.x^2+aim.y^2+aim.z^2)
    if length<.001 then return end
    self.boltPos,self.boltDir,self.boltLeft=pos,aim*(1/length),bolt.range
    drawRay(self.boltNode,pos,self.boltDir,.24,.16)
end

function Construct:TickExtras(realDt,target,poseDt)
    if self.state==Base.State.TELEGRAPH and self.attack==beam then
        if not self.directionLocked then
            self:Face(target)
            self.beamDir=Vector3(self.fx,0,self.fz)
            self.beamOrigin=self.position+Vector3(0,1.40,0)+self.beamDir*.58
            if self.stateTime+poseDt>=LOCK_TIME then
                self.directionLocked=true
                self:EmitAttackCue('danger')
            end
        end
        self:TraceBeam()
        self:DrawBeam(false,clamp((self.stateTime+poseDt)/beam.telegraph))
    end
    if self.optics and self.venting then
        local opening=aperture(self)
        local dir=Vector3(self.fx,0,self.fz)
        self.optics:Vent(self.position+Vector3(0,1.44+self.poseY,0)+dir*(.48+.15*opening),dir,
            opening,self.stateTime)
    end
    if not self.boltPos then return end
    local travel=math.min(self.boltLeft,BOLT_SPEED*realDt)
    if travel<=0 then return end
    local clear=unobstructed(self,self.boltPos,self.boltDir,travel)
    local hit=clear>0 and contacts(self,target,self.boltPos,self.boltDir,clear,.08)
    if hit or clear<travel or travel>=self.boltLeft then
        local pos,dir=self.boltPos,self.boltDir
        self.boltPos=nil
        if self.boltNode then self.boltNode.enabled=false end
        if hit then impact(self,bolt,pos,dir) end
        return
    end
    self.boltPos=self.boltPos+self.boltDir*travel
    self.boltLeft=self.boltLeft-travel
    drawRay(self.boltNode,self.boltPos,self.boltDir,.24,.16)
end

-- A finite, flat-ended horizontal cylinder against the character capsule.
local function beamContact(self,target)
    local origin,dir=self.beamOrigin,self.beamDir
    local dx,dz=target.x-origin.x,target.z-origin.z
    local along=dx*dir.x+dz*dir.z
    local endGap=math.max(0,-along,along-self.beamLength)
    local axisY=math.max(target.y+.32,math.min(target.y+1.65-.32,origin.y))
    local lateral=dx*dir.z-dz*dir.x
    local radialGap=math.max(0,math.sqrt(lateral^2+(axisY-origin.y)^2)-Optics.radius)
    if endGap^2+radialGap^2>.32^2 then return false end
    local delta=Vector3(dx,axisY-origin.y,dz)
    local d=math.sqrt(dx^2+delta.y^2+dz^2)
    return d<.001 or unobstructed(self,origin,delta*(1/d),d)>=d-.001
end

function Construct:AttackStep(_,target)
    if self.attack~=beam or not self.beamOrigin then return end
    self:TraceBeam()
    self.emitted=self.emitted or self.beamLength>.01
    self:DrawBeam(true,1)
    if self.attackHit then return end
    if self.beamLength>0 and beamContact(self,target) then
        self.attackHit=true
        impact(self,beam,self.beamOrigin,self.beamDir)
    end
end

function Construct:FinishAttack()
    local vent=self.attack==beam and self.emitted and self.state==Base.State.ATTACK
    self:SetState(Base.State.RECOVER)
    self.venting=vent
end

function Construct:SetState(state)
    if state~=Base.State.ATTACK then self.venting,self.emitted=false,false end
    if state~=Base.State.ATTACK and state~=Base.State.TELEGRAPH then
        self.beamOrigin,self.beamWall=nil,nil
        if self.optics then self.optics:Hide() end
    end
    if state==Base.State.STAGGER then self:ClearExtras() end
    local changed=Base.SetState(self,state)
    if changed and self.attack==beam and state==Base.State.TELEGRAPH then self.warning.visible=false end
    return changed
end

function Construct:ClearExtras()
    self.boltPos,self.beamOrigin,self.boltAim,self.beamWall=nil,nil,nil,nil
    self.venting,self.emitted=false,false
    if self.boltNode then self.boltNode.enabled=false end
    if self.optics then self.optics:Hide() end
end

function Construct:SetActive(active)
    if not active and not self.dead then self:SetState(Base.State.IDLE) end
    Base.SetActive(self,active)
end

function Construct:Destroy()
    Base.Destroy(self)
    if self.boltNode then self.boltNode:Remove(); self.boltNode=nil end
    if self.optics then self.optics:Destroy(); self.optics=nil end
    self.crystalMaterial=nil
end

return Construct
