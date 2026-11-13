local Base=require('combat.enemies.EnemyBase')
---@class StoneSentry: EnemyBase
---@field stones table[]
local Sentry=setmetatable({}, {__index=Base})
Sentry.__index=Sentry
Sentry.Config={kind='stone_sentry',enemy='sentry',name='碎石哨灵',ranged=true,hp=24,poise=100,radius=.55,height=2.4,
    hover=1.1,speed=2.7,aggro=15,leash=32,attackDistance=12,defaultPart='body',voxelSize=.1,
    parts={
        {id='body',material='stone',x=0,y=.40,z=0,radius=.56,armor=0},
        {id='core',material='core',x=0,y=.38,z=.48,radius=.22,weak=true},
    },
    attacks={{name='stone',telegraph=.9,duration=.12,recover=1.2,range=12,warning='line',damage=9,poise=7}},
    sculpt={
        {'body',0,.35,0,.50,.50,.33,208,209,210},
        {'core',0,.36,.34,.20,.22,.15,211,212,211},
        {'crown',0,.93,0,.35,.16,.26,209,208,211},
        {'arm_l',-.60,.35,0,.16,.30,.21,210,209,208},
        {'arm_r',.60,.35,0,.16,.30,.21,210,209,208},
    }}
function Sentry.New(scene,world,terrain,combat,position,id)
    local self=setmetatable(Base.Create(scene,world,terrain,combat,Sentry.Config,position,id),Sentry)
    local started=os.clock()
    self.stones={}
    for i=1,3 do
        local shape={id='stone_'..i,center=Vector3(0,0,0),radius=0,weak=false,enabled=false,material='stone'}
        self.hurtShapes[#self.hurtShapes+1]=shape
        local stone={active=false,age=0,x=0,y=0,z=0,vx=0,vy=0,vz=0,shape=shape,
            info={dmg=9,poise=7,kind='stone',source=self.id,pos=Vector3.ZERO,dir=Vector3.FORWARD}}
        if world then
            local v=world:CreateVolume(3,3,3,.1,Vector3.ZERO,Quaternion())
            v.destructible,v.evictable=false,false
            v.collisionLayer,v.collisionMask=0,0
            local g=v:GetGrid()
            g:FillBox(0,0,0,2,2,2,true); g:PaintBox(0,0,0,2,2,2,208); v:RebuildGeometry()
            stone.volume,stone.node=v,v:GetNode(); stone.node.enabled=false
        end
        self.stones[i]=stone
    end
    self.projectileBuildCpuMs=(os.clock()-started)*1000
    return self
end
function Sentry:Chase(dt,target,distance)
    self:Face(target)
    if distance<8 then
        if not self:Move(-self.fx*self.config.speed*dt,-self.fz*self.config.speed*dt) then
            self:StartAttack()
        end
    elseif distance>12 then self:Move(self.fx*self.config.speed*dt,self.fz*self.config.speed*dt)
    else self:StartAttack() end
end
function Sentry:BeginAttack()
    for _,stone in ipairs(self.stones) do
        if not stone.active then
            stone.active,stone.age=true,0
            stone.x,stone.y,stone.z=self.position.x,self.position.y+1.48,self.position.z
            local target=self.directionLocked and self.aimPoint
                or (self.combat.PlayerPos and self.combat.PlayerPos() or self.lastTarget)
            local dx,dy,dz=self.fx,0,self.fz
            if target then dx,dy,dz=target.x-stone.x,target.y+.8-stone.y,target.z-stone.z end
            local n=math.max(.001,math.sqrt(dx*dx+dy*dy+dz*dz))
            stone.vx,stone.vy,stone.vz=dx/n*12,dy/n*12,dz/n*12
            stone.shape.enabled,stone.shape.radius=true,.21
            stone.shape.center=Vector3(stone.x,stone.y,stone.z)
            return
        end
    end
end
function Sentry:AttackStep(_,_) end

local function hide(stone)
    stone.active,stone.shape.enabled,stone.shape.radius=false,false,0
    if stone.node then stone.node.enabled=false end
end

function Sentry:TickExtras(dt,target)
    self.lastTarget=target
    for _,stone in ipairs(self.stones) do
        if stone.active then
            stone.age=stone.age+dt
            local dx,dy,dz=stone.vx*dt,stone.vy*dt,stone.vz*dt
            local length=math.sqrt(dx*dx+dy*dy+dz*dz)
            local blocked=false
            if self.world and length>.001 then
                local hit=self.world:RaycastSingle(Ray(Vector3(stone.x,stone.y,stone.z),Vector3(dx/length,dy/length,dz/length)),length)
                blocked=hit.hit
            end
            local px,py,pz=target.x-stone.x,target.y+.8-stone.y,target.z-stone.z
            local u=length>0 and math.max(0,math.min(1,(px*dx+py*dy+pz*dz)/(length*length))) or 0
            -- Swept sphere vs player torso; an ordinary dodge's invulnerability is handled by Combat.
            local hitPlayer=(px-dx*u)^2+(py-dy*u)^2+(pz-dz*u)^2<=.55^2
            if blocked or stone.age>=3 then hide(stone)
            elseif hitPlayer then
                stone.info.pos=Vector3(stone.x,stone.y,stone.z)
                stone.info.dir=Vector3(stone.vx/12,stone.vy/12,stone.vz/12)
                if self.combat.DamagePlayer then self.combat.DamagePlayer(stone.info) end
                hide(stone)
            else
                stone.x,stone.y,stone.z=stone.x+dx,stone.y+dy,stone.z+dz
                stone.shape.center=Vector3(stone.x,stone.y,stone.z)
                if stone.node then stone.node.enabled=true; stone.node.position=Vector3(stone.x-.15,stone.y-.15,stone.z-.15) end
            end
        end
    end
end
---@return EnemyHitResult
function Sentry:ApplyHit(info)
    if info.part and info.part:sub(1,6)=='stone_' then
        local index=tonumber(info.part:sub(7))
        local stone=index and self.stones[index]
        self:ClearHitResult()
        if stone and stone.active and info.kind=='sword' then
            local fx=self.impact
            local pos,dir=info.pos or stone.shape.center,info.dir or Vector3.FORWARD
            fx.pos,fx.dir=Vector3(pos.x,pos.y,pos.z),Vector3(dir.x,dir.y,dir.z)
            local normal=info.normal
            fx.normal=normal and Vector3(normal.x,normal.y,normal.z) or Vector3(-dir.x,-dir.y,-dir.z)
            fx.material,fx.part,fx.tier,fx.kind,fx.weak='stone',info.part,info.tier or 'light','deflect',false
            fx.swingId,fx.weapon=info.swingId,info.weapon or info.kind
            hide(stone); self.result.hit=true
            self.result.part,self.result.material=info.part,'stone'
            self:StageHitPresentation(info,self.result)
        end
        return self.result
    end
    return Base.ApplyHit(self,info)
end
function Sentry:ClearExtras()
    if self.stones then for _,stone in ipairs(self.stones) do hide(stone) end end
end
function Sentry:GetStats()
    local s=Base.GetStats(self)
    s.rebuildCpuMs=s.rebuildCpuMs+self.projectileBuildCpuMs
    s.voxelCount=s.voxelCount+81 -- three fixed 3x3x3 projectile meshes, even while hidden
    for _,stone in ipairs(self.stones) do
        if stone.active then
            s.surfaceFacesEstimate=s.surfaceFacesEstimate+54
            s.drawSubmissionsEstimate=s.drawSubmissionsEstimate+1
        end
    end
    return s
end
function Sentry:Destroy()
    Base.Destroy(self)
    if self.world then
        for _,stone in ipairs(self.stones) do
            if stone.volume then self.world:RemoveVolume(stone.volume); stone.volume=nil; stone.node=nil end
        end
    end
end
return Sentry
