-- Scene-wide fixed pool. Two prebuilt hard-edge meshes per slot; only one is visible.
-- Shared opaque materials, no per-hit mesh/material/closure allocation or physics.
---@class EnemyParticles
---@field slots table[]
---@field key table|Scene
---@field root Node?
---@field rebuildCpuMs number
---@field reserved number
---@field materials table<string, Material>
---@field stats table
local Pool={}
Pool.__index=Pool
Pool.LIMIT=64
Pool.RESERVED=16
local pools=setmetatable({}, {__mode='k'})
local COLORS={soft={.63,.66,.36},armor={.95,.79,.49},core={.58,.85,1},stone={.62,.63,.59},flash={1,.94,.72}}
-- Construction only. Unit box and two crossed tapered diamonds; transforms set size.
local function mesh(parent,name,cross)
    local node=parent:CreateChild(name)
    local g=node:CreateComponent('CustomGeometry')
    g.castShadows=false
    g:BeginGeometry(0,TRIANGLE_LIST)
    local function tri(a,b,c)
        for _,p in ipairs({a,b,c}) do g:DefineVertex(Vector3(p[1],p[2],p[3])); g:DefineNormal(Vector3.UP) end
    end
    if cross then
        for _,a in ipairs({0,math.pi/2}) do
            local x,z=math.cos(a),math.sin(a)
            tri({0,.5,0},{-.10*x,0,-.10*z},{0,-.5,0})
            tri({0,.5,0},{0,-.5,0},{.10*x,0,.10*z})
            tri({-.5*x,0,-.5*z},{0,.10,0},{.5*x,0,.5*z})
            tri({-.5*x,0,-.5*z},{.5*x,0,.5*z},{0,-.10,0})
        end
    else
        ---@type number[][]
        local v={{-.5,-.5,-.5},{.5,-.5,-.5},{.5,.5,-.5},{-.5,.5,-.5},
            {-.5,-.5,.5},{.5,-.5,.5},{.5,.5,.5},{-.5,.5,.5}}
        tri(v[1],v[2],v[3]); tri(v[1],v[3],v[4])
        tri(v[6],v[5],v[8]); tri(v[6],v[8],v[7])
        tri(v[5],v[1],v[4]); tri(v[5],v[4],v[8])
        tri(v[2],v[6],v[7]); tri(v[2],v[7],v[3])
        tri(v[4],v[3],v[7]); tri(v[4],v[7],v[8])
        tri(v[5],v[6],v[2]); tri(v[5],v[2],v[1])
    end
    g:Commit(); node.enabled=false
    return node,g
end
function Pool.Acquire(scene,world,fallbackKey)
    local key=scene or fallbackKey
    local self=pools[key]
    if not self then
        self=setmetatable({slots={},references=0,count=0,peak=0,key=key,rebuildCpuMs=0,
            limit=Pool.LIMIT,reserved=Pool.RESERVED,serial=0,materials={},evicted=0,dropped=0,
            stats={count=0,cubeCount=0,flatCount=0,reserved=16,capacity=64,peak=0,evicted=0,dropped=0,trianglesEstimate=0}},Pool)
        pools[key]=self
        local started=os.clock()
        if scene then
            self.root=scene:CreateChild('EnemyParticlePool')
            for name,c in pairs(COLORS) do
                local mat=Material:new()
                mat:SetTechnique(0,cache:GetResource('Technique','Techniques/NoTextureUnlit.xml'))
                mat:SetShaderParameter('MatDiffColor',Variant(Color(c[1],c[2],c[3],1)))
                mat:SetCullMode(CULL_NONE); self.materials[name]=mat
            end
        end
        for i=1,Pool.LIMIT do
            local slot={active=false,owner=false,age=0,ttl=0,x=0,y=0,z=0,vx=0,vy=0,vz=0,
                sx=1,sy=1,sz=1,priority=0,serial=0,shape='cube',material='stone',gravity=3}
            if self.root then
                slot.box,slot.boxGeom=mesh(self.root,'box_'..i,false)
                slot.cross,slot.crossGeom=mesh(self.root,'cross_'..i,true)
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
-- 32/64 total. Keep the key-event reserve; changing quality cannot retain excess slots.
function Pool:SetLimit(limit)
    local nextLimit=limit<=32 and 32 or 64
    if nextLimit==self.limit then return end
    self.limit=nextLimit
    -- Quality changes may drop decoration immediately, never preferentially key events.
    for _,slot in ipairs(self.slots) do if slot.priority==0 then self:Hide(slot) end end
    while self.count>self.limit do
        local oldest
        for _,slot in ipairs(self.slots) do
            if slot.active and (not oldest or slot.priority<oldest.priority
                or (slot.priority==oldest.priority and slot.serial<oldest.serial)) then oldest=slot end
        end
        if not oldest then break end
        self:Hide(oldest)
    end
end
function Pool:Claim(priority,family)
    if priority==0 then
        local used=0
        for _,slot in ipairs(self.slots) do if slot.active and slot.family==family then used=used+1 end end
        local familyCap=family=='flat' and (self.limit==32 and 12 or 24) or (self.limit==32 and 20 or 40)
        if used>=familyCap then self.dropped=self.dropped+1; return nil end
    end
    local cap=priority>0 and self.limit or self.limit-self.reserved
    if self.count<cap then
        for i=1,Pool.LIMIT do if not self.slots[i].active then return self.slots[i] end end
    end
    if priority>0 then
        local candidate
        for i=1,Pool.LIMIT do
            local slot=self.slots[i]
            if slot.active and slot.priority<priority and (not candidate or slot.priority<candidate.priority
                or (slot.priority==candidate.priority and slot.serial<candidate.serial)) then candidate=slot end
        end
        if candidate then self:Hide(candidate); self.evicted=self.evicted+1; return candidate end
    end
    self.dropped=self.dropped+1
    return nil
end
-- info = {pos,dir,normal?,material,tier,weak?,broke?,kind?}. Pos/dir are REQUIRED.
-- Hit precedence: death > break > heavy > weak > material. One impact never emits all layers.
function Pool:Emit(owner,info)
    if type(info)~="table" or not info.pos or not info.dir then return 0 end
    local death,broken=info.kind=='death',info.broke==true
    local heavy=info.tier=='heavy' or info.tier=='third'
    local weak=info.weak or info.material=='core'
    local dust,phase=info.kind=='dust',info.kind=='phase'
    local count=death and (owner.boss and 24 or 12) or (broken and 12 or (heavy and 11 or (weak and 6 or (info.material=='armor' and 8 or 6))))
    if dust then count=6 elseif phase then count=10 end
    local priority=death and 3 or (broken and 2 or 0)
    if death then self:ClearOwner(owner) end
    local dx,dy,dz=info.dir.x,info.dir.y,info.dir.z
    local n=math.sqrt(dx*dx+dy*dy+dz*dz)
    if n<.001 then dx,dy,dz=0,0,1 else dx,dy,dz=dx/n,dy/n,dz/n end
    local normal=info.normal
    local nx,ny,nz=normal and normal.x or -dx,normal and normal.y or -dy,normal and normal.z or -dz
    n=math.max(.001,math.sqrt(nx*nx+ny*ny+nz*nz)); nx,ny,nz=nx/n,ny/n,nz/n
    local dot=dx*nx+dy*ny+dz*nz
    local tx,ty,tz=dx-dot*nx,dy-dot*ny,dz-dot*nz
    n=math.sqrt(tx*tx+ty*ty+tz*tz)
    if n<.01 then
        if math.abs(ny)<.9 then tx,ty,tz=-nz,0,nx else tx,ty,tz=1,0,0 end
        n=math.sqrt(tx*tx+ty*ty+tz*tz)
    end
    tx,ty,tz=tx/n,ty/n,tz/n
    local emitted=0
    for i=1,count do
        local flat=not (death or broken or phase or dust) and ((heavy and i==11) or (not heavy and (weak or info.material=='armor' or info.material=='stone')))
        local family=flat and 'flat' or 'cube'
        local slot=self:Claim(priority,family)
        if not slot then break end
        local q=(i%5)/4
        slot.active,slot.owner,slot.age,slot.priority,slot.family=true,owner,0,priority,family
        self.serial=self.serial+1; slot.serial=self.serial
        slot.x,slot.y,slot.z=info.pos.x,info.pos.y,info.pos.z
        slot.material=COLORS[info.material] and info.material or 'stone'
        slot.shape,slot.gravity='cube',3
        local speed=.6+q*.6
        local ax,ay,az=dx,dy,dz
        slot.ttl=.18+q*.12
        slot.sx,slot.sy,slot.sz=.04+q*.04,.04+q*.04,.04+q*.04
        if death or broken or phase then
            slot.shape='plate'; slot.ttl=death and (.6+q*.25) or (.35+q*.25)
            slot.sx,slot.sy,slot.sz=.12+q*.08,.025,.10+q*.06
            speed=death and (.8+q) or (1.2+q)
            ax,ay,az=nx,ny,nz
        elseif dust then
            slot.ttl=.2+q*.1; slot.sx,slot.sy,slot.sz=.045,.025,.045
            ax,ay,az=tx*(i%2==0 and 1 or -1),.2,tz*(i%2==0 and 1 or -1)
        elseif heavy then
            slot.ttl=.25+q*.15; slot.sx,slot.sy,slot.sz=.09+q*.05,.07,.09
            if i==11 then
                slot.shape,slot.material,slot.ttl,slot.gravity='cross','flash',.06,0
                slot.sx,slot.sy,slot.sz=.18,.18,.18; speed=0
            end
        elseif weak then
            slot.shape='cross'; slot.ttl=.18+q*.1
            slot.sx,slot.sy,slot.sz=.10+q*.06,.10+q*.06,.10+q*.06
        elseif info.material=='armor' or info.material=='stone' then
            slot.shape='spark'; slot.ttl=.15+q*.1
            slot.sx,slot.sy,slot.sz=.035,.012,.12
            speed=1.5+q*1.5; ax,ay,az=tx,ty,tz
        end
        -- Narrow deterministic fan around the selected direction. Contact remains exact.
        local spread=slot.shape=='spark' and 0 or (i%3-1)*.16
        slot.vx,slot.vy,slot.vz=(ax+tx*spread)*speed,(ay+(slot.shape=='spark' and 0 or .15))*speed,(az+tz*spread)*speed
        if slot.node then slot.node.enabled=false end
        if slot.box then
            slot.node=slot.shape=='cross' and slot.cross or slot.box
            local g=slot.shape=='cross' and slot.crossGeom or slot.boxGeom
            g:SetMaterial(self.materials[slot.material])
            slot.node.position=Vector3(slot.x,slot.y,slot.z)
            slot.node.rotation=Quaternion(math.deg(math.atan(slot.vx,slot.vz)),Vector3.UP)
            slot.node.scale=Vector3(slot.sx,slot.sy,slot.sz); slot.node.enabled=true
        end
        self.count=self.count+1; emitted=emitted+1
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
                slot.y=slot.y+slot.vy*dt; slot.vy=slot.vy-slot.gravity*dt
                if slot.node then
                    slot.node.position=Vector3(slot.x,slot.y,slot.z)
                    local fade=1-math.floor(slot.age/slot.ttl*8)/8
                    slot.node.scale=Vector3(slot.sx*fade,slot.sy*fade,slot.sz*fade)
                end
            end
        end
    end
end
-- Reused read-only snapshot. Flat opaque meshes avoid transparent billboard overdraw.
function Pool:GetStats()
    local s=self.stats
    s.count,s.capacity,s.reserved,s.peak=self.count,self.limit,self.reserved,self.peak
    s.evicted,s.dropped,s.cubeCount,s.flatCount,s.trianglesEstimate=self.evicted,self.dropped,0,0,0
    for _,slot in ipairs(self.slots) do
        if slot.active then
            if slot.family=='flat' then s.flatCount=s.flatCount+1 else s.cubeCount=s.cubeCount+1 end
            s.trianglesEstimate=s.trianglesEstimate+(slot.shape=='cross' and 8 or 12)
        end
    end
    return s
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
    self:ClearOwner(owner); self.references=self.references-1
    if self.references==0 then
        if self.root then self.root:Remove() end
        pools[self.key]=nil
    end
end
return Pool
