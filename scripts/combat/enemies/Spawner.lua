local Base=require('combat.enemies.EnemyBase')
local Beetle=require('combat.enemies.MossBeetle')
local Sentry=require('combat.enemies.StoneSentry')
local Beast=require('combat.enemies.StoneBeast')
---@class EnemySpawner
---@field enemies EnemyBase[]
---@field scene Scene?
---@field world VoxelPhysicsWorld?
---@field terrain table
---@field combat table
---@field arenaVolumes VoxelVolume[]
local Spawner={}
Spawner.__index=Spawner
Spawner.MAX_ACTIVE=4 -- minors only; a live Boss arena selects the Boss exclusively
Spawner.ARENA_DISTANCE=18
Spawner.ACTIVE_DISTANCE=38
Spawner.RESET_DISTANCE=40

-- Anchors audited against RuinsScene.SPAWN / DRAGON_POS and RuinsBuild.STELE_POS.
-- Requiring RuinsScene here would create a Scene -> Combat -> Spawner cycle.
Spawner.SPAWN_X,Spawner.SPAWN_Z=0,-64
Spawner.DRAGON_X,Spawner.DRAGON_Z=0,4
local function d2(x,z,a,b) return (x-a)^2+(z-b)^2 end

---@param scene Scene?
---@param world VoxelPhysicsWorld?
---@param terrain table
---@param combat table?
function Spawner.New(scene,world,terrain,combat)
    local self=setmetatable({},Spawner)
    self:Init(scene,world,terrain,combat)
    return self
end
function Spawner:ValidPosition(x,z,radius,arena)
    local t=self.terrain
    local y=t.GroundHeight(x,z)
    if y==nil or not t.HasGround(x,z,2+radius) or not t.IsSafeGround(x,y,z) then return nil end
    if d2(x,z,0,-64)<225 or d2(x,z,0,t.ISLAND.bridgeMainZ)<225
        or d2(x,z,0,t.ISLAND.bridgeRingZ)<225 or d2(x,z,0,4)<18^2 then return nil end
    if d2(x,z,-36,-6)<8^2 then return nil end -- tower/key path
    local stele=29.5/math.sqrt(2)
    for sx=-1,1,2 do for sz=-1,1,2 do
        if d2(x,z,sx*stele,sz*stele)<(arena and 6.5 or 5.5)^2 then return nil end
    end end
    local probes=self.footprints[radius]
    if not probes then probes=Base.MakeFootprint(radius); self.footprints[radius]=probes end
    for _,offset in ipairs(probes) do
        local px,pz=x+offset.x,z+offset.z
        local py=t.GroundHeight(px,pz)
        if py==nil or not t.HasGround(px,pz,2) or not t.IsSafeGround(px,py,pz) or math.abs(py-y)>.6 then return nil end
    end
    return y
end
function Spawner:Init(scene,world,terrain,combat)
    self.scene,self.world,self.terrain,self.combat=scene,world,terrain,combat or {}
    self.enemies,self.placements,self.rejected,self.obstacles,self.arenaVolumes={},{},{},{},{}
    self.nearest,self.distances={},{ }
    self.activeCount,self.aiUpdates=0,0
    self.footprints={}
    self.perf={activeCount=0,minorCount=0,bossCount=0,voxelCount=0,activeVoxelCount=0,particleCount=0,
        particleCapacity=64,surfaceFacesEstimate=0,drawSubmissionsEstimate=0,rebuildCpuMs=0,
        aiUpdates=0,actualDrawCalls=false,actualFrameMs=false,scope='enemies_and_hit_death_particles'}
    self.attackGroup={count=0,limit=2} -- at most two melee windups/active attacks, held until recovery
    local r=terrain.ISLAND.mainRadius
    -- Each authored encounter is two melee beetles and one ranged sentry.
    -- These clearings derive from mainRadius and are individually terrain-validated.
    local seeds={
        {Beetle,-r*.70,-12,'moss_w1'}, {Beetle,-r*.70-1.5,-14,'moss_w2'}, {Sentry,-r*.70+1.5,-10,'sentry_w'},
        {Beetle,r*.70,-12,'moss_e1'}, {Beetle,r*.70-1.5,-14,'moss_e2'}, {Sentry,r*.70+1.5,-10,'sentry_e'},
        {Beast,10,r*.69,'stone_beast'},
    }
    for _,seed in ipairs(seeds) do
        local class,x,z,id=seed[1],seed[2],seed[3],seed[4]
        local y=self:ValidPosition(x,z,class.Config.radius,class==Beast)
        if y then
            local enemy=class.New(scene,world,terrain,self.combat,Vector3(x,y,z),id)
            if not class.Config.ranged then enemy.attackGroup=self.attackGroup end
            enemy:SetActive(false)
            self.enemies[#self.enemies+1]=enemy
            self.placements[#self.placements+1]={id=id,x=x,y=y,z=z}
            if class==Beast then self.boss=enemy; self:BuildArena(enemy) end
        else
            self.rejected[#self.rejected+1]=id
            print('EnemySpawner: unsafe placement skipped: '..id)
        end
    end
end

-- Pillars have visual voxels and analytic XZ circles ONLY. No physical blockers
-- are inserted into the puzzle world. EnemyBase sweeps against these circles.
function Spawner:BuildArena(boss)
    local x,z=boss.home.x,boss.home.z
    local offsets={{-2,1},{2,2},{3,-3}}
    for _,o in ipairs(offsets) do
        local px,pz=x+o[1],z+o[2]
        local y=self:ValidPosition(px,pz,.5,true)
        if y then
            self.obstacles[#self.obstacles+1]={x=px,y=y,z=pz,radius=.5,height=2.5}
            self:ArenaVoxel(px,y,pz,.5,2.5,true)
        end
    end
    boss.obstacles=self.obstacles
    for i=1,20 do
        local a=i*math.pi*2/20
        local px,pz=x+math.cos(a)*5.2,z+math.sin(a)*5.2
        local y=self:ValidPosition(px,pz,.25,true)
        if y then self:ArenaVoxel(px,y,pz,.25,.3,false) end
    end
end
function Spawner:ArenaVoxel(x,y,z,radius,height,pillar)
    if not self.world then return end
    local s=.2
    local nx,ny=math.ceil(radius*2/s),math.ceil(height/s)
    local vol=self.world:CreateVolume(nx,ny,nx,s,Vector3(x-nx*s/2,y,z-nx*s/2),Quaternion())
    local g=vol:GetGrid()
    for ix=0,nx-1 do for iz=0,nx-1 do
        if ((ix+.5)*s-radius)^2+((iz+.5)*s-radius)^2<=radius^2 then
            for iy=0,ny-1 do
                g:SetSolid(ix,iy,iz,true)
                g:SetVoxelMaterial(ix,iy,iz,pillar and iy%5==0 and 219 or 216)
            end
        end
    end end
    vol.destructible,vol.evictable=false,false
    vol.collisionLayer,vol.collisionMask=0,0
    vol:RebuildGeometry()
    self.arenaVolumes[#self.arenaVolumes+1]=vol
end

function Spawner:SetCombat(combat)
    self.combat=combat
    for _,enemy in ipairs(self.enemies) do enemy:SetCombat(combat) end
end
function Spawner:GetEnemies() return self.enemies end
-- W2 may emit player/arrow flecks into this SAME pool, ticking its own owner once/frame.
function Spawner:GetParticlePool()
    return self.enemies[1] and self.enemies[1].particles or nil
end

function Spawner:Update(dt,playerPos)
    local target=playerPos or (self.combat.PlayerPos and self.combat.PlayerPos())
    if not target then return end
    for i=1,Spawner.MAX_ACTIVE do self.nearest[i]=false; self.distances[i]=math.huge end
    local boss=self.boss
    local bossArena=boss and not boss.dead and (d2(target.x,target.z,boss.home.x,boss.home.z)<=Spawner.ARENA_DISTANCE^2
        or (boss.aggro and d2(target.x,target.z,boss.position.x,boss.position.z)<=boss.config.leash^2))
    -- A fixed four-entry insertion list avoids sorting or temporary tables every frame.
    for _,enemy in ipairs(self.enemies) do
        enemy.selected=false
        local distance=d2(target.x,target.z,enemy.position.x,enemy.position.z)
        if not enemy.dead and distance<=Spawner.ACTIVE_DISTANCE^2
            and ((bossArena and enemy==boss) or (not bossArena and not enemy.boss)) then
            for i=1,Spawner.MAX_ACTIVE do
                if distance<self.distances[i] then
                    for j=Spawner.MAX_ACTIVE,i+1,-1 do self.nearest[j]=self.nearest[j-1]; self.distances[j]=self.distances[j-1] end
                    self.nearest[i],self.distances[i]=enemy,distance
                    break
                end
            end
        end
        if not enemy.dead and distance>Spawner.RESET_DISTANCE^2
            and d2(target.x,target.z,enemy.home.x,enemy.home.z)>Spawner.RESET_DISTANCE^2
            and (enemy.aggro or enemy.hp~=enemy.maxHP or enemy.poise~=0 or enemy.state~='IDLE'
                or d2(enemy.position.x,enemy.position.z,enemy.home.x,enemy.home.z)>.000001) then
            -- Losing the player drops aggro first; reset only after that disengagement.
            enemy.aggro=false
            enemy:Reset()
        end
    end
    for i=1,Spawner.MAX_ACTIVE do
        local enemy=self.nearest[i]
        if enemy then enemy.selected=true end
    end
    self.activeCount,self.aiUpdates=0,0
    for _,enemy in ipairs(self.enemies) do
        if enemy.dead then
            enemy:Update(dt,target) -- death visuals only, no AI or position queries
        elseif enemy.selected then
            if not enemy.active then enemy:SetActive(true) end
            enemy:Update(dt,target)
            self.activeCount,self.aiUpdates=self.activeCount+1,self.aiUpdates+1
        elseif enemy.active then
            enemy.aggro=false; enemy:SetActive(false)
            enemy:SetState('IDLE') -- do not resume a half-complete attack on activation
        end
    end
end

-- Reset survivors on player respawn; defeated actors remain defeated for this session.
function Spawner:Reset()
    for _,enemy in ipairs(self.enemies) do enemy:Reset(); enemy:SetActive(false) end
end
-- Read-only reused snapshot. Faces/draw submissions are conservative estimates;
-- rebuildCpuMs measures synchronous construction CPU time, not GPU work or Web FPS.
function Spawner:GetPerfStats()
    local p=self.perf
    p.activeCount,p.minorCount,p.bossCount=0,0,0
    p.voxelCount,p.activeVoxelCount,p.particleCount=0,0,0
    p.surfaceFacesEstimate,p.drawSubmissionsEstimate,p.rebuildCpuMs=0,0,0
    p.aiUpdates=self.aiUpdates
    for _,enemy in ipairs(self.enemies) do
        local s=enemy:GetStats()
        p.activeCount=p.activeCount+s.activeCount
        if enemy.boss then p.bossCount=p.bossCount+s.activeCount else p.minorCount=p.minorCount+s.activeCount end
        p.voxelCount=p.voxelCount+s.voxelCount
        p.activeVoxelCount=p.activeVoxelCount+s.activeCount*s.voxelCount
        p.particleCount=p.particleCount+s.particleCount
        p.surfaceFacesEstimate=p.surfaceFacesEstimate+s.surfaceFacesEstimate
        p.drawSubmissionsEstimate=p.drawSubmissionsEstimate+s.drawSubmissionsEstimate
        p.rebuildCpuMs=p.rebuildCpuMs+s.rebuildCpuMs
    end
    local first=self.enemies[1]
    if first and first.particles then
        local particles=first.particles:GetStats()
        p.particleCount=particles.count -- global scene pool, including W2 external owners
        p.particleCapacity,p.particleReserved=particles.capacity,particles.reserved
        p.particleCubes,p.particleFlat,p.particleTrianglesEstimate=particles.cubeCount,particles.flatCount,particles.trianglesEstimate
        p.particleEvicted,p.particleDropped=particles.evicted,particles.dropped
        p.rebuildCpuMs=p.rebuildCpuMs+first.particles.rebuildCpuMs
    end
    p.surfaceFacesEstimate=p.surfaceFacesEstimate+p.particleCount*8
    p.drawSubmissionsEstimate=p.drawSubmissionsEstimate+p.particleCount
    return p
end

function Spawner:Destroy()
    for _,enemy in ipairs(self.enemies) do enemy:Destroy() end
    if self.world then for _,vol in ipairs(self.arenaVolumes) do self.world:RemoveVolume(vol) end end
    self.enemies,self.arenaVolumes={},{}
end
return Spawner
