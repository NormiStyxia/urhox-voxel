-- One shared 64-slot pool per scene. Cubes are built once, never remeshed in combat.
-- Owner-scoped ticking lets standalone actors and Spawner share the same lifetime rule.
---@class EnemyParticles
---@field world VoxelPhysicsWorld?
---@field slots table[]
---@field key table|Scene
---@field rebuildCpuMs number
local Pool={}
Pool.__index=Pool
Pool.LIMIT=64
local pools=setmetatable({}, {__mode='k'})
function Pool.Acquire(scene,world,fallbackKey)
    local key=scene or fallbackKey
    local self=pools[key]
    if not self then
        self=setmetatable({slots={},references=0,count=0,peak=0,world=world,key=key,rebuildCpuMs=0},Pool)
        pools[key]=self
        local started=os.clock()
        for i=1,Pool.LIMIT do
            local slot={active=false,owner=false,age=0,ttl=0,x=0,y=0,z=0,vx=0,vy=0,vz=0,size=1}
            -- Fixed colors: no palette mutation or grid rebuild when slots are reused.
            local color=i%4==0 and 219 or (i%3==0 and 203 or 216)
            if scene and world then
                local v=world:CreateVolume(1,1,1,.12,Vector3.ZERO,Quaternion())
                local g=v:GetGrid(); g:SetSolid(0,0,0,true); g:SetVoxelMaterial(0,0,0,color)
                v.destructible,v.evictable=false,false
                v.collisionLayer,v.collisionMask=0,0
                v:RebuildGeometry()
                slot.volume,slot.node=v,v:GetNode(); slot.node.enabled=false
            end
            self.slots[i]=slot
        end
        self.rebuildCpuMs=(os.clock()-started)*1000
    end
    self.references=self.references+1
    return self
end
function Pool:Hide(slot)
    if not slot.active then return end
    slot.active,slot.owner=false,false
    self.count=self.count-1
    if slot.node then slot.node.enabled=false end
end
function Pool:Emit(owner,count,death)
    local emitted=0
    -- Death replaces this actor's pending hit flecks, freeing room for its burst.
    if death then self:ClearOwner(owner) end
    for i,slot in ipairs(self.slots) do
        if emitted>=count then break end
        if not slot.active then
            emitted=emitted+1
            slot.active,slot.owner,slot.age=true,owner,0
            slot.ttl=death and 1.4 or .35
            slot.size=death and 1.4 or .6
            local a=(i+owner.age)*2.399963
            slot.x=owner.position.x+math.cos(a)*owner.radius*.65
            slot.y=owner.position.y+(owner.config.hover or 0)+owner.config.height*.4
            slot.z=owner.position.z+math.sin(a)*owner.radius*.65
            slot.vx,slot.vz=math.cos(a)*1.6,math.sin(a)*1.6
            slot.vy=death and (1.2+i%4*.25) or .7
            self.count=self.count+1
            if slot.node then
                slot.node.position=Vector3(slot.x,slot.y,slot.z)
                slot.node:SetScale(slot.size); slot.node.enabled=true
            end
        end
    end
    self.peak=math.max(self.peak,self.count)
    return emitted
end
function Pool:UpdateOwner(owner,dt)
    for _,slot in ipairs(self.slots) do
        if slot.active and slot.owner==owner then
            slot.age=slot.age+dt
            if slot.age+1e-8>=slot.ttl then self:Hide(slot)
            else
                slot.x,slot.z=slot.x+slot.vx*dt,slot.z+slot.vz*dt
                slot.y=slot.y+slot.vy*dt; slot.vy=slot.vy-3*dt
                if slot.node then
                    slot.node.position=Vector3(slot.x,slot.y,slot.z)
                    slot.node:SetScale(slot.size*(1-math.floor(slot.age/slot.ttl*8)/8))
                end
            end
        end
    end
end
function Pool:CountOwner(owner)
    local count=0
    for _,slot in ipairs(self.slots) do if slot.active and slot.owner==owner then count=count+1 end end
    return count
end
function Pool:ClearOwner(owner)
    for _,slot in ipairs(self.slots) do if slot.owner==owner then self:Hide(slot) end end
end
function Pool:Release(owner)
    self:ClearOwner(owner)
    self.references=self.references-1
    if self.references==0 then
        if self.world then
            for _,slot in ipairs(self.slots) do if slot.volume then self.world:RemoveVolume(slot.volume) end end
        end
        pools[self.key]=nil
    end
end
return Pool
