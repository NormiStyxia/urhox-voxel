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

---@class WeaponBand: WeaponTrail
---@field position Vector3
---@field rotation Quaternion
---@field xAxis Vector3
---@field yAxis Vector3
---@field zAxis Vector3

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
---@field poseRotation Quaternion
---@field swingRotation Quaternion
---@field gripRest Quaternion
---@field sampleRotation Quaternion
---@field trails WeaponBand[]
---@field samples table[] Distance-spaced blade root/tip samples, newest first.
---@field sampleCount integer
---@field distanceCarry number
---@field previousRoot Vector3
---@field previousTip Vector3
---@field sampleValid boolean
---@field visualActive boolean
---@field visualFresh boolean
---@field visualCharge number?
---@field tailLeft number
---@field chargeFlashed boolean
---@field bladeRoot Vector3
---@field bladeTip Vector3
---@field bladeFlashX number
---@field flashes table
---@field flashKind string?
---@field flashLeft number
---@field fxAlpha Variant[]
---@field afterimages table? Borrowed animation array, never copied or modified.
---@field afterimagesFresh boolean
---@field imageElapsed number
---@field images WeaponTrail[]
---@field bowImages WeaponTrail[]
---@field bowImageMin Vector3
---@field bowImageKey string
---@field particles table[]
---@field imageMin Vector3
---@field imageKey string
---@field trailEnabled boolean
---@field disposed boolean
local Rig={}
Rig.__index=Rig
local TRAIL_SEGMENTS=8
local TRAIL_SPACING=.09 -- metres, not frames: eight 3-voxel-wide strips
local TRAIL_TAIL=.06
local FLASH_TIME=.08
local WHITE_PALETTE=174 -- reserved weapon bank, adjacent to accent slot 175
local FADE_FRAMES=8
local function Vec(t) return Vector3(t[1],t[2],t[3]) end
local function Clamp(n,lo,hi) return math.max(lo,math.min(hi,n)) end
local function Delta(a,b) return (a-b+180)%360-180 end
local function SetVec(v,x,y,z) v.x=x;v.y=y;v.z=z end
local function CopyVec(to,from) SetVec(to,from.x,from.y,from.z) end
local function Distance(a,b) local x,y,z=a.x-b.x,a.y-b.y,a.z-b.z;return math.sqrt(x*x+y*y+z*z) end
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
    self.lag=Vector3()
    self.poseRotation,self.swingRotation,self.gripRest=Quaternion(),Quaternion(),Quaternion(90,0,0)
    self.sampleRotation=Quaternion()
    self.trails,self.samples,self.images,self.particles={},{},{},{}
    self.bowImages={}
    self.sampleCount,self.imageElapsed,self.distanceCarry=0,0,0
    self.previousRoot,self.previousTip=Vector3(),Vector3()
    self.sampleValid,self.visualActive,self.visualFresh=false,false,false
    self.tailLeft,self.flashLeft,self.chargeFlashed=0,0,false
    self.flashes,self.fxAlpha={},{}
    for i=0,16 do self.fxAlpha[i+1]=Variant(Color(1,1,1,i/16)) end
    for i=1,TRAIL_SEGMENTS do self.samples[i]={root=Vector3(),tip=Vector3(),tangent=Vector3()} end
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
    self:BuildBowImages()
    self:UpdateTrailColor()
end

local function Effect(self,w,h,name,kind)
    local vol=self.world:CreateVolume(w,h,1,Parts.VOXEL_SIZE,Vector3.ZERO,Quaternion())
    local grid=vol:GetGrid()
    for y=0,h-1 do for x=0,w-1 do
        if kind~='socket' or x==1 or y==1 then
            grid:SetSolid(x,y,0,true)
            local white=kind=='blade' or (kind=='band' and x==1) or (kind=='socket' and x==1 and y==1)
            grid:SetVoxelMaterial(x,y,0,white and WHITE_PALETTE or Builder.TRAIL_PALETTE)
        end
    end end
    vol.destructible=false;vol.evictable=false;vol.collisionMask=0;vol.collisionLayer=0
    -- Solid pixel ribbons/charge grains do not accumulate alpha where the blade
    -- fans around its root. Only silhouettes and the event flash are translucent.
    local opaque=kind=='band' or kind=='particle'
    local material=opaque and self.world:GetPaletteMaterial():Clone(name) or Builder.FadeMaterial(self.world,name)
    if opaque then
        local technique=material:GetTechnique(0):Clone(name..'Technique')
        technique:RemovePass('shadow')
        material:SetTechnique(0,technique)
        material:SetShaderParameter('VoxelJitter',Variant(0.0))
        material:SetShaderParameter('MatDiffColor',self.fxAlpha[17])
    end
    vol.material=material;vol:RebuildGeometry()
    local node=vol:GetNode();node.enabled=false;node.temporary=true;node.name=name
    return {volume=vol,node=node,material=material,position=Vector3(),rotation=Quaternion(),
        xAxis=Vector3(),yAxis=Vector3(),zAxis=Vector3(),offset=Vector3()}
end

function Rig:CreateTrail()
    -- All nodes/materials and alpha Variants are allocated once, outside combat.
    for i=1,6 do
        local particle=Effect(self,1,1,'WeaponCharge_'..i,'particle')
        local angle=(i-1)*math.pi/3
        particle.direction=Vector3(math.cos(angle),.35*math.sin(angle*2),math.sin(angle))
        self.particles[i]=particle
    end
    self.flashes.socket=Effect(self,3,3,'WeaponSocketFlash','socket')
end

local function BuildSilhouettes(self,weapon,blueprint,pool)
    for _,image in ipairs(pool) do self.world:RemoveVolume(image.volume);image.material:Dispose() end
    local b=blueprint.bounds
    for i=1,2 do
        local d=b.dimensions
        local volume=self.world:CreateVolume(d[1],d[2],d[3],Parts.VOXEL_SIZE,Vector3.ZERO,Quaternion())
        local grid=volume:GetGrid()
        for _,cell in ipairs(blueprint.geometry.cells) do
            local x,y,z=cell.x-b.gridMin[1],cell.y-b.gridMin[2],cell.z-b.gridMin[3]
            grid:SetSolid(x,y,z,true);grid:SetVoxelMaterial(x,y,z,Builder.TRAIL_PALETTE)
        end
        volume.destructible=false;volume.evictable=false;volume.collisionMask=0;volume.collisionLayer=0
        local material=Builder.FadeMaterial(self.world,'WeaponAfterimage_'..weapon..'_'..i)
        volume.material=material;volume:RebuildGeometry()
        local node=volume:GetNode();node.enabled=false;node.temporary=true
        pool[i]={volume=volume,node=node,material=material}
    end
end

function Rig:BuildBowImages()
    local blueprint=self.entries.bow.mesh.blueprint
    if self.bowImageKey==blueprint.geometry.key then return end
    self.bowImageKey=blueprint.geometry.key;self.bowImageMin=Vec(blueprint.bounds.min)
    BuildSilhouettes(self,'bow',blueprint,self.bowImages)
end

function Rig:BuildSwordImages()
    local blueprint=self.entries.sword.mesh.blueprint
    if self.imageKey==blueprint.geometry.key then return end
    self.imageKey=blueprint.geometry.key
    local b=blueprint.bounds
    self.imageMin=Vec(b.min)
    local root,tip,edge=math.huge,-math.huge,-math.huge
    for _,cell in ipairs(blueprint.geometry.cells) do
        if cell.slot=='blade' then root=math.min(root,cell.y);tip=math.max(tip,cell.y);edge=math.max(edge,cell.x) end
    end
    self.bladeRoot=Vector3(0,(root-.5)*Parts.VOXEL_SIZE,0)
    self.bladeTip=Vector3(0,(tip+.5)*Parts.VOXEL_SIZE,0)
    self.bladeFlashX=(edge+.5)*Parts.VOXEL_SIZE -- outside the opaque blade, not buried in it
    for _,trail in ipairs(self.trails) do self.world:RemoveVolume(trail.volume);trail.material:Dispose() end
    for i=1,TRAIL_SEGMENTS do self.trails[i]=Effect(self,3,tip-root+1,'WeaponBand_'..i,'band') end
    local oldFlash=self.flashes.blade
    if oldFlash then self.world:RemoveVolume(oldFlash.volume);oldFlash.material:Dispose() end
    self.flashes.blade=Effect(self,1,tip-root+1,'WeaponFullChargeFlash','blade')
    BuildSilhouettes(self,'sword',blueprint,self.images)
end

--- Array belongs to CombatAnim and is valid until the next animation update.
--- nil omits silhouettes; the distance-sampled band still follows active input.
---@param list table?
function Rig:SetAfterimages(list)
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
    self.world:SetPaletteEntry(WHITE_PALETTE,Color(1,1,1,1),1000)
    self.world:SetPaletteEntryPBR(WHITE_PALETTE,.5,0,.5,Color(1,1,1,.5))
end

function Rig:ClearTrail()
    self.sampleCount,self.distanceCarry,self.sampleValid=0,0,false
    for _,trail in ipairs(self.trails) do trail.node.enabled=false end
    for _,image in ipairs(self.images) do image.node.enabled=false end
    for _,image in ipairs(self.bowImages) do image.node.enabled=false end
    for _,particle in ipairs(self.particles) do particle.node.enabled=false end
end

---@param on boolean
function Rig:SetTrail(on)
    self.trailEnabled=on==true
    if not self.trailEnabled then
        self:ClearTrail();self.flashLeft=0
        self.tailLeft=0;self.visualActive=false;self.visualCharge=nil;self.chargeFlashed=false
        self.flashes.blade.node.enabled=false;self.flashes.socket.node.enabled=false
    end
end

--- Called each frame by the combat owner; no pose/motion inference.
---@param active boolean Actual sword hit_on..hit_off interval.
---@param charge number? Only sword_heavy_charge; nil outside that clip.
function Rig:SetCombatVisual(active,charge)
    if self.disposed then return end
    active=active==true
    if active and not self.visualActive then self:ClearTrail() end
    if self.visualActive and not active then self.tailLeft=TRAIL_TAIL end
    if charge==nil and self.visualCharge~=nil then self.chargeFlashed=false end
    self.visualActive,self.visualFresh=active,true
    self.visualCharge=type(charge)=='number' and charge==charge and Clamp(charge,0,1) or nil
end

--- Events only: SetPose never triggers a flash, and full charge is latched.
---@param kind string full_charge | draw | sheath
---@return boolean
function Rig:Flash(kind)
    if self.disposed or not self.trailEnabled or self.active~='sword' then return false end
    for i=1,2 do
        local shot=self.afterimages and self.afterimages[i]
        if shot and shot.clip=='dodge_slide' then return false end
    end
    if kind~='full_charge' and kind~='draw' and kind~='sheath' then return false end
    if kind=='full_charge' and self.chargeFlashed then return false end
    if self.flashLeft>0 and self.flashKind==kind then return false end
    if kind=='full_charge' then self.chargeFlashed=true end
    self.flashes.blade.node.enabled=false;self.flashes.socket.node.enabled=false
    self.images[2].node.enabled=false
    self.flashKind,self.flashLeft=kind,FLASH_TIME
    local flash=kind=='full_charge' and self.flashes.blade or self.flashes.socket
    local parent=kind=='full_charge' and self.entries.sword.pivot
        or (kind=='draw' and self.sockets.hand_right or self.sockets.back_sword)
    flash.node:SetParent(parent);flash.node.rotation=flash.rotation
    local size=Parts.VOXEL_SIZE
    SetVec(flash.offset,kind=='full_charge' and self.bladeFlashX or -1.5*size,
        kind=='full_charge' and self.bladeRoot.y or -1.5*size,-.5*size)
    flash.node.position=flash.offset;flash.node.enabled=true
    flash.material:SetShaderParameter('MatDiffColor',self.fxAlpha[13])
    return true
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
    self.visualActive,self.visualCharge,self.tailLeft,self.chargeFlashed=false,nil,0,false
    self.flashLeft=0;self.flashes.blade.node.enabled=false;self.flashes.socket.node.enabled=false
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

---@param self WeaponRig
---@param out Quaternion
local function HandRotation(self,out)
    self.swingRotation:FromEulerAngles(self.swingEuler.x,self.swingEuler.y,self.swingEuler.z)
    local a,b=self.gripRest,self.swingRotation
    out.w=a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z
    out.x=a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y
    out.y=a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x
    out.z=a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w
end

---@param offset Vector3
---@param euler Vector3
function Rig:SetSwing(offset,euler)
    if self.disposed then return end
    self.swingOffset=offset or Vector3.ZERO
    self.swingEuler=euler or Vector3.ZERO
end

--- Current bones + latest SetSwing, without advancing Update or mutating nodes.
--- Call SetSwing with this frame's animation result BEFORE sampling this port.
--- Returned world-space values remain independent of the next sample.
---@return Vector3? position nil when not held in hand / disposed
---@return Quaternion? rotation
function Rig:GetAfterimagePose()
    if self.disposed or self.pose~='hand' or self.attached~='hand' then return nil,nil end
    local socket=self.sockets[self.active=='sword' and 'hand_right' or 'hand_left']
    HandRotation(self,self.sampleRotation)
    return socket:LocalToWorld(self.swingOffset),socket.worldRotation*self.sampleRotation
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
    if weapon=='sword' then self:BuildSwordImages() else self:BuildBowImages() end
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

-- Alpha Variants, samples and vector workspaces are pooled outside the FX update.
local function Alpha(self,effect,value)
    effect.material:SetShaderParameter('MatDiffColor',self.fxAlpha[math.floor(Clamp(value,0,1)*16+.5)+1])
end

function Rig:RecordSample(rx,ry,rz,tx,ty,tz,dx,dy,dz)
    local recycled=self.samples[TRAIL_SEGMENTS]
    for i=TRAIL_SEGMENTS,2,-1 do self.samples[i]=self.samples[i-1] end
    self.samples[1]=recycled
    SetVec(recycled.root,rx,ry,rz);SetVec(recycled.tip,tx,ty,tz);SetVec(recycled.tangent,dx,dy,dz)
    self.sampleCount=math.min(TRAIL_SEGMENTS,self.sampleCount+1)
end

---@param entry WeaponRigEntry
function Rig:SampleBlade(entry)
    local root=entry.pivot:LocalToWorld(self.bladeRoot)
    local tip=entry.pivot:LocalToWorld(self.bladeTip)
    local previousRoot,previousTip=self.previousRoot,self.previousTip
    local distance=self.sampleValid and math.max(Distance(root,previousRoot),Distance(tip,previousTip)) or 0
    local bend=(tip.x-root.x)*(previousTip.x-previousRoot.x)
        +(tip.y-root.y)*(previousTip.y-previousRoot.y)+(tip.z-root.z)*(previousTip.z-previousRoot.z)
    if distance>2 or (self.sampleValid and bend<0) then self:ClearTrail() end
    if not self.sampleValid then
        self:RecordSample(root.x,root.y,root.z,tip.x,tip.y,tip.z,0,0,0)
        self.sampleValid=true
    elseif distance>1e-9 then
        local rx,ry,rz=root.x-previousRoot.x,root.y-previousRoot.y,root.z-previousRoot.z
        local tx,ty,tz=tip.x-previousTip.x,tip.y-previousTip.y,tip.z-previousTip.z
        local step=TRAIL_SPACING-self.distanceCarry
        while step<=distance+1e-9 do
            local t=math.min(1,step/distance)
            self:RecordSample(previousRoot.x+rx*t,previousRoot.y+ry*t,previousRoot.z+rz*t,
                previousTip.x+tx*t,previousTip.y+ty*t,previousTip.z+tz*t,(rx+tx)*.5,(ry+ty)*.5,(rz+tz)*.5)
            step=step+TRAIL_SPACING
        end
        self.distanceCarry=(self.distanceCarry+distance)%TRAIL_SPACING
        if self.distanceCarry>TRAIL_SPACING-1e-9 then self.distanceCarry=0 end
    end
    CopyVec(previousRoot,root);CopyVec(previousTip,tip)
end

function Rig:DrawBands()
    local fade=self.visualActive and 1 or math.ceil(Clamp(self.tailLeft/TRAIL_TAIL,0,1)*4)/4
    for i,band in ipairs(self.trails) do
        band.node.enabled=i<=math.ceil(self.sampleCount*fade) and self.sampleCount>=2 and fade>0
        if band.node.enabled then
            local sample=self.samples[i]
            local x,y,z=band.xAxis,band.yAxis,band.zAxis
            SetVec(y,sample.tip.x-sample.root.x,sample.tip.y-sample.root.y,sample.tip.z-sample.root.z)
            local length=math.sqrt(y.x*y.x+y.y*y.y+y.z*y.z)
            SetVec(y,y.x/length,y.y/length,y.z/length)
            local d=sample.tangent
            local dot=d.x*y.x+d.y*y.y+d.z*y.z
            SetVec(x,d.x-dot*y.x,d.y-dot*y.y,d.z-dot*y.z)
            length=math.sqrt(x.x*x.x+x.y*x.y+x.z*x.z)
            if length<1e-6 then
                if math.abs(y.x)<.9 then SetVec(x,1-y.x*y.x,-y.x*y.y,-y.x*y.z)
                else SetVec(x,-y.z*y.x,-y.z*y.y,1-y.z*y.z) end
                length=math.sqrt(x.x*x.x+x.y*x.y+x.z*x.z)
            end
            SetVec(x,x.x/length,x.y/length,x.z/length)
            SetVec(z,x.y*y.z-x.z*y.y,x.z*y.x-x.x*y.z,x.x*y.y-x.y*y.x)
            band.rotation:FromAxes(x,y,z)
            local halfWidth,halfDepth=Parts.VOXEL_SIZE*1.5,Parts.VOXEL_SIZE*.5
            SetVec(band.position,sample.root.x-x.x*halfWidth-z.x*halfDepth,
                sample.root.y-x.y*halfWidth-z.y*halfDepth,sample.root.z-x.z*halfWidth-z.z*halfDepth)
            band.node.worldPosition=band.position;band.node.worldRotation=band.rotation
            -- White centre/accent edges share one solid mesh. Tail recedes in
            -- four discrete steps rather than stacking transparent full-blade strips.
        end
    end
end

---@param entry WeaponRigEntry
---@param dt number
---@param slide boolean?
function Rig:UpdateImages(entry,dt,slide)
    -- Event flash + one silhouette, or up to two silhouettes without the flash.
    -- Also retain only one silhouette over the band for a clean swing outline.
    local limit=slide and 2 or ((self.sampleCount>=2 or self.flashLeft>0) and 1 or 2)
    local pool=self.active=='sword' and self.images or self.bowImages
    local other=self.active=='sword' and self.bowImages or self.images
    local minimum=self.active=='sword' and self.imageMin or self.bowImageMin
    for i=1,2 do
        local shot=self.afterimages and self.afterimages[i]
        local image=pool[i]
        other[i].node.enabled=false
        local age=shot and (shot.age or 0)+self.imageElapsed or 1
        local life=slide and math.min(.08,math.max(0,shot and shot.life or .08)) or .10
        local clipOK=shot and type(shot.clip)=='string' and (slide and shot.clip=='dodge_slide'
            or not slide and self.active=='sword' and shot.clip:sub(1,6)=='sword_')
        local valid=i<=limit and clipOK and age>=0 and age<life-1e-8 and Distance(entry.pivot.worldPosition,shot.position)<2
        image.node.enabled=not not valid
        if valid then
            image.node.worldPosition=shot.position+shot.rotation*minimum
            image.node.worldRotation=shot.rotation
            local tail=(slide or self.visualActive) and 1 or Clamp(self.tailLeft/TRAIL_TAIL,0,1)
            Alpha(self,image,Clamp(math.min(shot.alpha or 1,1-age/life),0,1)*.25*tail)
        end
    end
end

---@param entry WeaponRigEntry
function Rig:UpdateCharge(entry)
    local charge=self.visualCharge
    for _,particle in ipairs(self.particles) do
        particle.node.enabled=charge~=nil and charge<1 and not self.visualActive
        if particle.node.enabled then
            local radius=.24*(1-charge)+.015
            local d=particle.direction
            SetVec(particle.offset,d.x*radius,self.bladeRoot.y+d.y*radius,d.z*radius)
            local point=entry.pivot:LocalToWorld(particle.offset)
            local half=Parts.VOXEL_SIZE*.5
            SetVec(particle.position,point.x-half,point.y-half,point.z-half)
            particle.node.worldPosition=particle.position
        end
    end
end

---@param dt number
function Rig:UpdateFlash(dt)
    self.flashLeft=math.max(0,self.flashLeft-dt)
    if self.flashLeft<1e-8 then self.flashLeft=0 end
    local flash=self.flashKind=='full_charge' and self.flashes.blade or self.flashes.socket
    if self.flashLeft<=0 then flash.node.enabled=false;return end
    Alpha(self,flash,math.ceil(self.flashLeft/FLASH_TIME*4)/4*.75)
end

---@param dt number
function Rig:Update(dt)
    if self.disposed then return end
    dt=math.max(0,dt)
    self:AdvanceTransition()
    local entry=self.entries[self.active]
    local body=self.body.rotation.eulerAngles
    local gain=1-math.exp(-Clamp(dt,0,0.1)*10)
    local targetPitch=Clamp(-Delta(body.x,self.previousBody.x)*0.7,-2,2)
    local targetRoll=Clamp(-Delta(body.z,self.previousBody.z)*0.7,-2,2)
    SetVec(self.lag,self.lag.x+(targetPitch-self.lag.x)*gain,0,self.lag.z+(targetRoll-self.lag.z)*gain)
    self.previousBody=body
    if self.attached=="hand" then
        entry.pivot.position=self.swingOffset
        HandRotation(self,self.poseRotation)
        entry.pivot.rotation=self.poseRotation
    elseif self.attached=="back" then
        entry.pivot.position=Vector3.ZERO
        self.poseRotation:FromEulerAngles(self.lag.x,0,self.lag.z)
        entry.pivot.rotation=self.poseRotation
    end
    if not self.visualFresh then self:SetCombatVisual(false,nil) end
    self.visualFresh=false
    self.tailLeft=self.visualActive and TRAIL_TAIL or math.max(0,self.tailLeft-dt)
    if self.tailLeft<1e-8 then self.tailLeft=0 end
    if self.afterimagesFresh then self.afterimagesFresh=false else self.imageElapsed=self.imageElapsed+dt end
    local slide=false
    for i=1,2 do
        local shot=self.afterimages and self.afterimages[i]
        if shot and shot.clip=='dodge_slide' then slide=true;break end
    end
    if slide then
        self:ClearTrail();self.tailLeft=0;self.visualActive=false;self.visualCharge=nil;self.chargeFlashed=false
        self.flashLeft=0;self.flashes.blade.node.enabled=false;self.flashes.socket.node.enabled=false
    end
    self:UpdateFlash(dt)
    if not self.trailEnabled or self.pose~="hand" or self.attached~="hand" or entry.mesh.alpha<1 then
        self:ClearTrail();self.tailLeft=0;return
    end
    if slide then self:UpdateImages(entry,dt,true);return end
    if self.active~='sword' then self:ClearTrail();self.tailLeft=0;return end
    if self.visualActive or self.tailLeft>0 then
        if self.visualActive then self:SampleBlade(entry) end
        self:DrawBands();self:UpdateImages(entry,dt)
    else self:ClearTrail() end
    self:UpdateCharge(entry)
end

function Rig:Dispose()
    if self.disposed then return end
    self.disposed=true
    for _,entry in pairs(self.entries) do Builder.Dispose(entry.mesh); entry.pivot:Remove() end
    for _,trail in ipairs(self.trails) do self.world:RemoveVolume(trail.volume); trail.material:Dispose() end
    for _,image in ipairs(self.images) do self.world:RemoveVolume(image.volume);image.material:Dispose() end
    for _,image in ipairs(self.bowImages) do self.world:RemoveVolume(image.volume);image.material:Dispose() end
    for _,particle in ipairs(self.particles) do self.world:RemoveVolume(particle.volume);particle.material:Dispose() end
    for _,flash in pairs(self.flashes) do self.world:RemoveVolume(flash.volume);flash.material:Dispose() end
    self.sockets.back_sword:Remove()
    self.sockets.back_bow:Remove()
    self.sockets.hand_left:Remove()
    -- hand_right is controller.castSocket, owned by NomiController, never removed.
    self.trails,self.samples,self.images,self.particles={},{},{},{}
    self.bowImages={}
    self.afterimages=nil
end
return Rig
