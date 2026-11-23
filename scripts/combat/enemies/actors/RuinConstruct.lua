local Base = require('combat.enemies.EnemyBase')
local Construct = setmetatable({}, {__index=Base})
Construct.__index = Construct

local bolt = {name='crystal_bolt', telegraph=.68, duration=.18, recover=1.0,
    range=12, warning='line', damage=9, poise=6}
local beam = {name='locked_beam', telegraph=1.05, duration=.16, recover=1.18,
    range=13, warning='line', damage=15, poise=12}
local LOCK_TIME, BOLT_SPEED = .55, 12
local function clamp(v) return math.max(0, math.min(1, v)) end

local function posePart(enemy, id, p)
    local arm = id=='arm_r' or id=='arm_l'
    local side = (id=='arm_r' or id=='satellite_r') and 1 or -1
    if enemy.dead then
        local time = enemy.deathTime
        local disconnect = clamp(time/.18)
        local fall = clamp((time-.10)/.68)^2
        local settle = clamp((time-.78)/.32)
        if id=='core' or id=='neck' then
            p.z = -.22*disconnect
            p.sx,p.sy,p.sz = 1-.95*disconnect,1-.95*disconnect,1-.95*disconnect
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
    if arm then
        local aim = (both or side==1) and charge or 0
        p.pitch = (moving and 13 or 4)*math.sin(cycle+side*.9)*(1-aim)-83*aim
        p.x = both and -side*.53*aim or 0
        p.y = p.y+.05*aim
        p.z = .10*aim
        if both or side==1 then p.z=p.z-.16*kick end
    elseif id=='core' then
        local recoil = 1-clamp(enemy.reaction.recoilAge/.16)
        p.z = .065*charge-.17*recoil-.08*kick
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
    parts={{id='torso',material='stone',x=0,y=1.44,z=0,radius=.58,armor=0},
        {id='core',material='core',x=0,y=1.44,z=.28,radius=.24,armor=0}},attacks={bolt,beam}}

-- The visible octahedron and beam are allocated once, facing local +Z.
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
        self.lockMaterial=unlit(Color(1,.52,.18,1))
        self.boltNode=crystal(scene,self.crystalMaterial)
        self.beamNode=scene:CreateChild('construct_beam')
        self.beamMesh=self.beamNode:CreateComponent('StaticModel')
        self.beamMesh:SetModel(cache:GetResource('Model','Models/Box.mdl'))
        self.beamMesh:SetMaterial(self.lockMaterial)
        self.beamNode.enabled=false
    end
    return self
end

local function unobstructed(self, origin, direction, distance)
    if self.world and distance>0 then
        local hit=self.world:RaycastSingle(Ray(origin,direction),distance)
        if hit.hit then return math.max(0,math.min(distance,hit.distance)) end
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

function Construct:LockBeam()
    self.beamDir=Vector3(self.fx,0,self.fz)
    local source=self.position+Vector3(0,1.33,0)
    if unobstructed(self,source,self.beamDir,.40)<.40 then return end
    self.beamOrigin=source+self.beamDir*.40
    self.beamLength=unobstructed(self,self.beamOrigin,self.beamDir,beam.range)
    if self.beamMesh then self.beamMesh:SetMaterial(self.lockMaterial) end
    drawRay(self.beamNode,self.beamOrigin,self.beamDir,self.beamLength,.055)
end

function Construct:BeginAttack()
    if self.attack==beam then
        if not self.beamOrigin then return end
        self.beamLength=unobstructed(self,self.beamOrigin,self.beamDir,self.beamLength)
        if self.beamMesh then self.beamMesh:SetMaterial(self.crystalMaterial) end
        drawRay(self.beamNode,self.beamOrigin,self.beamDir,self.beamLength,.20)
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
    if self.state==Base.State.TELEGRAPH and self.attack==beam and not self.directionLocked
        and self.stateTime+poseDt>=LOCK_TIME then
        self:Face(target)
        self.directionLocked=true
        self:LockBeam()
        self.warning.visible=false -- the fixed 3D line takes over from the ground marker
        self:EmitAttackCue('danger')
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

function Construct:AttackStep(_,target)
    if self.attack~=beam or not self.beamOrigin or self.attackHit then return end
    if self.beamLength>0 and contacts(self,target,self.beamOrigin,self.beamDir,self.beamLength,.10) then
        self.attackHit=true
        impact(self,beam,self.beamOrigin,self.beamDir)
    end
end

function Construct:SetState(state)
    if state~=Base.State.TELEGRAPH and state~=Base.State.ATTACK then
        self.beamOrigin=nil
        if self.beamNode then self.beamNode.enabled=false end
    end
    return Base.SetState(self,state)
end

function Construct:ClearExtras()
    self.boltPos,self.beamOrigin,self.boltAim=nil,nil,nil
    if self.boltNode then self.boltNode.enabled=false end
    if self.beamNode then self.beamNode.enabled=false end
end

function Construct:SetActive(active)
    if not active and not self.dead then self:SetState(Base.State.IDLE) end
    Base.SetActive(self,active)
end

function Construct:Destroy()
    Base.Destroy(self)
    if self.boltNode then self.boltNode:Remove(); self.boltNode=nil end
    if self.beamNode then self.beamNode:Remove(); self.beamNode=nil; self.beamMesh=nil end
    self.crystalMaterial,self.lockMaterial=nil,nil
end

return Construct
