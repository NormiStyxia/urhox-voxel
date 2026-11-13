-- Nomi's weapon sockets and visual motion. CombatAnim owns attack timing/poses.
-- All volumes are visual-only. No Finalize, collision or gameplay damage calls.
local Builder=require("combat.WeaponBuilder")
local Parts=require("combat.WeaponParts")
local Store=require("combat.WeaponStore")

---@class WeaponRigEntry
---@field pivot Node
---@field mesh WeaponMesh

---@class WeaponTrail
---@field volume VoxelVolume
---@field node Node
---@field material Material

---@class WeaponTrailSample
---@field position Vector3
---@field rotation Quaternion
---@field moving boolean

---@class WeaponRig
---@field scene Scene
---@field world VoxelPhysicsWorld
---@field controller NomiController
---@field body Node
---@field sockets table<string, Node>
---@field entries table<string, WeaponRigEntry>
---@field config table
---@field active string
---@field pose string requested pose
---@field attached string current visual socket
---@field transition table?
---@field swingOffset Vector3
---@field swingEuler Vector3
---@field previousBody Vector3
---@field lag Vector3
---@field trails WeaponTrail[]
---@field history WeaponTrailSample[]
---@field historyCount integer
---@field afterimages table? Borrowed animation array, never copied or modified.
---@field afterimagesFresh boolean
---@field imageElapsed number
---@field images WeaponTrail[]
---@field particles table[]
---@field imageMin Vector3
---@field imageKey string
---@field trailTip Vector3
---@field particleStamp number?
---@field trailEnabled boolean
---@field disposed boolean
local Rig={}
Rig.__index=Rig
local TRAIL_FRAMES=8
local FADE_FRAMES=8
local function Vec(t) return Vector3(t[1],t[2],t[3]) end
local function Clamp(n,lo,hi) return math.max(lo,math.min(hi,n)) end
local function Delta(a,b) return (a-b+180)%360-180 end
local function Single(config,weapon)
    return {weapon=weapon,parts=config[weapon].parts,colors=config[weapon].colors}
end

---@param scene Scene
---@param world VoxelPhysicsWorld
---@param nomiController NomiController
---@return WeaponRig
function Rig.New(scene,world,nomiController)
    local self=setmetatable({},Rig)
    self:Init(scene,world,nomiController)
    return self
end

---@param scene Scene
---@param world VoxelPhysicsWorld
---@param controller NomiController
function Rig:Init(scene,world,controller)
    self.scene,self.world,self.controller=scene,world,controller
    self.config=Store.Load()
    self.active,self.pose,self.attached=self.config.active,"hidden","hidden"
    self.transition=nil
    self.swingOffset,self.swingEuler=Vector3.ZERO,Vector3.ZERO
    self.lag=Vector3.ZERO
    self.trails,self.history,self.images,self.particles={},{},{},{}
    self.historyCount,self.imageElapsed=0,0
    for i=1,TRAIL_FRAMES+1 do self.history[i]={position=Vector3.ZERO,rotation=Quaternion(),moving=false} end
    self.trailEnabled,self.disposed=true,false
    ---@type table<string, Node>
    local bones=controller.nomi.bones
    self.body=assert(bones.body,"WeaponRig requires body bone")
    self.previousBody=self.body.rotation.eulerAngles
    local backSword=self.body:CreateChild("back_sword")
    backSword.position=Vector3(0.12,0.05,-0.23)
    -- +35 around Z takes +Y to character-left (-X).
    backSword.rotation=Quaternion(0,0,35)
    local backBow=self.body:CreateChild("back_bow")
    backBow.position=Vector3(0,0.15,-0.28)
    backBow.rotation=Quaternion(0,0,90)
    local left=assert(bones.arm_left):CreateChild("hand_left")
    local rightPosition=controller.castSocket.position
    left.position=Vector3(-rightPosition.x,rightPosition.y,rightPosition.z)
    self.sockets={back_sword=backSword,back_bow=backBow,hand_right=controller.castSocket,hand_left=left}
    self.entries={}
    for _,weapon in ipairs({"sword","bow"}) do
        local pivot=self.body:CreateChild("weapon_grip_"..weapon)
        pivot.temporary=true
        local mesh=assert(Builder.Build(world,pivot,Single(self.config,weapon)))
        self.entries[weapon]={pivot=pivot,mesh=mesh}
        Builder.SetOpacity(mesh,0)
    end
    self:CreateTrail()
    self:BuildSwordImages()
    self:UpdateTrailColor()
end

function Rig:CreateTrail()
    -- Eight tiny fixed fragments (32 voxels total), reused for the rig's lifetime.
    -- Their transforms follow saved world-space grip samples, never a hand parent.
    for i=1,TRAIL_FRAMES do
        local vol=self.world:CreateVolume(1,4,1,Parts.VOXEL_SIZE,Vector3.ZERO,Quaternion())
        local grid=vol:GetGrid()
        for y=0,3 do grid:SetSolid(0,y,0,true); grid:SetVoxelMaterial(0,y,0,Builder.TRAIL_PALETTE) end
        vol.destructible=false
        vol.evictable=false
        vol.collisionMask=0
        vol.collisionLayer=0
        local material=Builder.FadeMaterial(self.world,"WeaponTrail_"..i)
        material:SetShaderParameter("MatDiffColor",Variant(Color(1,1,1,(TRAIL_FRAMES+1-i)/16)))
        vol.material=material
        vol:RebuildGeometry()
        local node=vol:GetNode()
        node.name="weapon_trail_"..i
        node.temporary=true
        node.enabled=false
        self.trails[i]={volume=vol,node=node,material=material}
    end
    for i=1,8 do
        local vol=self.world:CreateVolume(1,1,1,Parts.VOXEL_SIZE,Vector3.ZERO,Quaternion())
        local grid=vol:GetGrid()
        grid:SetSolid(0,0,0,true);grid:SetVoxelMaterial(0,0,0,Builder.TRAIL_PALETTE)
        vol.destructible=false;vol.evictable=false;vol.collisionMask=0;vol.collisionLayer=0
        local material=Builder.FadeMaterial(self.world,'WeaponSquare_'..i)
        vol.material=material;vol:RebuildGeometry()
        local node=vol:GetNode();node.enabled=false;node.temporary=true
        self.particles[i]={volume=vol,node=node,material=material,age=1,position=Vector3.ZERO}
    end
end

function Rig:BuildSwordImages()
    local blueprint=self.entries.sword.mesh.blueprint
    if self.imageKey==blueprint.geometry.key then return end
    for _,image in ipairs(self.images) do self.world:RemoveVolume(image.volume);image.material:Dispose() end
    self.imageKey=blueprint.geometry.key
    local b=blueprint.bounds
    self.imageMin=Vec(b.min)
    self.trailTip=Vector3(0,blueprint.hit.length*.8,0)
    for i=1,2 do
        local d=b.dimensions
        local volume=self.world:CreateVolume(d[1],d[2],d[3],Parts.VOXEL_SIZE,Vector3.ZERO,Quaternion())
        local grid=volume:GetGrid()
        for _,cell in ipairs(blueprint.geometry.cells) do
            local x,y,z=cell.x-b.gridMin[1],cell.y-b.gridMin[2],cell.z-b.gridMin[3]
            grid:SetSolid(x,y,z,true);grid:SetVoxelMaterial(x,y,z,Builder.TRAIL_PALETTE)
        end
        volume.destructible=false;volume.evictable=false;volume.collisionMask=0;volume.collisionLayer=0
        local material=Builder.FadeMaterial(self.world,'WeaponAfterimage_'..i)
        volume.material=material;volume:RebuildGeometry()
        local node=volume:GetNode();node.enabled=false;node.temporary=true
        self.images[i]={volume=volume,node=node,material=material}
    end
end

--- Array belongs to CombatAnim and is valid until the next animation update.
--- nil selects the older eight-frame fallback; an empty array means no trail.
---@param list table?
function Rig:SetAfterimages(list)
    if (self.afterimages==nil)~=(list==nil) then self:ClearTrail() end
    self.afterimages=list
    self.afterimagesFresh=true
    self.imageElapsed=0
end

function Rig:UpdateTrailColor()
    local preset=Parts.ColorPresets[self.config[self.active].colors.accent]
    local rgb=preset.rgb
    local r,g,b=rgb[1]/255,rgb[2]/255,rgb[3]/255
    self.world:SetPaletteEntry(Builder.TRAIL_PALETTE,Color(r,g,b,1),1000)
    self.world:SetPaletteEntryPBR(Builder.TRAIL_PALETTE,0.5,0,0.5,Color(r,g,b,0.6))
end

function Rig:ClearTrail()
    self.historyCount=0
    self.particleStamp=nil
    for _,trail in ipairs(self.trails) do trail.node.enabled=false end
    for _,image in ipairs(self.images) do image.node.enabled=false end
    for _,particle in ipairs(self.particles) do particle.node.enabled=false;particle.age=1 end
end

---@param on boolean
function Rig:SetTrail(on)
    self.trailEnabled=on==true
    if not self.trailEnabled then self:ClearTrail() end
end

---@param pose string
function Rig:Attach(pose)
    local entry=self.entries[self.active]
    if pose=="hidden" then
        Builder.SetOpacity(entry.mesh,0)
    else
        local socket=self.sockets[pose=="hand" and (self.active=="sword" and "hand_right" or "hand_left") or ("back_"..self.active)]
        entry.pivot:SetParent(socket)
        entry.pivot.position=Vector3.ZERO
        entry.pivot.rotation=Quaternion()
    end
    self.attached=pose
end

---@param weapon string
---@return boolean
function Rig:SetActive(weapon)
    if self.disposed or (weapon~="sword" and weapon~="bow") then return false end
    if self.active==weapon then return true end
    Builder.SetOpacity(self.entries[self.active].mesh,0)
    self.active,self.config.active=weapon,weapon
    self.transition=nil
    self.attached="hidden"
    self.swingOffset,self.swingEuler=Vector3.ZERO,Vector3.ZERO
    self:ClearTrail()
    self:UpdateTrailColor()
    -- Swapping stows the new weapon; the combat owner may then request hand.
    local nextPose=self.pose=="hidden" and "hidden" or "back"
    self.pose="hidden"
    self:SetPose(nextPose)
    return true
end

---@param pose string hidden | back | hand
---@return boolean
function Rig:SetPose(pose)
    if self.disposed or (pose~="hidden" and pose~="back" and pose~="hand") then return false end
    if self.pose==pose then return true end
    self.pose=pose
    self:ClearTrail()
    local alpha=self.entries[self.active].mesh.alpha
    if self.attached=="hidden" and pose~="hidden" then self:Attach(pose) end
    self.transition={frame=0,fromAlpha=alpha,from=self.attached,to=pose}
    return true
end

---@param offset Vector3
---@param euler Vector3
function Rig:SetSwing(offset,euler)
    if self.disposed then return end
    self.swingOffset=offset or Vector3.ZERO
    self.swingEuler=euler or Vector3.ZERO
end

---@return table world-space hit description; length is actual geometry, unscaled by reach
function Rig:GetHit()
    local entry=self.entries[self.active]
    local hit=entry.mesh.blueprint.hit
    return {origin=entry.pivot:LocalToWorld(Vec(hit.origin)),dir=entry.pivot.worldRotation*Vec(hit.dir),
        length=hit.length,radius=hit.radius}
end

---@return table
function Rig:GetStats() return self.entries[self.active].mesh.blueprint.stats end

---@param config table single-weapon config from section 4.3
---@return boolean
function Rig:Apply(config)
    if self.disposed then return false end
    local blueprint=Builder.Compile(config)
    if not blueprint then return false end
    local weapon=blueprint.config.weapon
    local entry=self.entries[weapon]
    local mesh=Builder.Build(self.world,entry.pivot,blueprint.config,entry.mesh)
    if not mesh then return false end
    entry.mesh=mesh
    -- Persist independent mutable tables, never cached blueprint references.
    local value={parts={},colors={}}
    for k,v in pairs(blueprint.config.parts) do value.parts[k]=v end
    for k,v in pairs(blueprint.config.colors) do value.colors[k]=v end
    self.config[weapon]=value
    if weapon=='sword' then self:BuildSwordImages() end
    if weapon==self.active then self:UpdateTrailColor(); self:ClearTrail() end
    Store.Save(self.config)
    return true
end

function Rig:AdvanceTransition()
    local transition=self.transition
    if not transition then return end
    transition.frame=transition.frame+1
    local frame=transition.frame
    local entry=self.entries[self.active]
    local alpha=1
    if transition.to=="hidden" then
        alpha=transition.fromAlpha*(1-frame/FADE_FRAMES)
    elseif transition.from~=transition.to then
        if frame<=4 then
            alpha=transition.fromAlpha*(1-frame/4)
        else
            if self.attached~=transition.to then self:Attach(transition.to) end
            alpha=(frame-4)/4
        end
    else
        alpha=transition.fromAlpha+(1-transition.fromAlpha)*frame/FADE_FRAMES
    end
    Builder.SetOpacity(entry.mesh,alpha)
    if frame>=FADE_FRAMES then self:Attach(transition.to); self.transition=nil end
end

---@param entry WeaponRigEntry
---@param dt number
function Rig:UpdateImages(entry,dt)
    if self.afterimagesFresh then self.afterimagesFresh=false else self.imageElapsed=self.imageElapsed+dt end
    local first,last
    for i=1,2 do
        local shot=self.afterimages[i]
        local image=self.images[i]
        local age=shot and (shot.age or 0)+self.imageElapsed or 1
        local valid=shot and age>=0 and age<.10 and type(shot.clip)=='string'
            and shot.clip:sub(1,6)=='sword_' and (entry.pivot.worldPosition-shot.position):Length()<2
        image.node.enabled=not not valid
        if valid then
            first=first or shot;last=shot
            image.node.worldPosition=shot.position+shot.rotation*self.imageMin
            image.node.worldRotation=shot.rotation
            local alpha=math.ceil(Clamp(math.min(shot.alpha or 1,1-age/.10),0,1)*4)/4*.28
            image.material:SetShaderParameter('MatDiffColor',Variant(Color(1,1,1,alpha)))
        end
    end
    local tip=entry.pivot:LocalToWorld(self.trailTip)
    local endpoint=last and last.position+last.rotation*self.trailTip or tip
    for i,trail in ipairs(self.trails) do
        trail.node.enabled=first~=nil
        if first then
            local point=tip+(endpoint-tip)*(i/8)
            local size=Parts.VOXEL_SIZE
            trail.node.worldPosition=Vector3(math.floor(point.x/size)*size,math.floor(point.y/size)*size,math.floor(point.z/size)*size)
            trail.node.worldRotation=first.rotation
        end
    end
    if first and first.time~=self.particleStamp then
        self.particleStamp=first.time
        for _,particle in ipairs(self.particles) do particle.position=endpoint;particle.age=0 end
    end
    for i,particle in ipairs(self.particles) do
        particle.age=particle.age+dt
        particle.node.enabled=particle.age<.10
        if particle.node.enabled then
            local t=math.floor(particle.age/.025)*.025
            particle.node.worldPosition=particle.position+Vector3(((i%3)-1)*t*2,t*(i%2==0 and 1 or -1),((i%4)-1.5)*t)
            particle.material:SetShaderParameter('MatDiffColor',Variant(Color(1,1,1,math.ceil((1-particle.age/.10)*4)/16)))
        end
    end
end

---@param dt number
function Rig:Update(dt)
    if self.disposed then return end
    self:AdvanceTransition()
    local entry=self.entries[self.active]
    local body=self.body.rotation.eulerAngles
    local gain=1-math.exp(-Clamp(dt,0,0.1)*10)
    local targetPitch=Clamp(-Delta(body.x,self.previousBody.x)*0.7,-2,2)
    local targetRoll=Clamp(-Delta(body.z,self.previousBody.z)*0.7,-2,2)
    self.lag=Vector3(self.lag.x+(targetPitch-self.lag.x)*gain,0,self.lag.z+(targetRoll-self.lag.z)*gain)
    self.previousBody=body
    if self.attached=="hand" then
        entry.pivot.position=self.swingOffset
        -- Arm -90 pitches the palm forward. A +90 grip rest rotation keeps
        -- the blade/bow upright there; CombatAnim adds its authored local pose.
        entry.pivot.rotation=Quaternion(90,0,0)*Quaternion(self.swingEuler.x,self.swingEuler.y,self.swingEuler.z)
    elseif self.attached=="back" then
        entry.pivot.position=Vector3.ZERO
        entry.pivot.rotation=Quaternion(self.lag.x,0,self.lag.z)
    end
    if not self.trailEnabled or self.active~='sword' or self.pose~="hand" or self.attached~="hand" or entry.mesh.alpha<1 then
        self:ClearTrail();return
    end
    if self.afterimages~=nil then self:UpdateImages(entry,math.max(0,dt));return end
    local point=entry.pivot.worldPosition
    local previous=self.historyCount>0 and self.history[1] or nil
    -- Ignore resting jitter, and clear history across teleports (>2m/frame).
    local distance=previous and (point-previous.position):Length() or 0
    if distance>2 then self:ClearTrail(); previous=nil end
    local moving=distance>0.012 and distance<=2
    self.historyCount=math.min(TRAIL_FRAMES+1,self.historyCount+1)
    local recycled=self.history[TRAIL_FRAMES+1]
    for i=TRAIL_FRAMES+1,2,-1 do self.history[i]=self.history[i-1] end
    self.history[1]=recycled
    recycled.position,recycled.rotation,recycled.moving=point,entry.pivot.worldRotation,moving
    for i,trail in ipairs(self.trails) do
        local sample=i<self.historyCount and self.history[i+1] or nil
        trail.node.enabled=sample~=nil and sample.moving
        if sample then
            local s=Parts.VOXEL_SIZE
            local p=sample.position
            trail.node.worldPosition=Vector3(math.floor(p.x/s+0.5)*s,math.floor(p.y/s+0.5)*s,math.floor(p.z/s+0.5)*s)
                -sample.rotation*Vector3(s*0.5,0,s*0.5)
            trail.node.worldRotation=sample.rotation
        end
    end
end

function Rig:Dispose()
    if self.disposed then return end
    self.disposed=true
    for _,entry in pairs(self.entries) do Builder.Dispose(entry.mesh); entry.pivot:Remove() end
    for _,trail in ipairs(self.trails) do self.world:RemoveVolume(trail.volume); trail.material:Dispose() end
    for _,image in ipairs(self.images) do self.world:RemoveVolume(image.volume);image.material:Dispose() end
    for _,particle in ipairs(self.particles) do self.world:RemoveVolume(particle.volume);particle.material:Dispose() end
    self.sockets.back_sword:Remove()
    self.sockets.back_bow:Remove()
    self.sockets.hand_left:Remove()
    -- hand_right is controller.castSocket, owned by NomiController, never removed.
    self.trails,self.history,self.images,self.particles={},{},{},{}
    self.afterimages=nil
end
return Rig
