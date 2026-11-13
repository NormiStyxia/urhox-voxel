-- Kinematic combat actors. No physics bodies, voxel damage or TimeObject calls.
-- XZ: precomputed concentric footprint samples (<= .2m spacing), swept <= .1m.
-- Y: feet stay on permanent Terrain, not bridge rubble or VOID_Y.
-- Hurt spheres are independent of visuals; attacks check player feet/head height.
---@alias EnemyHurtShape {id:string,center:Vector3,radius:number,weak:boolean,enabled:boolean,material:string}
---@alias EnemyHitResult {hit:boolean,killed:boolean,partBroken:string?,part:string?,material:string?,broke:boolean,staggered:boolean,weak:boolean}

---@class EnemyBase
---@field node Node?
---@field world VoxelPhysicsWorld?
---@field scene Scene?
---@field position Vector3
---@field home Vector3
---@field hurtShapes EnemyHurtShape[]
---@field parts table<string, table>
---@field combat table
---@field terrain table
---@field config table
---@field visual table?
---@field phasePulse number
---@field rageTime number?
---@field rageActive boolean?
---@field onEvent fun(name:string, info:table)? Reused snapshot; copy before retaining.
---@field pendingSwingId string|number?
---@field particles EnemyParticles?
---@field stats table
---@field footprint table[]
---@field attackGroup table? Shared melee telegraph/attack budget, owned by Spawner.
---@field cueData VariantMap? Reused native event payload; absent in offline tests.
local Base = {}
Base.__index = Base
Base.State = { IDLE='IDLE', PATROL='PATROL', ALERT='ALERT', CHASE='CHASE',
    TELEGRAPH='TELEGRAPH', ATTACK='ATTACK', RECOVER='RECOVER', STAGGER='STAGGER', DEAD='DEAD' }
local Visual=require('combat.enemies.EnemyVisual')
local Particles=require('combat.enemies.EnemyParticles')
local S = Base.State
local sqrt, min, max = math.sqrt, math.min, math.max

---@param scene Scene?
---@param world VoxelPhysicsWorld?
---@param terrain table
---@param combat table?
---@param config table
---@param position Vector3
---@param id string?
---@return EnemyBase
function Base.Create(scene, world, terrain, combat, config, position, id)
    local self = setmetatable({}, Base)
    self:Init(scene, world, terrain, combat, config, position, id)
    return self
end

function Base:Init(scene, world, terrain, combat, config, position, id)
    self.scene, self.world, self.terrain = scene, world, terrain
    self.combat, self.config = combat or {}, config
    self.id, self.name = id or config.kind, config.name
    self.kind, self.boss = config.kind, config.boss or false
    self.position = Vector3(position.x, position.y, position.z)
    self.home = Vector3(position.x, position.y, position.z)
    self.hp, self.maxHP = config.hp, config.hp
    self.maxHp = self.maxHP -- HUD consumers commonly use this spelling.
    self.poise, self.maxPoise = 0, 100
    self.poiseQuiet,self.poiseProtection=0,0
    self.radius, self.yaw = config.radius, 0
    self.footprint=Base.MakeFootprint(self.radius)
    self.stats={activeCount=0,voxelCount=0,particleCount=0,surfaceFacesEstimate=0,drawSubmissionsEstimate=0,rebuildCpuMs=0}
    self.metrics=Visual.Measure(config)
    self.fx, self.fz = 0, 1
    self.state, self.stateTime, self.age = S.IDLE, 0, 0
    self.aggro, self.active, self.dead, self.defeated = false, true, false, false
    self.attackIndex, self.attackHit, self.attackTravel = 0, false, 0
    self.attackToken,self.directionLocked=false,false
    self.aimPoint=Vector3(position.x,position.y,position.z+1)
    self.staggerDuration, self.down, self.phase = 0, false, 1
    self.stumble=false
    self.phasePulse=0
    self.aggroClock, self.hitStop, self.poseY, self.posePitch = 0, 0, 0, 0
    self.poseRoll,self.posePivot=0,config.boss and .85 or .38
    self.reaction={part='',age=1,angle=0,shift=0,flash=0,dx=0,dy=0,dz=0}
    self.impact={pos=Vector3(0,0,0),dir=Vector3(0,0,1),normal=Vector3(0,0,-1),material='soft',tier='light',part='',weak=false,broke=false,kind='hit'}
    self.deathImpact={pos=Vector3(0,0,0),dir=Vector3(0,0,1),normal=Vector3(0,1,0),material='stone',tier='light',part='',kind='death'}
    self.deathBurst,self.deathFinished,self.staggerLanded=false,false,false
    self.presentationPending,self.deathPresentationReady=false,false
    self.pendingSwingId,self.pendingPart=nil,''
    self.presentedHits=0
    self.pendingDt, self.selected, self.deathTime = 0, false, 0
    self.moveBlocked, self.blockReason = false, ''
    self.obstacles, self.hurtShapes, self.parts = {}, {}, {}
    self.result = { hit=false, killed=false, partBroken=nil,part=nil,material=nil,broke=false,staggered=false,weak=false }
    self.damageInfo = { dmg=0, poise=0, kind='enemy', source=self.id,
        pos=Vector3(0,0,0), dir=Vector3(0,0,1) }
    self.attack = config.attacks[1]
    self.warning = { visible=false, progress=0, step=0, kind='ring', radius=0 }
    ---@type table
    self.cue={sequence=0,phase='',attack='',position=self.position,pos=self.position,duration=0,
        enemy=config.enemy or 'beast',enemyId=self.id,material='',tier='',part='',danger=false,magnitude=0,name=''}
    if scene and scene.SendEvent then self.cueData=VariantMap() end
    for _, p in ipairs(config.parts) do
        self.parts[p.id] = { armor=p.armor or 0, maxArmor=p.armor or 0, broken=false, spec=p }
        self.hurtShapes[#self.hurtShapes+1] = { id=p.id, center=Vector3(0,0,0),
            radius=p.radius, weak=p.weak or false, enabled=not p.hidden, material=p.material or 'stone' }
    end
    if scene and world then
        self.visual = Visual.New(scene, world, config)
        self.node = self.visual.root
    end
    self.particles=Particles.Acquire(scene,world,combat or self)
    self:SyncShapes()
end

function Base:SetCombat(combat) self.combat = combat or self.combat end

-- Initialization only. Rings cover the interior as well as the edge; no per-step tables.
function Base.MakeFootprint(radius)
    local points={{x=0,z=0}}
    local rings=math.ceil(radius/.2)
    for ring=1,rings do
        local r=radius*ring/rings
        local n=math.max(8,math.ceil(2*math.pi*r/.2))
        for i=1,n do
            local a=i*2*math.pi/n
            points[#points+1]={x=math.cos(a)*r,z=math.sin(a)*r}
        end
    end
    return points
end

---@return number?
function Base:SafeHeight(x, z)
    local t=self.terrain
    if not t.HasGround(x,z,max(2,self.radius+.25)) then return nil end
    local y=t.GroundHeight(x,z)
    if y==nil or y==t.VOID_Y then return nil end
    for _,offset in ipairs(self.footprint) do
        local px,pz=x+offset.x,z+offset.z
        if not t.HasGround(px,pz) then return nil end
        local py=t.GroundHeight(px,pz)
        if py==nil or py==t.VOID_Y or not t.IsSafeGround(px,py,pz) or math.abs(py-y)>.7 then return nil end
    end
    return y
end

-- Returns false at an edge/wall/pillar. Never teleports across a gap.
function Base:Move(dx, dz)
    self.moveBlocked, self.blockReason = false, ''
    local length = sqrt(dx*dx+dz*dz)
    if length<1e-6 then return true end
    local steps=math.ceil(length/.1)
    if steps>32 then self.moveBlocked,self.blockReason=true,'budget'; return false end
    if self:SafeHeight(self.position.x,self.position.z)==nil then
        self.moveBlocked,self.blockReason=true,'edge'; return false
    end
    if self.world then
        local ray=Ray(Vector3(self.position.x,self.position.y+.7,self.position.z),Vector3(dx/length,0,dz/length))
        local hit=self.world:RaycastSingle(ray,length+self.radius)
        if hit.hit then self.moveBlocked,self.blockReason=true,'wall'; return false end
    end
    for _=1,steps do
        local x,z=self.position.x+dx/steps,self.position.z+dz/steps
        local y=self:SafeHeight(x,z)
        if y==nil or math.abs(y-self.position.y)>.7 then
            self.moveBlocked,self.blockReason=true,'edge'; return false
        end
        for _,p in ipairs(self.obstacles) do
            if (x-p.x)^2+(z-p.z)^2 < (self.radius+p.radius)^2 then
                self.moveBlocked,self.blockReason=true,'pillar'; return false
            end
        end
        self.position=Vector3(x,y,z)
    end
    return true
end

function Base:Face(target)
    local dx,dz=target.x-self.position.x,target.z-self.position.z
    local len=sqrt(dx*dx+dz*dz)
    if len>.001 then
        self.fx,self.fz=dx/len,dz/len
        self.yaw=math.deg(math.atan(self.fx,self.fz))
    end
    return len
end

function Base:CanTelegraph()
    return not self.attackGroup or self.attackToken or self.attackGroup.count<self.attackGroup.limit
end
function Base:ReleaseAttackToken()
    if self.attackToken and self.attackGroup then self.attackGroup.count=max(0,self.attackGroup.count-1) end
    self.attackToken=false
end
function Base:StartAttack()
    if not self:CanTelegraph() then return false end
    self:SelectAttack()
    return self:SetState(S.TELEGRAPH)
end

-- Native event reserved for inhale/whoosh SFX. No audio assets or mandatory Combat API.
-- The pose, ground marker and this event all change at the same state boundary.
-- One synchronous event port. Native listeners should use Event; Phase retains
-- inhale/whoosh/stop compatibility. onEvent receives the SAME reused cue snapshot.
function Base:EmitEvent(name,phase)
    local cue=self.cue
    cue.sequence,cue.name,cue.phase=cue.sequence+1,name,phase or name
    cue.attack,cue.pos,cue.position=self.attack.name,self.position,self.position
    cue.duration=name=='enemy_windup' and self.attack.telegraph or (name=='camera_shake' and .12 or 0)
    cue.danger=phase=='danger'
    cue.magnitude=name=='camera_shake' and .025 or 0
    cue.material,cue.tier,cue.part=self.impact.material,self.impact.tier,self.impact.part
    if self.onEvent then self.onEvent(name,cue) end
    if self.cueData and self.scene then
        self.cueData['EnemyId']=self.id
        self.cueData['Enemy']=cue.enemy
        self.cueData['Attack']=cue.attack
        self.cueData['Phase']=cue.phase
        self.cueData['Event']=name
        self.cueData['Position']=cue.pos
        self.cueData['Duration']=cue.duration
        self.cueData['Danger']=Variant(cue.danger)
        self.cueData['Material']=Variant(cue.material)
        self.cueData['Tier']=Variant(cue.tier)
        self.cueData['Part']=Variant(cue.part)
        self.cueData['Magnitude']=Variant(cue.magnitude)
        self.scene:SendEvent('EnemyAttackCue',self.cueData)
    end
end
function Base:EmitAttackCue(phase)
    self:EmitEvent((phase=='inhale' or phase=='danger') and 'enemy_windup'
        or (phase=='whoosh' and 'attack_active' or 'attack_stop'),phase)
end
function Base:UpdatePose()
    self.poseRoll=0
    self.poseY=self.state==S.TELEGRAPH and (-.03-.09*self.warning.progress) or 0
    if self.state==S.ALERT then self.poseY=.08 end
    self.posePitch=self.stumble and 10 or 0
    if self.stumble then self.poseY=-.16 end
    if self.down then
        local t=self.stateTime
        local stand=self.staggerDuration-.4
        local fall=min(1,max(0,(t-.15)/.2))
        if t>=stand then fall=max(0,(self.staggerDuration-t)/.4) end
        self.poseRoll=75*fall
        self.posePitch=t<.15 and 8*t/.15 or 0
        if t>.35 and t<stand then self.poseRoll=75+2*math.sin((t-.35)*7) end
        self.poseY=.27*fall
    end
end
function Base:SetState(state)
    if self.dead then return false end
    if state==S.TELEGRAPH then
        if not self:CanTelegraph() then return false end
        if self.attackGroup and not self.attackToken then
            self.attackGroup.count=self.attackGroup.count+1; self.attackToken=true
        end
    elseif state~=S.ATTACK then self:ReleaseAttackToken() end
    local previous=self.state
    self.state,self.stateTime=state,0
    self.warning.visible=state==S.TELEGRAPH
    if state==S.ALERT then
        self.aggro,self.aggroClock=true,0
        if self.combat.OnEnemyAggro then self.combat.OnEnemyAggro(self.id) end
    elseif state==S.TELEGRAPH then
        self.attackHit,self.attackTravel=false,0
        self.warning.kind,self.warning.radius=self.attack.warning,self.attack.range
        self.warning.progress,self.warning.step=0,0
        self.directionLocked=false
        if self.lastTarget then self.aimPoint=self.lastTarget end
    end
    self:UpdatePose(); self:SyncShapes()
    if self.visual then self.visual:Update(self) end
    if state==S.TELEGRAPH then self:EmitAttackCue('inhale')
    elseif state==S.ATTACK then self:EmitAttackCue('whoosh'); self:BeginAttack()
    elseif previous==S.TELEGRAPH or previous==S.ATTACK then self:EmitAttackCue('stop') end
    return true
end

function Base:Stagger(seconds, down)
    if self.dead or (self.state==S.STAGGER and not self.stumble) then return false end
    self.stumble=false
    self.staggerDuration,self.down=seconds,down or false
    self.poise=0
    self.staggerLanded=false
    self:SetState(S.STAGGER)
    return true
end
function Base:Stumble(seconds)
    if self.dead or self.state==S.STAGGER then return false end
    self.staggerDuration,self.down,self.stumble=seconds,false,true
    self:SetState(S.STAGGER) -- armor consequence: do not erase/lock the independent poise meter
    return true
end

function Base:SelectAttack()
    self.attackIndex=self.attackIndex%#self.config.attacks+1
    self.attack=self.config.attacks[self.attackIndex]
end

function Base:BeginAttack() end
function Base:FinishAttack() self:SetState(S.RECOVER) end
function Base:AfterRecover() self:SetState(S.CHASE) end
function Base:OnBreak(_) end
function Base:OnDamaged() end
---@return number
function Base:DamageScale(_, _) return 1 end
function Base:TickExtras(_, _) end
function Base:TickPresentation(_, _) return false end
function Base:ClearExtras() end

function Base:Chase(dt, target, distance)
    self:Face(target)
    if distance<=self.config.attackDistance then
        self:StartAttack()
    else
        self:Move(self.fx*self.config.speed*dt,self.fz*self.config.speed*dt)
    end
end

-- Point/sector against player vertical capsule, plus wall occlusion.
function Base:CanDamage(target, range, cosine, jumpable)
    local dx,dz=target.x-self.position.x,target.z-self.position.z
    local d=sqrt(dx*dx+dz*dz)
    if d>range+.32 then return false end
    if jumpable and target.y>self.position.y+.65 then return false end
    if target.y>self.position.y+self.config.height or target.y+1.6<self.position.y then return false end
    if cosine and d>.001 and (dx*self.fx+dz*self.fz)/d<cosine then return false end
    if self.world and d>.01 then
        local hit=self.world:RaycastSingle(Ray(Vector3(self.position.x,self.position.y+.7,self.position.z),
            Vector3(dx/d,0,dz/d)),d)
        if hit.hit and hit.distance<d-.25 then return false end
    end
    return true
end

function Base:DamagePlayer(target, range, cosine, jumpable)
    if self.attackHit or not self:CanDamage(target,range,cosine,jumpable) then return false end
    self.attackHit=true
    local info=self.damageInfo
    info.dmg,info.poise=self.attack.damage,self.attack.poise or 8
    info.pos,info.dir=self.position,Vector3(self.fx,0,self.fz)
    if self.combat.DamagePlayer then self.combat.DamagePlayer(info) end
    return true
end

function Base:AttackStep(dt, target)
    local a=self.attack
    if a.travel then
        local step=min(a.travel-self.attackTravel,a.travel/a.duration*dt)
        self:Move(self.fx*step,self.fz*step)
        self.attackTravel=self.attackTravel+step
    end
    self:DamagePlayer(target,a.hitRange or a.range,a.cosine,a.jumpable)
end

---@return boolean
function Base:PartEnabled(spec)
    if spec.recoveryOnly then return self.state==S.RECOVER end
    return not spec.hidden or self.parts.back_armor.broken
end

function Base:SyncShapes()
    for i=1,#self.config.parts do
        local h=self.hurtShapes[i]
        local p=self.parts[h.id].spec
        local x,y,z=p.x or 0,p.y or 0,p.z or 0
        if self.poseRoll~=0 then
            local a=math.rad(self.poseRoll)
            local pivot=self.posePivot
            x,y=x*math.cos(a)-(y-pivot)*math.sin(a),pivot+x*math.sin(a)+(y-pivot)*math.cos(a)
        end
        h.center=Vector3(self.position.x+x*self.fz+z*self.fx,
            self.position.y+y+(self.config.hover or 0)+self.poseY,
            self.position.z-x*self.fx+z*self.fz)
        h.enabled=self.active and not self.dead and self:PartEnabled(p)
        h.material=p.material or 'stone'
        h.weak=(p.weak or false) and h.enabled
        h.radius=h.enabled and p.radius or 0
    end
end

function Base:GetHurtShapes() self:SyncShapes(); return self.hurtShapes end

function Base:Knockback(info, distance)
    local dir=info.dir
    if not dir then return end
    local n=sqrt(dir.x*dir.x+dir.z*dir.z)
    if n>.001 then self:Move(dir.x/n*distance,dir.z/n*distance) end
end

-- Capture actual contact before any physical knockback. Fallback is the selected
-- hurt sphere surface, never an arbitrary body-center burst. Caller vectors are copied.
function Base:PrepareImpact(info,part)
    local fx=self.impact
    local shape
    for _,h in ipairs(self.hurtShapes) do if h.id==part.spec.id then shape=h; break end end
    local dir=info.dir or Vector3.FORWARD
    local n=max(.001,sqrt(dir.x^2+dir.y^2+dir.z^2))
    fx.dir=Vector3(dir.x/n,dir.y/n,dir.z/n)
    local center=shape and shape.center or self.position
    local pos=info.pos or (center-fx.dir*part.spec.radius)
    fx.pos=Vector3(pos.x,pos.y,pos.z)
    local normal=info.normal or (fx.pos-center)
    n=sqrt(normal.x^2+normal.y^2+normal.z^2)
    fx.normal=n>.001 and Vector3(normal.x/n,normal.y/n,normal.z/n) or Vector3(-fx.dir.x,-fx.dir.y,-fx.dir.z)
    fx.material,fx.part=part.spec.material or 'stone',part.spec.id
    fx.tier=info.tier or (info.heavy and 'heavy' or (info.combo==3 and 'third' or 'light'))
    fx.weak,fx.broke,fx.kind=part.spec.weak or false,false,'hit'
    fx.swingId,fx.weapon=info.swingId,info.weapon or info.kind
end

-- Reset ONLY in the presentation consumer, never in a deferred settlement.
function Base:ReactToImpact()
    local fx,r=self.impact,self.reaction
    local part=self.parts[fx.part]
    if not part then return end -- deflecting a detached stone does not recoil its caster
    local heavy=fx.tier=='heavy' or fx.tier=='third'
    r.part=part.spec.bone or part.spec.id
    r.age,r.angle,r.shift,r.flash=0,heavy and 8 or 5,heavy and .05 or .025,heavy and .08 or .06
    r.dx,r.dy,r.dz=fx.dir.x*self.fz-fx.dir.z*self.fx,fx.dir.y,fx.dir.x*self.fx+fx.dir.z*self.fz
end

function Base:ConsumeHitPresentation()
    local fx=self.impact
    self.presentedHits=self.presentedHits+1
    self:ReactToImpact()
    if fx.killed then
        local d=self.deathImpact
        d.pos=Vector3(fx.pos.x,fx.pos.y,fx.pos.z)
        d.dir=Vector3(fx.dir.x,fx.dir.y,fx.dir.z)
        d.normal=Vector3(fx.normal.x,fx.normal.y,fx.normal.z)
        d.material,d.tier,d.part=fx.material,fx.tier,fx.part
        d.swingId,d.weapon,d.broke,d.staggered,d.killed,d.weak=fx.swingId,fx.weapon,fx.broke,fx.staggered,true,fx.weak
        self.deathPresentationReady=true
        if self.particles then self.particles:ClearOwner(self) end
    elseif self.particles then self.particles:Emit(self,fx) end
    if self.visual then self.visual:Update(self) end
end

-- One local token per successful settlement, not a scene-wide swing lock: a sweep
-- must present each target. The W2 contract consumes this token synchronously.
function Base:StageHitPresentation(info,result)
    local fx=self.impact
    fx.broke,fx.staggered,fx.killed=result.broke,result.staggered,result.killed
    self.pendingSwingId,self.pendingPart=info.swingId,result.part
    self.presentationPending=info.deferPresentation==true
    if not self.presentationPending then self:ConsumeHitPresentation() end
end

---@param event table Borrowed synchronous HitEvent; never retain its table or vectors.
---@return boolean consumed False for duplicates, unmatched events, or the legacy path.
function Base:OnHitEvent(event)
    if not self.presentationPending or not event then return false end
    if event.part~=self.pendingPart then return false end
    if self.pendingSwingId~=nil and event.swingId~=self.pendingSwingId then return false end
    self.presentationPending=false -- consume before any callback/visual work
    local fx=self.impact
    if event.pos then fx.pos=Vector3(event.pos.x,event.pos.y,event.pos.z) end
    if event.dir then fx.dir=Vector3(event.dir.x,event.dir.y,event.dir.z) end
    if event.normal then fx.normal=Vector3(event.normal.x,event.normal.y,event.normal.z) end
    fx.material,fx.tier,fx.part=event.material or fx.material,event.tier or fx.tier,event.part
    fx.swingId,fx.weapon=event.swingId,event.weapon
    fx.broke,fx.staggered,fx.killed,fx.weak=event.broke==true,event.staggered==true,event.killed==true,event.weak==true
    -- Preserve the settled deflection kind; unified events use kind='hit' for all.
    self:ConsumeHitPresentation()
    return true
end
function Base:ClearHitResult()
    local r=self.result
    r.hit,r.killed,r.partBroken=false,false,nil
    r.part,r.material,r.broke,r.staggered,r.weak=nil,nil,false,false,false
    return r
end

-- info/result tables are caller-owned / enemy-owned respectively; copy before retaining.
---@return EnemyHitResult
function Base:ApplyHit(info)
    local result=self:ClearHitResult()
    if self.dead or not self.active then return result end
    local part=self.parts[info.part or self.config.defaultPart]
    if not part or not self:PartEnabled(part.spec) then return result end
    local damage=max(0,info.dmg or 0)
    if damage==0 then return result end
    if not self.aggro then self:SetState(S.ALERT) end
    self:PrepareImpact(info,part)
    result.hit,result.part,result.material,result.weak=true,part.spec.id,self.impact.material,part.spec.weak or false
    local scaled=damage*self:DamageScale(info,part)
    if part.spec.weak then scaled=scaled*(part.spec.weakMultiplier or 1.6) end
    if self.down then scaled=scaled*1.5 end
    self.hp=max(0,self.hp-scaled)
    if not self.boss and info.kind=='sword' then self:Knockback(info,info.combo==3 and .55 or .1) end
    if part.maxArmor>0 and not part.broken then
        part.armor=max(0,part.armor-damage*max(0,info.armorBreak or 1))
        if part.armor==0 then
            part.broken=true; result.partBroken=part.spec.id; result.broke=true; self:OnBreak(part.spec.id)
        end
    end
    self:OnDamaged()
    if self.hp==0 then
        self:ReleaseAttackToken()
        self:EmitAttackCue('stop')
        self.dead,self.defeated,self.aggro=true,true,false
        self.state,self.stateTime,self.deathTime=S.DEAD,0,0
        self.deathBurst,self.deathFinished,self.deathPresentationReady=false,false,false
        self.warning.visible=false
        self:ClearExtras()
        result.killed=true
        if self.combat.OnEnemyDead then self.combat.OnEnemyDead(self) end
    elseif self.state~=S.STAGGER or self.stumble then
        local impact=max(0,info.poise or 0)
        if impact>0 and self.poiseProtection<=0 then
            self.poiseQuiet=0
            self.poise=self.poise+impact
            if self.poise>=self.maxPoise then
                if self.boss then self:Knockback(info,.6) end
                result.staggered=self:Stagger(self.boss and 3 or .8,self.boss)
            end
        end
        if not info.deferPresentation then
            self.hitStop=max(self.hitStop,result.partBroken and .1 or (info.heavy and .08 or .04))
        end
    end
    self:SyncShapes()
    self:StageHitPresentation(info,result)
    return result
end

function Base:Update(dt, playerPos)
    dt=max(0,min(dt,.2)) -- bounded catch-up; never skip a full telegraph on a hitch
    self.age=self.age+dt
    self.reaction.age=self.reaction.age+dt
    if self.particles then self.particles:UpdateOwner(self,dt) end
    if self.dead then
        local old=self.deathTime
        self.deathTime=self.deathTime+dt
        if self.deathPresentationReady and not self.deathBurst and self.deathTime+1e-8>=.25 then
            self.deathBurst=true
            if self.particles then
                self.particles:Emit(self,self.deathImpact)
                self.particles:UpdateOwner(self,max(0,self.deathTime-.25))
            end
            self:EmitEvent('die')
        end
        if not self.deathFinished and old<1.1 and self.deathTime+1e-8>=1.1 then
            self.deathFinished=true
            if self.particles then self.particles:ClearOwner(self) end
            if self.boss then self:EmitEvent('victory') end
        end
        if self.visual then self.visual:Update(self) end
        if self.visual and self.visual.removed then self.node=nil end
        return
    end
    if not self.active then return end
    -- Recovery/protection use real time, including animation hit-stop. Only poise
    -- damage resets this clock; HP/armor hits alone cannot keep the meter full.
    local oldQuiet=self.poiseQuiet
    self.poiseQuiet=self.poiseQuiet+dt
    self.poiseProtection=max(0,self.poiseProtection-dt)
    if self.state~=S.STAGGER or self.stumble then
        local recoveryTime=max(0,self.poiseQuiet-3)-max(0,oldQuiet-3)
        self.poise=max(0,self.poise-10*recoveryTime)
    end
    local target=playerPos or (self.combat.PlayerPos and self.combat.PlayerPos())
    if not target then return end
    self.lastTarget=target
    self:TickExtras(dt,target)
    if self:TickPresentation(dt,target) then
        self.hitStop=max(0,self.hitStop-dt)
        self:UpdatePose(); self:SyncShapes()
        if self.visual then self.visual:Update(self) end
        return
    end
    if self.hitStop>0 then
        local held=min(dt,self.hitStop)
        self.hitStop=max(0,self.hitStop-held)
        dt=dt-held
        if dt<=1e-8 then
            if self.visual then self.visual:Update(self) end
            return
        end
    end
    self.stateTime=self.stateTime+dt
    local distance=sqrt((target.x-self.position.x)^2+(target.z-self.position.z)^2)
    if self.aggro and distance>self.config.leash then
        self.aggro=false; self.down=false; self:ClearExtras(); self:SetState(S.PATROL)
    end
    if self.aggro then
        self.aggroClock=self.aggroClock+dt
        if self.aggroClock>=1 then
            self.aggroClock=0
            if self.combat.OnEnemyAggro then self.combat.OnEnemyAggro(self.id) end
        end
    end
    if self.down and not self.staggerLanded and self.stateTime+1e-8>=.35 then
        self.staggerLanded=true
        self:EmitEvent('stagger_land')
        if self.particles then
            local fx=self.impact
            fx.pos,fx.dir,fx.normal=self.position,Vector3.UP,Vector3.UP
            fx.kind,fx.broke,fx.weak='dust',false,false
            self.particles:Emit(self,fx)
        end
    end
    local state=self.state
    if state==S.IDLE or state==S.PATROL then
        if distance<=self.config.aggro and math.abs(target.y-self.position.y)<5 then
            self:Face(target); self:SetState(S.ALERT)
        elseif state==S.IDLE and self.stateTime>=1.2 then self:SetState(S.PATROL)
        elseif state==S.PATROL then
            local d=self:Face(self.home)
            if d>.4 then self:Move(self.fx*dt,self.fz*dt)
            else
                local a=self.age*.35
                self:Move(math.cos(a)*dt*.35,math.sin(a)*dt*.35)
                if self.stateTime>=3 then self:SetState(S.IDLE) end
            end
        end
    elseif state==S.ALERT then
        self:Face(target)
        if self.stateTime>=.4 then self:SetState(S.CHASE) end
    elseif state==S.CHASE then self:Chase(dt,target,distance)
    elseif state==S.TELEGRAPH then
        local lockTime=max(0,self.attack.telegraph-.18)
        if not self.directionLocked then
            -- Sampling on the crossing frame keeps the lock within one render
            -- frame of the last 0.18s. Never turn again during the active attack.
            self:Face(target); self.aimPoint=target
            if self.stateTime+1e-8>=lockTime then self.directionLocked=true; self:EmitAttackCue('danger') end
        end
        self.warning.progress=min(1,self.stateTime/self.attack.telegraph)
        self.warning.step=min(6,1+math.floor(self.warning.progress*6))
        if self.stateTime+1e-8>=self.attack.telegraph then self:SetState(S.ATTACK) end
    elseif state==S.ATTACK then
        self:AttackStep(dt,target)
        if self.state==S.ATTACK and self.stateTime+1e-8>=self.attack.duration then self:FinishAttack() end
    elseif state==S.RECOVER then
        if self.stateTime+1e-8>=self.attack.recover then self:AfterRecover() end
    elseif state==S.STAGGER and self.stateTime>=self.staggerDuration then
        self.down=false
        if not self.stumble then self.poise,self.poiseQuiet,self.poiseProtection=0,0,1.5 end
        self.stumble=false
        self:SetState(S.RECOVER)
    end
    self:UpdatePose()
    self:SyncShapes()
    if self.visual then self.visual:Update(self) end
end

function Base:SetActive(active)
    self.active=active
    if not active then
        self.presentationPending=false
        self:ReleaseAttackToken()
        if self.warning.visible or self.state==S.ATTACK then self:EmitAttackCue('stop'); self.warning.visible=false end
        self:ClearExtras()
        if self.particles then self.particles:ClearOwner(self) end
        self.down,self.stumble,self.poseY,self.posePitch,self.hitStop=false,false,0,0,0
        self.poseRoll=0; self.reaction.age=1
    end
    if self.node and not (self.visual and self.visual.removed) then self.node.enabled=active end
    self:SyncShapes()
end

function Base:Reset()
    if self.defeated then return false end
    self.hp,self.poise,self.down,self.phase=self.maxHP,0,false,1
    self.poiseQuiet,self.poiseProtection,self.directionLocked=0,0,false
    self.stumble=false
    self.presentationPending=false
    self.reaction.age=1; self.staggerLanded=false
    self.position=Vector3(self.home.x,self.home.y,self.home.z)
    self.fx,self.fz,self.yaw=0,1,0
    self.aggro,self.hitStop,self.poseY,self.posePitch=false,0,0,0
    self.attackIndex,self.attackTravel,self.pendingDt=0,0,0
    self.attack=self.config.attacks[1]
    for _,p in pairs(self.parts) do p.armor,p.broken=p.maxArmor,false end
    if self.particles then self.particles:ClearOwner(self) end
    self:ClearExtras(); self:SetState(S.IDLE); self:SyncShapes()
    if self.visual then self.visual:Update(self) end
    return true
end

-- Reused read-only snapshot. Surface faces/submissions are estimates, not GPU counters.
function Base:GetStats()
    local s=self.stats
    s.activeCount=self.active and not self.dead and 1 or 0
    s.voxelCount=self.metrics.voxelCount
    s.particleCount=self.particles and self.particles:CountOwner(self) or 0
    local visible=(self.active and (not self.dead or self.deathTime<.25)) and 1 or 0
    s.surfaceFacesEstimate=visible*self.metrics.surfaceFacesEstimate
    s.drawSubmissionsEstimate=visible*self.metrics.drawSubmissionsEstimate
    if s.activeCount>0 and self.warning.visible then s.drawSubmissionsEstimate=s.drawSubmissionsEstimate+1 end
    if s.activeCount>0 and self.phasePulse>0 then s.drawSubmissionsEstimate=s.drawSubmissionsEstimate+1 end
    s.deathStage=self.dead and (self.deathTime+1e-8<.12 and 'hold' or (self.deathTime+1e-8<.25 and 'release' or (self.deathTime+1e-8<1.1 and 'fragments' or 'cleared'))) or 'alive'
    s.presentedHits=self.presentedHits
    s.flashSupported=self.visual and self.visual.flashSupported or false
    s.rebuildCpuMs=self.visual and self.visual.rebuildCpuMs or 0
    return s
end

function Base:Destroy()
    self.presentationPending=false
    self:ReleaseAttackToken()
    self:ClearExtras()
    if self.visual then self.visual:Destroy(); self.visual=nil; self.node=nil end
    if self.particles then self.particles:Release(self); self.particles=nil end
end
return Base
