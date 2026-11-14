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
---@field visualState string
---@field motion table
---@field layers table
---@field bowDrawMeshes table[]
---@field bowArrow table
---@field bowDraw number
---@field bowStage integer
---@field bowArrowOffset Vector3
---@field visualKeys table
---@field visualClock number
---@field events string[]
---@field eventOutput string[]
---@field hangPosition Vector3
---@field hangVelocity Vector3
---@field hangRotation Quaternion
---@field hangReady boolean
---@field hangTarget Vector3
---@field moveTarget Vector3
---@field moveRotation Quaternion
---@field recoil number
---@field glowColors Color[]
---@field glowBucket integer
---@field arrivalFresh boolean
local Rig={}
Rig.__index=Rig
local TRAIL_SEGMENTS=8
local TRAIL_SPACING=.09 -- metres, not frames: eight 3-voxel-wide strips
local TRAIL_TAIL=.06
local FLASH_TIME=.08
local WHITE_PALETTE=174 -- reserved weapon bank, adjacent to accent slot 175
local SWORD_LENGTH,SWORD_WIDTH=1.25,1.3 -- visual only: pivot/GetHit remain unscaled
local function Vec(t) return Vector3(t[1],t[2],t[3]) end
local function Clamp(n,lo,hi) return math.max(lo,math.min(hi,n)) end
local function Delta(a,b) return (a-b+180)%360-180 end
local function SetVec(v,x,y,z) v.x=x;v.y=y;v.z=z end
local function CopyVec(to,from) SetVec(to,from.x,from.y,from.z) end
local function SpringAxis(pos,vel,goal,dt,omega,decay)
    local d=pos-goal;local c=vel+omega*d
    return goal+(d+c*dt)*decay,(vel-omega*c*dt)*decay
end
local function CopyRot(to,from) to.w=from.w;to.x=from.x;to.y=from.y;to.z=from.z end
local function Rotate(out,q,v)
    local tx,ty,tz=2*(q.y*v.z-q.z*v.y),2*(q.z*v.x-q.x*v.z),2*(q.x*v.y-q.y*v.x)
    SetVec(out,v.x+q.w*tx+q.y*tz-q.z*ty,v.y+q.w*ty+q.z*tx-q.x*tz,v.z+q.w*tz+q.x*ty-q.y*tx)
end
local function BlendRot(out,a,b,t)
    local dot=a.w*b.w+a.x*b.x+a.y*b.y+a.z*b.z
    local sign=dot<0 and -1 or 1
    dot=Clamp(math.abs(dot),0,1)
    local wa,wb=1-t,t
    if dot<.9995 then
        local angle=math.acos(dot);local sine=math.sin(angle)
        wa=math.sin((1-t)*angle)/sine;wb=math.sin(t*angle)/sine
    end
    wb=wb*sign
    local w,x,y,z=a.w*wa+b.w*wb,a.x*wa+b.x*wb,a.y*wa+b.y*wb,a.z*wa+b.z*wb
    local n=math.sqrt(w*w+x*x+y*y+z*z)
    out.w=w/n;out.x=x/n;out.y=y/n;out.z=z/n
end
local function ScaleSword(node,minimum)
    node.scale=Vector3(SWORD_WIDTH,SWORD_LENGTH,1)
    node.position=Vector3(minimum.x*SWORD_WIDTH,minimum.y*SWORD_LENGTH,minimum.z)
end
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
    self.visualState,self.visualClock,self.recoil='hidden',0,0
    self.motion={elapsed=0,duration=0,from=Vector3(),rotation=Quaternion(),output=Vector3(),outRotation=Quaternion(),
        arc=Vector3(),curve=Vector3()}
    self.events,self.eventOutput,self.layers,self.visualKeys={},{},{},{}
    self.hangPosition,self.hangVelocity,self.hangTarget,self.moveTarget=Vector3(),Vector3(),Vector3(),Vector3()
    self.hangRotation,self.moveRotation=Quaternion(),Quaternion()
    self.hangReady=false
    self.bowDraw,self.bowStage,self.bowArrowOffset=0,0,Vector3()
    self.bowDrawMeshes={}
    self.glowColors,self.glowBucket={},0
    ---@type table<string, Node>
    local bones=controller.nomi.bones
    self.body=assert(bones.body,"WeaponRig requires body bone")
    self.previousBody=self.body.rotation.eulerAngles
    local backSword=self.body:CreateChild("back_sword")
    backSword.position=Vector3(0,1.05-self.body.position.y,-.30-self.body.position.z)
    -- +35 around Z takes +Y to character-left (-X).
    backSword.rotation=Quaternion(15,0,35) -- +Z roll points +Y blade toward character-left
    local backBow=self.body:CreateChild("back_bow")
    backBow.position=Vector3(0,1.05-self.body.position.y,-.30-self.body.position.z)
    backBow.rotation=Quaternion(0,180,90) -- horizontal; convex +Z faces outward(-Z), string toward body
    -- Shared palms belong to BlockCharacter, including their mirrored calibration
    -- and arm/forearm ownership. Only our weapon_grip children apply gripRest.
    local right=assert(controller.nomi:HandSocket('right'),'WeaponRig requires calibrated right palm')
    local left=assert(controller.nomi:HandSocket('left'),'WeaponRig requires calibrated left palm')
    self.sockets={back_sword=backSword,back_bow=backBow,hand_right=right,hand_left=left}
    self.entries={}
    for _,weapon in ipairs({"sword","bow"}) do
        local pivot=self.body:CreateChild("weapon_grip_"..weapon)
        pivot.temporary=true
        local mesh=assert(Builder.Build(world,pivot,Single(self.config,weapon)))
        self.entries[weapon]={pivot=pivot,mesh=mesh}
        if weapon=='sword' then ScaleSword(mesh.node,Vec(mesh.blueprint.bounds.min)) end
        Builder.SetOpacity(mesh,0)
    end
    self:CreateTrail()
    self:BuildSwordImages()
    self:BuildBowImages()
    self:BuildVisualPools('sword');self:BuildVisualPools('bow')
    self:UpdateTrailColor()
end

local function Effect(self,w,h,name,kind)
    local vol=self.world:CreateVolume(w,h,1,Parts.VOXEL_SIZE,Vector3.ZERO,Quaternion())
    local grid=vol:GetGrid()
    for y=0,h-1 do for x=0,w-1 do
        if kind~='socket' or x==1 or y==1 then
            grid:SetSolid(x,y,0,true)
            local white=kind=='blade' or (kind=='band' and x>=1 and x<w-1) or (kind=='socket' and x==1 and y==1)
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
        if weapon=='sword' then node.scale=Vector3(SWORD_WIDTH,SWORD_LENGTH,1) end
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
    self.imageMin=Vector3(b.min[1]*SWORD_WIDTH,b.min[2]*SWORD_LENGTH,b.min[3])
    local root,tip,edge=math.huge,-math.huge,-math.huge
    for _,cell in ipairs(blueprint.geometry.cells) do
        if cell.slot=='blade' then root=math.min(root,cell.y);tip=math.max(tip,cell.y);edge=math.max(edge,cell.x) end
    end
    self.bladeRoot=Vector3(0,(root-.5)*Parts.VOXEL_SIZE*SWORD_LENGTH,0)
    self.bladeTip=Vector3(0,(tip+.5)*Parts.VOXEL_SIZE*SWORD_LENGTH,0)
    self.bladeFlashX=(edge+.5)*Parts.VOXEL_SIZE*SWORD_WIDTH
    for _,trail in ipairs(self.trails) do self.world:RemoveVolume(trail.volume);trail.material:Dispose() end
    for i=1,TRAIL_SEGMENTS do
        self.trails[i]=Effect(self,5,tip-root+1,'WeaponBand_'..i,'band') -- 0.15m wide
        self.trails[i].node.scale=Vector3(1,SWORD_LENGTH,1)
    end
    local oldFlash=self.flashes.blade
    if oldFlash then self.world:RemoveVolume(oldFlash.volume);oldFlash.material:Dispose() end
    self.flashes.blade=Effect(self,1,tip-root+1,'WeaponFullChargeFlash','blade')
    self.flashes.blade.node.scale=Vector3(1,SWORD_LENGTH,1)
    BuildSilhouettes(self,'sword',blueprint,self.images)
end

local function DisposeEffect(self,effect)
    if effect then self.world:RemoveVolume(effect.volume);effect.material:Dispose() end
end

-- Six non-overlapping horizontal slices reveal bottom-to-top without rebuilding
-- grids or animating scale. Pools resize only when the selected parts change.
function Rig:BuildVisualPools(weapon)
    local entry=self.entries[weapon]
    local bp=entry.mesh.blueprint
    if self.visualKeys[weapon]==bp.geometry.key then return end
    self.visualKeys[weapon]=bp.geometry.key
    for _,layer in ipairs(self.layers[weapon] or {}) do DisposeEffect(self,layer) end
    ---@type table[][]
    local groups={{},{},{},{},{},{}}
    local b=bp.bounds
    for _,cell in ipairs(bp.geometry.cells) do
        local index=math.min(6,math.floor((cell.y-b.gridMin[2])/b.dimensions[2]*6)+1)
        groups[index][#groups[index]+1]=cell
    end
    local layers={}
    for i=1,6 do
        local layer=Builder.VisualVolume(self.world,entry.pivot,bp,groups[i],'WeaponReveal_'..weapon..i)
        if weapon=='sword' then ScaleSword(layer.node,layer.minimum) end
        layers[i]=layer
    end
    self.layers[weapon]=layers
    if weapon=='bow' then
        for _,mesh in ipairs(self.bowDrawMeshes) do DisposeEffect(self,mesh) end
        for stage=0,2 do
            local shape=Builder.BowVisual(bp,stage)
            local mesh=Builder.VisualVolume(self.world,entry.pivot,bp,shape.cells,'BowDraw_'..stage)
            mesh.stringZ=shape.stringMidpoint[3];self.bowDrawMeshes[stage+1]=mesh
        end
        DisposeEffect(self,self.bowArrow)
        local arrow={}
        for z=0,21 do arrow[#arrow+1]={x=0,y=0,z=z,channel='secondary'} end
        for z=1,4 do
            arrow[#arrow+1]={x=-1,y=0,z=z,channel='accent'}
            arrow[#arrow+1]={x=1,y=0,z=z,channel='accent'}
        end
        local tip=assert(Parts.Get(bp.config.parts.tip))
        for iy,layer in ipairs(tip.voxels) do for iz,row in ipairs(layer) do for ix=1,#row do
            local c=row:sub(ix,ix)
            if c~='.' then arrow[#arrow+1]={x=tip.origin[1]+ix-1,y=tip.origin[3]+iz-1,z=21+iy-1,channel=tip.palette[c]} end
        end end end
        self.bowArrow=Builder.VisualVolume(self.world,entry.pivot,bp,arrow,'BowNockedArrow')
    end
end

--- Three cached draw shapes; no geometry work on this per-frame entry.
---@param p number
function Rig:SetBowDraw(p)
    if self.disposed then return end
    self.bowDraw=type(p)=='number' and p==p and Clamp(p,0,1) or 0
    self.bowStage=self.bowDraw<.25 and 0 or (self.bowDraw<.75 and 1 or 2)
end

---@param name string materialize | materialized | blade_draw | blade_sheath | dissolved
function Rig:EmitEvent(name)
    if #self.events>=8 then table.remove(self.events,1) end
    self.events[#self.events+1]=name
end

--- Borrowed string array, valid until the next PopEvents. Drain once per frame.
---@return string[]
function Rig:PopEvents()
    local output=self.eventOutput
    for i=#output,1,-1 do output[i]=nil end
    for i=1,#self.events do output[i]=self.events[i];self.events[i]=nil end
    return output
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
    self.world:SetPaletteEntryPBR(Builder.TRAIL_PALETTE,0.5,0,0.5,Color(r*1.2,g*1.2,b*1.2,0.9))
    self.world:SetPaletteEntry(WHITE_PALETTE,Color(1,1,1,1),1000)
    self.world:SetPaletteEntryPBR(WHITE_PALETTE,.5,0,.5,Color(1.3,1.3,1.3,1))
    for i=1,8 do local strength=.9+(i-1)/70;self.glowColors[i]=Color(r*strength,g*strength,b*strength,.6) end
    self.glowBucket=0
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

--- Full charge is event-only/latched; draw/sheath also fire at resolved arrival.
---@param kind string full_charge | draw | sheath
---@return boolean
function Rig:Flash(kind)
    if self.disposed or not self.trailEnabled or (kind=='full_charge' and self.active~='sword') then return false end
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
        or (kind=='draw' and self.sockets[self.active=='sword' and 'hand_right' or 'hand_left'] or self.sockets['back_'..self.active])
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
    for _,layer in ipairs(self.layers[self.active]) do layer.node.enabled=false end
    for _,mesh in ipairs(self.bowDrawMeshes) do mesh.node.enabled=false end
    self.bowArrow.node.enabled=false;self:SetBowDraw(0)
    self.active,self.config.active=weapon,weapon
    self.visualActive,self.visualCharge,self.tailLeft,self.chargeFlashed=false,nil,0,false
    self.flashLeft=0;self.flashes.blade.node.enabled=false;self.flashes.socket.node.enabled=false
    self.transition=nil
    self.visualState,self.hangReady='hidden',false
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
    local previous=self.pose
    self.pose=pose
    self:ClearTrail()
    for _,layer in ipairs(self.layers[self.active]) do layer.node.enabled=false end
    self:SetBowDraw(0)
    if pose=='hidden' then
        self:BeginMotion('dissolve',.30)
    elseif self.visualState=='hidden' then
        self:Attach('back');self.hangReady=false
        if pose=='hand' then self:BeginMotion('fly_to_hand',.08) -- direct attack cannot wait for a .30s reveal
        else self:BeginMotion('materialize',.30);self:EmitEvent('materialize') end
    elseif pose=='hand' then
        self:BeginMotion('fly_to_hand',self.visualState=='materialize' and .08 or .12)
    elseif previous=='hand' or self.visualState=='fly_to_hand' then
        self:BeginMotion('stow',.18)
    else
        self:Attach('back');self:BeginMotion('materialize',.30)
    end
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
    if self.disposed or self.pose~='hand' or self.visualState~='hand' or self.attached~='hand' then return nil,nil end
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
    if weapon=='sword' then ScaleSword(mesh.node,Vec(blueprint.bounds.min)) end
    -- Persist independent mutable tables, never cached blueprint references.
    local value={parts={},colors={}}
    for k,v in pairs(blueprint.config.parts) do value.parts[k]=v end
    for k,v in pairs(blueprint.config.colors) do value.colors[k]=v end
    self.config[weapon]=value
    if weapon=='sword' then self:BuildSwordImages() else self:BuildBowImages() end
    self:BuildVisualPools(weapon)
    if weapon==self.active then self:UpdateTrailColor(); self:ClearTrail() end
    Store.Save(self.config)
    return true
end

-- State storage and motion workspaces are reused across every transition.
function Rig:BeginMotion(state,duration)
    local m=self.motion
    m.elapsed,m.duration=0,duration
    m.visibleFrom=self.entries[self.active].mesh.alpha
    SetVec(m.arc,self.active=='sword' and .18 or -.18,.35,0)
    self.visualState,self.transition=state,m
    local pivot=self.entries[self.active].pivot
    CopyVec(m.from,pivot.worldPosition);CopyRot(m.rotation,pivot.worldRotation)
    if state=='fly_to_hand' or state=='stow' then
        pivot:SetParent(self.scene)
        pivot.worldPosition=m.from;pivot.worldRotation=m.rotation
    end
end

local function MainAlpha(self,mesh,a)
    mesh.alpha=a;mesh.node.enabled=a>0
    mesh.volume.material=a>=1 and mesh.opaque or mesh.fade
    if a>0 and a<1 then mesh.fade:SetShaderParameter('MatDiffColor',self.fxAlpha[math.floor(a*16+.5)+1]) end
end

-- Critically damped position spring (80ms time constant), capped displacement.
-- A teleport resets the spring instead of dragging a weapon across the world.
function Rig:UpdateHang(dt)
    local socket=self.sockets['back_'..self.active]
    CopyVec(self.hangTarget,socket.worldPosition)
    local target=self.hangTarget
    target.y=target.y+.02*math.sin(self.visualClock*math.pi*1.2)
    if not self.hangReady or Distance(target,self.hangPosition)>2 then
        CopyVec(self.hangPosition,target);SetVec(self.hangVelocity,0,0,0)
        CopyRot(self.hangRotation,socket.worldRotation);self.hangReady=true
    else
        local omega=25 -- critically damped lag ~2/omega = .08s
        local decay=math.exp(-omega*dt)
        local p,v=self.hangPosition,self.hangVelocity
        p.x,v.x=SpringAxis(p.x,v.x,target.x,dt,omega,decay)
        p.y,v.y=SpringAxis(p.y,v.y,target.y,dt,omega,decay)
        p.z,v.z=SpringAxis(p.z,v.z,target.z,dt,omega,decay)
        local distance=Distance(p,target)
        if distance>.12 then
            local k=.12/distance
            SetVec(p,target.x+(p.x-target.x)*k,target.y+(p.y-target.y)*k,target.z+(p.z-target.z)*k)
        end
        BlendRot(self.hangRotation,self.hangRotation,socket.worldRotation,1-math.exp(-dt/.08))
    end
    self.recoil=math.max(0,self.recoil-dt)
end

function Rig:ShowLayers(visible)
    local entry=self.entries[self.active]
    MainAlpha(self,entry.mesh,Clamp(visible/6,0,1))
    entry.mesh.node.enabled=false
    for i,layer in ipairs(self.layers[self.active]) do
        layer.node.enabled=i<=visible
        if layer.node.enabled then layer.material:SetShaderParameter('MatDiffColor',self.fxAlpha[17]) end
    end
end

function Rig:ArrivalFlash(kind)
    -- A repeated animation draw/sheath event in the same 80ms window is ignored.
    self.arrivalFresh=self:Flash(kind)
end

function Rig:AdvanceTransition(dt)
    local entry=self.entries[self.active]
    local state=self.visualState
    if state=='hang' or state=='materialize' or state=='dissolve' and entry.pivot.parent==self.sockets['back_'..self.active] then
        entry.pivot.worldPosition=self.hangPosition;entry.pivot.worldRotation=self.hangRotation
        if self.recoil>0 then
            local p=self.motion.output;CopyVec(p,self.hangPosition)
            Rotate(self.motion.curve,self.body.worldRotation,Vector3.FORWARD)
            local d=self.motion.curve;local amount=.02*math.sin((1-self.recoil/.12)*math.pi)
            SetVec(p,p.x-d.x*amount,p.y-d.y*amount,p.z-d.z*amount)
            entry.pivot.worldPosition=p
        end
    end
    local m=self.transition
    if not m then return end
    m.elapsed=math.min(m.duration,m.elapsed+dt)
    if m.duration-m.elapsed<1e-8 then m.elapsed=m.duration end
    local t=Clamp(m.elapsed/m.duration,0,1)
    if state=='materialize' or state=='dissolve' then
        local fraction=state=='materialize' and (m.visibleFrom+(1-m.visibleFrom)*t) or m.visibleFrom*(1-t)
        self:ShowLayers(math.min(6,math.floor(fraction*6+1e-7)))
        if t>=1 then
            for _,layer in ipairs(self.layers[self.active]) do layer.node.enabled=false end
            self.transition=nil
            if state=='dissolve' then
                self:Attach('hidden');self.visualState='hidden';self:EmitEvent('dissolved')
            else
                MainAlpha(self,entry.mesh,1);self:Attach('back');self.visualState='hang'
                self:EmitEvent('materialized');self:ArrivalFlash('sheath')
                if self.pose=='hand' then self:BeginMotion('fly_to_hand',.12) end
            end
        end
    elseif state=='fly_to_hand' or state=='stow' then
        local goal=self.moveTarget
        if state=='fly_to_hand' then
            local socket=self.sockets[self.active=='sword' and 'hand_right' or 'hand_left']
            CopyVec(goal,socket:LocalToWorld(self.swingOffset))
            HandRotation(self,self.poseRotation)
            CopyRot(self.moveRotation,socket.worldRotation*self.poseRotation)
        else CopyVec(goal,self.hangPosition);CopyRot(self.moveRotation,self.hangRotation) end
        local u=1-(1-t)*(1-t)
        Rotate(m.curve,self.body.worldRotation,m.arc)
        local arc=4*u*(1-u)
        SetVec(m.output,m.from.x+(goal.x-m.from.x)*u+m.curve.x*arc,
            m.from.y+(goal.y-m.from.y)*u+m.curve.y*arc,m.from.z+(goal.z-m.from.z)*u+m.curve.z*arc)
        BlendRot(m.outRotation,m.rotation,self.moveRotation,u)
        entry.pivot.worldPosition=m.output;entry.pivot.worldRotation=m.outRotation
        MainAlpha(self,entry.mesh,1)
        if t>=1 then
            self.transition=nil;self:ClearTrail()
            if state=='fly_to_hand' then
                self:Attach('hand');self.visualState='hand';self:EmitEvent('blade_draw');self:ArrivalFlash('draw')
            else
                self:Attach('back');self.visualState='hang';self.recoil=.12
                self:EmitEvent('blade_sheath');self:ArrivalFlash('sheath')
            end
        end
    end
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
    local flying=self.visualState=='fly_to_hand'
    local fade=(self.visualActive or flying) and 1 or math.ceil(Clamp(self.tailLeft/TRAIL_TAIL,0,1)*4)/4
    for i,band in ipairs(self.trails) do
        band.node.enabled=i<=math.ceil(self.sampleCount*fade) and self.sampleCount>=2 and fade>0 and (not flying or i<=4)
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
            local halfWidth,halfDepth=Parts.VOXEL_SIZE*2.5,Parts.VOXEL_SIZE*.5
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

function Rig:UpdateBowVisual()
    local drawn=self.active=='bow' and self.visualState=='hand' and self.bowDraw>.05
    for i,mesh in ipairs(self.bowDrawMeshes) do mesh.node.enabled=drawn and i==self.bowStage+1 end
    self.bowArrow.node.enabled=drawn
    if self.active=='bow' and self.visualState=='hand' then self.entries.bow.mesh.node.enabled=not drawn end
    if drawn then
        local minimum=self.bowArrow.minimum
        SetVec(self.bowArrowOffset,minimum.x+.06,minimum.y,minimum.z+self.bowDrawMeshes[self.bowStage+1].stringZ)
        self.bowArrow.node.position=self.bowArrowOffset
        self.bowArrow.material:SetShaderParameter('MatDiffColor',self.fxAlpha[17])
        self.bowDrawMeshes[self.bowStage+1].material:SetShaderParameter('MatDiffColor',self.fxAlpha[17])
    end
end

function Rig:UpdateMaterializeParticles()
    local state=self.visualState
    local visible=state=='materialize' or state=='dissolve'
    local t=visible and self.motion.elapsed/self.motion.duration or 0
    local center=self.entries[self.active].pivot.worldPosition
    for _,particle in ipairs(self.particles) do
        particle.node.enabled=visible
        if visible then
            local radius=.02+.3*(state=='materialize' and 1-t or t)
            local d=particle.direction
            SetVec(particle.position,center.x+d.x*radius,center.y+d.z*radius,center.z+d.y*radius)
            particle.node.worldPosition=particle.position
        end
    end
end

function Rig:UpdateGlow()
    if self.visualState~='hang' then return end
    local bucket=math.floor((math.sin(self.visualClock*math.pi*1.2)+1)*3.5)+1
    if bucket~=self.glowBucket then
        self.glowBucket=bucket
        self.world:SetPaletteEntryPBR(Builder.PaletteBase[self.active]+Builder.ChannelOffset.accent,.5,0,.5,self.glowColors[bucket])
    end
end

---@param dt number
function Rig:Update(dt)
    if self.disposed then return end
    dt=math.max(0,dt)
    self.visualClock=self.visualClock+dt
    self:UpdateHang(dt)
    -- W2 submits the real hit_on state before Update and performs AfterPose
    -- sweeps afterwards. Never leave its first hit using a mid-flight pivot.
    if self.visualActive and self.visualFresh and self.pose=='hand' and self.visualState=='fly_to_hand' then
        self.motion.elapsed=self.motion.duration
    end
    self:AdvanceTransition(dt)
    local entry=self.entries[self.active]
    if self.visualState=='hand' then
        entry.pivot.position=self.swingOffset
        HandRotation(self,self.poseRotation)
        entry.pivot.rotation=self.poseRotation
    end
    self:UpdateBowVisual()
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
    self:UpdateFlash(self.arrivalFresh and 0 or dt);self.arrivalFresh=false
    if not self.trailEnabled then self:ClearTrail();self.tailLeft=0;return end
    if slide and self.visualState~='hand' then return end -- interrupted flights cannot emit slide knife/particles
    if self.visualState~='hand' then
        if self.visualState=='fly_to_hand' and self.active=='sword' then
            self:SampleBlade(entry);self:DrawBands()
        else self:ClearTrail() end
        self:UpdateMaterializeParticles()
        self:UpdateGlow()
        self.tailLeft=0;return
    end
    if self.pose~='hand' or self.attached~='hand' or entry.mesh.alpha<1 then self:ClearTrail();self.tailLeft=0;return end
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
    for _,layers in pairs(self.layers) do for _,layer in ipairs(layers) do DisposeEffect(self,layer) end end
    for _,mesh in ipairs(self.bowDrawMeshes) do DisposeEffect(self,mesh) end
    DisposeEffect(self,self.bowArrow)
    for _,trail in ipairs(self.trails) do self.world:RemoveVolume(trail.volume); trail.material:Dispose() end
    for _,image in ipairs(self.images) do self.world:RemoveVolume(image.volume);image.material:Dispose() end
    for _,image in ipairs(self.bowImages) do self.world:RemoveVolume(image.volume);image.material:Dispose() end
    for _,particle in ipairs(self.particles) do self.world:RemoveVolume(particle.volume);particle.material:Dispose() end
    for _,flash in pairs(self.flashes) do self.world:RemoveVolume(flash.volume);flash.material:Dispose() end
    for _,entry in pairs(self.entries) do Builder.Dispose(entry.mesh); entry.pivot:Remove() end
    self.sockets.back_sword:Remove()
    self.sockets.back_bow:Remove()
    -- Both palms are shared character-owned nodes: never delete, move or reset
    -- them. Our weapon pivots and child flash volumes have already been removed.
    self.trails,self.samples,self.images,self.particles={},{},{},{}
    self.bowImages={}
    self.afterimages=nil
end
return Rig
