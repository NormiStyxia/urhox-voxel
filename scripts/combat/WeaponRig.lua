-- Nomi's weapon sockets and visual motion. CombatAnim owns attack timing/poses.
-- All volumes are visual-only. No Finalize, collision or gameplay damage calls.
local Builder=require("combat.WeaponBuilder")
local WingVisual=require("combat.WingSwordVisual")
local ThornVisual=require("combat.ThornBowVisual")
local Catalog=require("combat.WeaponCatalog")
local Store=require("combat.WeaponStore")

---@class WeaponRigEntry
---@field pivot Node
---@field mesh WeaponMesh
---@field wing table?
---@field wingTip number?

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
---@field wingGlow number?
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
---@field trailColors table
---@field arrivalFresh boolean
---@field retiring table Reused outgoing visual snapshot; never gameplay active.
---@field hangForward Vector3
local Rig={}
Rig.__index=Rig
local TRAIL_SEGMENTS=8
local TRAIL_SPACING=.09 -- metres, not frames: eight 3-voxel-wide strips
local TRAIL_TAIL=.06
local FLASH_TIME=.08
local WHITE_PALETTE=174 -- reserved weapon bank, adjacent to accent slot 175
local SWORD_LENGTH,SWORD_WIDTH=1.25,1.3 -- visual only: pivot/GetHit remain unscaled
local REVEAL_TIME,HIDE_TIME,SWAP_HALF=.16,.12,.08
local HOLO_OUT,HOLO_IN=.30,.40 -- wing sword projection: slower dissolve / back-socket reform
local BACK_DEPTH=-.50 -- ~.34m behind torso back; clearance also covers hair/coat and lag
local MAX_HANG_ANGLE=math.rad(5)
local function Vec(t) return Vector3(t[1],t[2],t[3]) end
local function Clamp(n,lo,hi) return math.max(lo,math.min(hi,n)) end
local function Delta(a,b) return (a-b+180)%360-180 end
-- Native Vector3 is a value, unlike Quaternion userdata. Every caller must
-- assign the returned value back to its table/property (mock tables hid this).
local function SetVec(v,x,y,z) v.x=x;v.y=y;v.z=z;return v end
local function CopyVec(to,from) return SetVec(to,from.x,from.y,from.z) end
local function SpringAxis(pos,vel,goal,dt,omega,decay)
    local d=pos-goal;local c=vel+omega*d
    return goal+(d+c*dt)*decay,(vel-omega*c*dt)*decay
end
local function CopyRot(to,from) to.w=from.w;to.x=from.x;to.y=from.y;to.z=from.z end
local function Rotate(out,q,v)
    local tx,ty,tz=2*(q.y*v.z-q.z*v.y),2*(q.z*v.x-q.x*v.z),2*(q.x*v.y-q.y*v.x)
    return SetVec(out,v.x+q.w*tx+q.y*tz-q.z*ty,v.y+q.w*ty+q.z*tx-q.x*tz,v.z+q.w*tz+q.x*ty-q.y*tx)
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
    return {weapon=weapon,appearance=config[weapon].appearance,colors=config[weapon].colors}
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
    -- Dedicated visual-only impulse: mesh child, never gameplay pivot/socket.
    self.hitRotation,self.hitOffset=Quaternion(),Vector3()
    self.hitPosition=Vector3()
    self.hitAt,self.hitStop,self.hitWhite,self.hitAngle=-math.huge,0,0,0
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
    self.hangForward=Vector3()
    self.retiring={weapon=nil,elapsed=0,alpha=0,layerMask=0,bowStage=0,arrow=false,position=Vector3(),rotation=Quaternion()}
    self.hangReady=false
    self.bowDraw,self.bowStage,self.bowArrowOffset=0,0,Vector3()
    self.bowDrawMeshes={}
    self.glowColors,self.glowBucket,self.trailColors={},0,{}
    ---@type table<string, Node>
    local bones=controller.nomi.bones
    self.body=assert(bones.body,"WeaponRig requires body bone")
    self.previousBody=self.body.rotation.eulerAngles
    local backSword=self.body:CreateChild("back_sword")
    backSword.position=Vector3(.12,1.18-self.body.position.y,BACK_DEPTH-self.body.position.z)
    -- Actual blade axis is +Y. Rz(165): +Y=(-sin15,-cos15,0),
    -- so the point hangs down-left and the negative-Y handle points up-right.
    backSword.rotation=Quaternion(0,0,165)
    local backBow=self.body:CreateChild("back_bow")
    backBow.position=Vector3(0,.86-self.body.position.y,BACK_DEPTH-self.body.position.z)
    -- Ry(180)*Rz(35): +Y=(sin35,cos35,0), +Z=(0,0,-1).
    -- 35deg from vertical; the model's -Z string faces the character's +Z.
    backBow.rotation=Quaternion(0,180,35)
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
        if weapon=='sword' then self:AttachWing(self.entries.sword) end
    end
    self.combatFx=require("combat.CombatFx").New(scene,world)
    self.slashRibbon=require("combat.SlashRibbon").New(scene)
    self.shockBurst=require("combat.ShockBurst").New(scene)
    self:CreateTrail()
    self:BuildSwordImages()
    self:BuildBowImages()
    self:BuildVisualPools('sword');self:BuildVisualPools('bow')
    self:AttachThorn(self.entries.bow)
    self:PrepareTrailColor('sword');self:PrepareTrailColor('bow')
    self:UpdateTrailColor()
end

local function Effect(self,w,h,name,kind)
    local vol=self.world:CreateVolume(w,h,1,Catalog.VOXEL_SIZE,Vector3.ZERO,Quaternion())
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
        local volume=self.world:CreateVolume(d[1],d[2],d[3],Catalog.VOXEL_SIZE,Vector3.ZERO,Quaternion())
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
        if cell.region=='blade' then root=math.min(root,cell.y);tip=math.max(tip,cell.y);edge=math.max(edge,cell.x) end
    end
    self.bladeRoot=Vector3(0,(root-.5)*Catalog.VOXEL_SIZE*SWORD_LENGTH,0)
    self.bladeTip=Vector3(0,(tip+.5)*Catalog.VOXEL_SIZE*SWORD_LENGTH,0)
    self.bladeFlashX=(edge+.5)*Catalog.VOXEL_SIZE*SWORD_WIDTH
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
-- grids or animating scale. Pools resize only when the appearance changes.
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
            local limbs={}
            for _,cell in ipairs(shape.cells) do if cell.feature~='string' then limbs[#limbs+1]=cell end end
            local mesh=Builder.VisualVolume(self.world,entry.pivot,bp,limbs,'BowDraw_'..stage)
            mesh.stringZ=shape.stringMidpoint[3];mesh.nockZ=shape.nockZ;self.bowDrawMeshes[stage+1]=mesh
        end
        DisposeEffect(self,self.bowArrow)
        local arrow=Builder.NockedArrow(bp)
        self.bowArrow=Builder.VisualVolume(self.world,entry.pivot,bp,arrow,'BowNockedArrow')
        self.arrowTip=0
        for _,cell in ipairs(arrow) do self.arrowTip=math.max(self.arrowTip,(cell.z+.5)*.03) end
        for _,mesh in ipairs(self.bowStrings or {}) do DisposeEffect(self,mesh) end
        self.bowStrings={}
        for i=1,2 do
            local mesh=Builder.VisualVolume(self.world,entry.pivot,bp,{{x=0,y=0,z=0,channel='accent'}},'BowString_'..i)
            self.bowStrings[i]=mesh
        end
        self.bowHalfHeight=Catalog.Definitions.bow.halfHeight
        -- Twelve complete arrows are rebuilt only on idle equipment geometry change.
        for _,mesh in ipairs(self.flightArrows or {}) do DisposeEffect(self,mesh);mesh.root:Remove() end
        self.flightArrows={}
        for i=1,12 do
            local root=self.scene:CreateChild('BowFlight_'..i)
            local mesh=Builder.VisualVolume(self.world,root,bp,arrow,'BowFlightGeometry_'..i)
            mesh.root,mesh.tip=root,self.arrowTip
            mesh.node.position=mesh.minimum-Vector3(0,0,self.arrowTip)
            root.enabled=false;mesh.node.enabled=true
            self.flightArrows[i]=mesh
        end
    end
end

--- Three cached draw shapes; no geometry work on this per-frame entry.
---@param p number
function Rig:SetBowDraw(p)
    if self.disposed then return end
    self.bowDraw=self.pose=='hand' and type(p)=='number' and p==p and Clamp(p,0,1) or 0
    self.bowStage=self.bowDraw<.65 and 0 or (self.bowDraw<.90 and 1 or 2)
end

function Rig:GetBowNockLocal(u)
    u=Clamp(u or self.bowDraw,0,1)
    local z=u<=.5 and -.36*u or -.18-.34*(u-.5)
    return Vector3(0,self.entries.bow.mesh.blueprint.hit.origin[2],z)
end

function Rig:GetBowArrowTip()
    local launch=self.entries.bow.mesh.blueprint.hit.origin
    local nock=self:GetBowNockLocal()
    return self.entries.bow.pivot:LocalToWorld(Vector3(launch[1],launch[2],nock.z+self.arrowTip))
end

-- With grip/rotation this evaluates this frame's target BEFORE rig rendering;
-- without them returns the rendered world point, for debug/launch checks.
function Rig:GetBowNock(u,grip,rotation)
    local localPoint=self:GetBowNockLocal(u)
    if grip and rotation then return grip+rotation*localPoint end
    return self.entries.bow.pivot:LocalToWorld(localPoint)
end

function Rig:ReleaseBow()
    self.bowReleaseAt=self.visualClock
    self.bowDraw=0;self.bowStage=0
    self:UpdateBowVisual()
end

function Rig:CancelBow()
    self.bowReleaseAt=nil
    self.bowDraw,self.bowStage=0,0
    self:UpdateBowVisual()
end

function Rig:FlashBowFull()
    if self.active~='bow' or self.pose~='hand' or not self.trailEnabled then return end
    -- Reuse the arrival spark's existing geometry/material; no full-body shake.
    local flash=self.flashes.socket
    self.flashKind,self.flashLeft='bow_full',.08
    flash.node:SetParent(self.entries.bow.pivot)
    flash.node.rotation=Quaternion()
    flash.node.position=self:GetBowNockLocal(1)-Vector3(.045,.045,.015)
    flash.node.enabled=true
    flash.material:SetShaderParameter('MatDiffColor',self.fxAlpha[13])
end

function Rig:DrawArrow(p,visible)
    local mesh=self.flightArrows and self.flightArrows[p.index]
    if not mesh then return end
    mesh.root.enabled=visible
    if not visible then return end
    local direction=p.vel:LengthSquared()>.01 and p.vel:Normalized() or Vector3.FORWARD
    mesh.root.position=(p.embedded and p.pos or p.renderPos or p.pos)
    mesh.root:SetDirection(direction)
    local shake=p.embedded and p.age<.35 and 4*math.sin(p.age*math.pi*14)*2^(-p.age/.1) or 0
    mesh.node.rotation=Quaternion(shake,0,0)
    mesh.node.position=mesh.node.rotation*(mesh.minimum-Vector3(0,0,mesh.tip))
    local alpha=p.embedded and p.age>.7 and (p.age>.75 and 0 or .5) or 1
    mesh.material:SetShaderParameter('MatDiffColor',self.fxAlpha[math.floor(alpha*16)+1])
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
    if self.disposed or self.pose~='hand' then return end
    self.afterimages=list
    self.afterimagesFresh=true
    self.imageElapsed=0
end

---@param weapon string
function Rig:PrepareTrailColor(weapon)
    local index=self.config[weapon].colors.accent
    if self.trailColors[weapon] and self.trailColors[weapon].index==index then return end
    local preset=Catalog.ColorPresets[index]
    local rgb=preset.rgb --[[@as number[] ]]
    local r,g,b=rgb[1]/255,rgb[2]/255,rgb[3]/255
    local colors={index=index,color=Color(r,g,b,1),emissive=Color(r*1.2,g*1.2,b*1.2,.9),
        white=Color(1,1,1,1),whiteEmissive=Color(1.3,1.3,1.3,1),glow={}}
    for i=1,8 do local strength=.9+(i-1)/70;colors.glow[i]=Color(r*strength,g*strength,b*strength,.6) end
    self.trailColors[weapon]=colors
end

function Rig:UpdateTrailColor()
    local colors=self.trailColors[self.active]
    self.world:SetPaletteEntry(Builder.TRAIL_PALETTE,colors.color,1000)
    self.world:SetPaletteEntryPBR(Builder.TRAIL_PALETTE,.5,0,.5,colors.emissive)
    self.world:SetPaletteEntry(WHITE_PALETTE,colors.white,1000)
    self.world:SetPaletteEntryPBR(WHITE_PALETTE,.5,0,.5,colors.whiteEmissive)
    self.glowColors=colors.glow
    self.glowBucket=0
end

function Rig:ClearTrail()
    self.contactArc=false
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
        self.combatFx:ClearSword()
        self.slashRibbon:Clear()
        -- Decorative silhouettes/charge grains can be disabled independently
        -- of arrival flashes and essential hit confirmation.
        for _,image in ipairs(self.images) do image.node.enabled=false end
        for _,image in ipairs(self.bowImages) do image.node.enabled=false end
        for _,particle in ipairs(self.particles) do particle.node.enabled=false end
    end
end

--- Borrowed synchronous HitEvent; only scalar state is retained.
function Rig:BeginSlash(combo,heavy)
    if self.trailEnabled then
        self.combatFx:Begin(combo,heavy)
        self.slashRibbon:Begin(heavy and "cross" or (combo==5 and "moon" or (combo==4 and "heavy" or "light")))
    end
    self.wingGlow=math.max(self.wingGlow or 0,heavy and 1 or .8)
end
function Rig:ImpactFx(position,forward,plunge)
    if self.pose=='hand' then
        self.combatFx:Impact(position,forward,plunge)
        self.shockBurst:Emit(position,forward,plunge)
    end
end
function Rig:SetPlunging(on)
    local plunging=on==true and self.trailEnabled and self.pose=='hand'
    if plunging and not self.combatFx.plunging then self.slashRibbon:Begin('plunge') end
    if not plunging and self.combatFx.plunging then self.slashRibbon:End() end
    self.combatFx.plunging=plunging
end
function Rig:HitImpulse(event)
    if self.disposed or self.pose~='hand' or self.active~='sword' or self.retiring.weapon then return false end
    if self.hitGroup~=event.swingId or self.visualClock-self.hitAt>.25 then
        self.hitGroup,self.hitAt=event.swingId,self.visualClock
        self.hitStop,self.hitWhite,self.hitAngle=0,0,0
    end
    local strong=event.tier=='heavy' or event.tier=='third'
    self.hitStop=math.max(self.hitStop,event.attackerStop or 0)
    self.hitWhite=math.max(self.hitWhite,(strong or event.critical or event.killed) and .06 or .04)
    self.hitAngle=math.max(self.hitAngle,strong and 1.5 or .8)
    self.hitSign=event.combo==2 and 1 or -1
    self.wingGlow=1
    if self.trailEnabled then self.combatFx:Contact(event.pos) end
    self:UpdateHitImpulse() -- AfterPose runs after Rig.Update; show on contact frame.
    return true
end

function Rig:UpdateHitImpulse()
    local entry=self.entries.sword
    local age=self.visualClock-self.hitAt
    local alive=self.pose=='hand' and self.active=='sword' and age<self.hitStop+.05
    local k=alive and math.max(0,1-math.max(0,age-self.hitStop)/.05) or 0
    self.hitRotation:FromEulerAngles(0,0,(self.hitSign or -1)*self.hitAngle*k)
    local b=entry.mesh.blueprint.bounds.min
    self.hitOffset=SetVec(self.hitOffset,b[1]*SWORD_WIDTH,b[2]*SWORD_LENGTH,b[3])
    entry.mesh.node.rotation=self.hitRotation
    self.hitPosition=Rotate(self.hitPosition,self.hitRotation,self.hitOffset)
    entry.mesh.node.position=self.hitPosition
    if alive and age<self.hitWhite-1e-8 then
        local flash=self.flashes.blade
        flash.node:SetParent(entry.pivot)
        flash.offset=SetVec(flash.offset,self.bladeFlashX,self.bladeRoot.y,-.015)
        flash.node.position=flash.offset;flash.node.rotation=flash.rotation
        flash.node.enabled=true
        flash.material:SetShaderParameter('MatDiffColor',self.fxAlpha[17])
    elseif self.flashKind~='full_charge' or self.flashLeft<=0 then self.flashes.blade.node.enabled=false end
end

--- Conservative contact confirmation, matching the existing gameplay sector.
--- Reuses the eight bands; no new volume, shader, table or hit is created.
function Rig:ShowContactArc(zone)
    if self.disposed or self.pose~='hand' or self.active~='sword' or self.retiring.weapon then return false end
    self:ClearTrail()
    local count=self.trailEnabled and 8 or 4
    local half=math.rad(zone.angle*.5)
    local f,o=zone.forward,zone.origin
    for i=1,count do
        local a=-half+2*half*(i-.5)/count
        local x,z=math.sin(a),math.cos(a)
        local dx,dz=x*f.z+z*f.x,z*f.z-x*f.x
        local radius=zone.radius
        local inner=math.max(0,radius-(self.bladeTip.y-self.bladeRoot.y))
        self:RecordSample(o.x+dx*inner,o.y+.9,o.z+dz*inner,
            o.x+dx*radius,o.y+.9,o.z+dz*radius,dz,0,-dx)
    end
    self.contactArc=true;self.tailLeft=TRAIL_TAIL
    self:DrawBands()
    return true
end

--- Called each frame by the combat owner; no pose/motion inference.
---@param active boolean Actual sword hit_on..hit_off interval.
---@param charge number? Only sword_heavy_charge; nil outside that clip.
function Rig:SetCombatVisual(active,charge)
    if self.disposed then return end
    if self.pose~='hand' then active,charge=false,nil end
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
    if self.disposed or self.pose=='hidden' or self.retiring.weapon
        or (kind=='full_charge' and (self.active~='sword' or self.visualState~='hand')) then return false end
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
    local size=Catalog.VOXEL_SIZE
    flash.offset=SetVec(flash.offset,kind=='full_charge' and self.bladeFlashX or -1.5*size,
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

local function MainAlpha(self,mesh,a)
    mesh.alpha=a;mesh.node.enabled=a>0
    mesh.volume.material=a>=1 and mesh.opaque or mesh.fade
    if a>0 and a<1 then mesh.fade:SetShaderParameter('MatDiffColor',self.fxAlpha[math.floor(a*16+.5)+1]) end
end

function Rig:StopCombatVisual()
    self.combatFx:Clear()
    self.slashRibbon:Clear()
    self.shockBurst:Clear()
    self:ClearTrail()
    self.hitAt,self.hitStop,self.hitWhite,self.hitAngle=-math.huge,0,0,0
    self.hitGroup,self.contactArc=nil,false
    self:UpdateHitImpulse()
    self.afterimages=nil;self.afterimagesFresh=false;self.imageElapsed=0
    self.visualActive,self.visualFresh,self.visualCharge=false,false,nil
    self.tailLeft,self.flashLeft,self.chargeFlashed=0,0,false
    self.flashes.blade.node.enabled=false;self.flashes.socket.node.enabled=false
end

function Rig:HideWeapon(weapon)
    MainAlpha(self,self.entries[weapon].mesh,0)
    for _,layer in ipairs(self.layers[weapon]) do layer.node.enabled=false end
    if weapon=='bow' then
        for _,mesh in ipairs(self.bowDrawMeshes) do mesh.node.enabled=false end
        for _,mesh in ipairs(self.bowStrings) do mesh.node.enabled=false end
        self.bowArrow.node.enabled=false
    end
end

function Rig:CancelRetiring()
    local r=self.retiring
    if r.weapon then self:HideWeapon(r.weapon);r.weapon=nil end
end

--- Freeze only already-visible outgoing geometry; latest selection stays the
--- gameplay owner. A second swap cancels this snapshot before taking another.
function Rig:RetireCurrent()
    local r,entry=self.retiring,self.entries[self.active]
    r.elapsed,r.layerMask,r.bowStage,r.arrow=0,0,0,false
    r.alpha=entry.mesh.node.enabled and entry.mesh.alpha or 0
    for i,layer in ipairs(self.layers[self.active]) do
        if layer.node.enabled then r.layerMask=r.layerMask|(1<<(i-1)) end
    end
    if self.active=='bow' then
        for _,mesh in ipairs(self.bowStrings) do mesh.node.enabled=false end
        for i,mesh in ipairs(self.bowDrawMeshes) do if mesh.node.enabled then r.bowStage=i end end
        r.arrow=self.bowArrow.node.enabled
    end
    if r.alpha<=0 and r.layerMask==0 and r.bowStage==0 then return end
    r.weapon=self.active
    r.position=CopyVec(r.position,entry.pivot.worldPosition);CopyRot(r.rotation,entry.pivot.worldRotation)
    entry.pivot:SetParent(self.scene);entry.pivot.worldPosition=r.position;entry.pivot.worldRotation=r.rotation
end

--- Returns leftover frame time for the incoming visual. At most one weapon
--- can be drawn in a frame; outgoing .08s + incoming .08s = .16s swap.
function Rig:AdvanceRetiring(dt)
    local r=self.retiring
    if not r.weapon then return dt end
    local remaining=SWAP_HALF-r.elapsed
    r.elapsed=math.min(SWAP_HALF,r.elapsed+dt)
    if SWAP_HALF-r.elapsed<1e-8 then self:CancelRetiring();return math.max(0,dt-remaining) end
    local a=math.ceil((1-r.elapsed/SWAP_HALF)*6)/6
    local alpha=self.fxAlpha[math.floor(a*16+.5)+1]
    local entry=self.entries[r.weapon]
    MainAlpha(self,entry.mesh,r.alpha*a)
    for i,layer in ipairs(self.layers[r.weapon]) do
        layer.node.enabled=(r.layerMask&(1<<(i-1)))~=0
        if layer.node.enabled then layer.material:SetShaderParameter('MatDiffColor',alpha) end
    end
    if r.weapon=='bow' then
        for i,mesh in ipairs(self.bowDrawMeshes) do
            mesh.node.enabled=i==r.bowStage
            if mesh.node.enabled then mesh.material:SetShaderParameter('MatDiffColor',alpha) end
        end
        self.bowArrow.node.enabled=r.arrow
        if r.arrow then self.bowArrow.material:SetShaderParameter('MatDiffColor',alpha) end
    end
    return 0
end

---@param weapon string
---@return boolean
function Rig:SetActive(weapon)
    if self.disposed or (weapon~="sword" and weapon~="bow") then return false end
    if self.active==weapon then return true end
    for i=#self.events,1,-1 do self.events[i]=nil end -- discard outgoing arrival notifications
    self:CancelRetiring()
    self:RetireCurrent()
    if not self.retiring.weapon then self:HideWeapon(self.active) end
    self:StopCombatVisual();self:SetBowDraw(0)
    self.active,self.config.active=weapon,weapon
    self.transition=nil
    self.visualState,self.hangReady='hidden',false
    self.attached="hidden"
    self.swingOffset,self.swingEuler=Vector3.ZERO,Vector3.ZERO
    self:ClearTrail()
    self:UpdateTrailColor()
    self:HideWeapon(weapon)
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
    if pose=='hidden' then self:CancelRetiring();self:StopCombatVisual() end
    if self.pose==pose then return true end
    for i=#self.events,1,-1 do self.events[i]=nil end -- a redirected flight owns a new arrival
    local previous=self.pose
    self.pose=pose
    self:StopCombatVisual()
    self:SetBowDraw(0)
    if pose=='hidden' then
        self:BeginMotion('dissolve',HIDE_TIME)
        -- No arrow, flash, trail or afterimage survives the setter itself.
        for _,mesh in ipairs(self.bowDrawMeshes) do mesh.node.enabled=false end
        for _,mesh in ipairs(self.bowStrings) do mesh.node.enabled=false end
        self.bowArrow.node.enabled=false
    elseif self.visualState=='hidden' then
        self:Attach('back');self.hangReady=false
        if pose=='hand' then self:BeginMotion('fly_to_hand',.08) -- direct attack cannot wait for a .30s reveal
        else self:BeginMotion('materialize',self.retiring.weapon and SWAP_HALF or REVEAL_TIME);self:EmitEvent('materialize') end
    elseif pose=='hand' then
        self:BeginMotion('fly_to_hand',self.visualState=='materialize' and .08 or .12)
    elseif previous=='hand' or self.visualState=='fly_to_hand' then
        self:BeginMotion('stow',.18)
    else
        -- Reverse an interrupted dissolve in-place: do not teleport its visible
        -- fragments to a back socket. A short flight resolves the new target.
        self:BeginMotion('stow',.16)
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
    local hit=Catalog.Definitions[self.active].hit
    return {origin=entry.pivot:LocalToWorld(Vec(hit.origin)),dir=entry.pivot.worldRotation*Vec(hit.dir),
        length=hit.length,radius=hit.radius}
end

---@return table
function Rig:GetStats() return Catalog.Definitions[self.active].stats end

-- Apply only cosmetic values, retaining all fixed geometry and effect pools.
-- Persistence and loadout selection belong to WeaponLoadout, not the renderer.
function Rig:ApplyAppearance(config,deferred)
    if self.disposed then return false,'武器已释放' end
    local blueprint,err=Builder.Compile(config)
    if not blueprint then return false,err end
    local weapon=blueprint.config.weapon
    local entry=self.entries[weapon]
    local previous=entry.mesh.blueprint
    if previous.key==blueprint.key then return true end
    local oldConfig,oldTrail=self.config[weapon],self.trailColors[weapon]
    local wing,finished
    local transaction={}
    function transaction.Rollback()
        if finished then return end
        entry.mesh.blueprint=previous
        self.config[weapon],self.trailColors[weapon]=oldConfig,oldTrail
        if wing then wing.Rollback() end
        Builder.ApplyPalette(self.world,previous.config)
        if weapon==self.active then self:UpdateTrailColor() end
        finished=true
    end
    function transaction.Commit()
        if finished then return end
        if wing then wing.Commit() end
        finished=true
    end
    local ok,reason=pcall(function()
        Builder.ApplyPalette(self.world,blueprint.config)
        if entry.wing then wing=WingVisual.Recolor(entry.wing,blueprint.config.colors,true) end
        entry.mesh.blueprint=blueprint
        self.config[weapon]=Catalog.CopyAppearance(weapon,blueprint.config)
        self:PrepareTrailColor(weapon)
        if weapon==self.active then self:UpdateTrailColor() end
    end)
    if not ok then
        local restored,restoreError=pcall(transaction.Rollback)
        return false,tostring(reason)..(restored and '' or '; rollback: '..tostring(restoreError))
    end
    if not deferred then transaction.Commit() end
    return true,nil,transaction
end

-- State storage and motion workspaces are reused across every transition.
function Rig:BeginMotion(state,duration)
    local m=self.motion
    m.elapsed,m.duration=0,duration
    m.visibleFrom=self.entries[self.active].mesh.alpha
    m.arc=SetVec(m.arc,self.active=='sword' and .18 or -.18,.35,0)
    self.visualState,self.transition=state,m
    local pivot=self.entries[self.active].pivot
    m.from=CopyVec(m.from,pivot.worldPosition);CopyRot(m.rotation,pivot.worldRotation)
    m.holo=self:HoloCapable()
    if m.holo then
        -- Projection transition: the blade dissolves where it is (following the
        -- hand or back) and reforms at the target; it never flies through the body.
        for _,layer in ipairs(self.layers[self.active]) do layer.node.enabled=false end
        local out=state~='materialize' and m.visibleFrom>0
        -- A direct attack from hidden (.08s request) reforms faster.
        local outTime=out and HOLO_OUT or 0
        local inTime=state=='dissolve' and 0 or (duration<=.08 and .10 or HOLO_IN)
        m.duration=math.max(1e-3,outTime+inTime)
        m.split=outTime/m.duration
        m.arrived=false
        return
    end
    if state=='fly_to_hand' or state=='stow' then
        for _,layer in ipairs(self.layers[self.active]) do layer.node.enabled=false end
        pivot:SetParent(self.scene)
        pivot.worldPosition=m.from;pivot.worldRotation=m.rotation
    end
end

---@return boolean
function Rig:HoloCapable()
    local entry=self.entries.sword
    return self.active=='sword' and entry~=nil and entry.wing~=nil and WingVisual.HasHolo(entry.wing)
end

-- Keeps the pivot on whichever socket it currently rides (hand pose or back hang).
function Rig:HoldPivot(entry)
    local hand=self.sockets.hand_right
    if entry.pivot.parent==hand then
        entry.pivot.position=self.swingOffset
        HandRotation(self,self.poseRotation)
        entry.pivot.rotation=self.poseRotation
    else
        entry.pivot.worldPosition=self.hangPosition;entry.pivot.worldRotation=self.hangRotation
    end
end

--- Wing sword projection timeline. t in [0,1]; split marks dissolve -> reform.
--- Out: projection glow rises over the solid blade, solid hides, cells blow away.
--- In: cells assemble from the tip down, then the solid blade returns and the glow fades.
function Rig:AdvanceHolo(entry,m,t)
    local state=self.visualState
    local into=state~='dissolve'
    if t<m.split then
        local u=t/m.split
        self.holoSolid,self.holoGlow,self.holoCut=u<.30,math.min(1,u/.30),math.max(0,(u-.30)/.70)
        MainAlpha(self,entry.mesh,1-u)
    elseif into then
        if not m.arrived then
            m.arrived=true
            self:Attach(state=='fly_to_hand' and 'hand' or 'back')
        end
        local v=m.split<1 and (t-m.split)/(1-m.split) or 1
        self.holoSolid,self.holoGlow,self.holoCut=v>=.70,v<.70 and 1 or 1-(v-.70)/.30,math.max(0,1-v/.70)
        MainAlpha(self,entry.mesh,math.max(v,1e-3))
    else
        self.holoSolid,self.holoGlow,self.holoCut=false,0,1
    end
    self:HoldPivot(entry)
    if t>=1 then
        self.transition=nil;self:ClearTrail()
        if state=='dissolve' then
            self:Attach('hidden');self.visualState='hidden';self:EmitEvent('dissolved')
        elseif state=='fly_to_hand' then
            MainAlpha(self,entry.mesh,1)
            self:Attach('hand');self.visualState='hand';self:EmitEvent('blade_draw');self:ArrivalFlash('draw')
        else
            MainAlpha(self,entry.mesh,1);self:Attach('back');self.visualState='hang'
            if state=='materialize' then
                self:EmitEvent('materialized');self:ArrivalFlash('sheath')
                if self.pose=='hand' then self:BeginMotion('fly_to_hand',.12) end
            else
                self.recoil=.12;self:EmitEvent('blade_sheath');self:ArrivalFlash('sheath')
            end
        end
    end
end

-- Critically damped position spring (80ms time constant), capped displacement.
-- A teleport resets the spring instead of dragging a weapon across the world.
function Rig:UpdateHang(dt)
    local socket=self.sockets['back_'..self.active]
    self.hangTarget=CopyVec(self.hangTarget,socket.worldPosition)
    local target=self.hangTarget
    target.y=target.y+.02*math.sin(self.visualClock*math.pi*1.2)
    self.hangTarget=target
    if not self.hangReady or Distance(target,self.hangPosition)>2 then
        self.hangPosition=CopyVec(self.hangPosition,target);self.hangVelocity=SetVec(self.hangVelocity,0,0,0)
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
            p=SetVec(p,target.x+(p.x-target.x)*k,target.y+(p.y-target.y)*k,target.z+(p.z-target.z)*k)
        end
        -- A fast turn must not drag the hilt inward through the coat.
        self.hangForward=Rotate(self.hangForward,self.body.worldRotation,Vector3.FORWARD)
        local f=self.hangForward
        local inward=(p.x-target.x)*f.x+(p.y-target.y)*f.y+(p.z-target.z)*f.z
        if inward>.025 then p=SetVec(p,p.x-f.x*(inward-.025),p.y-f.y*(inward-.025),p.z-f.z*(inward-.025)) end
        self.hangPosition,self.hangVelocity=p,v
        BlendRot(self.hangRotation,self.hangRotation,socket.worldRotation,1-math.exp(-dt/.08))
        local a,b=self.hangRotation,socket.worldRotation
        local angle=2*math.acos(Clamp(math.abs(a.w*b.w+a.x*b.x+a.y*b.y+a.z*b.z),0,1))
        if angle>MAX_HANG_ANGLE then BlendRot(self.hangRotation,a,b,1-MAX_HANG_ANGLE/angle) end
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
    if (state=='hang' or state=='materialize' or state=='dissolve' and entry.pivot.parent==self.sockets['back_'..self.active])
        and not (self.transition and self.transition.holo) then
        entry.pivot.worldPosition=self.hangPosition;entry.pivot.worldRotation=self.hangRotation
        if self.recoil>0 then
            local p=CopyVec(self.motion.output,self.hangPosition)
            self.motion.curve=Rotate(self.motion.curve,self.body.worldRotation,Vector3.FORWARD)
            local d=self.motion.curve;local amount=.02*math.sin((1-self.recoil/.12)*math.pi)
            p=SetVec(p,p.x-d.x*amount,p.y-d.y*amount,p.z-d.z*amount)
            self.motion.output=p
            entry.pivot.worldPosition=p
        end
    end
    local m=self.transition
    if not m then return end
    m.elapsed=math.min(m.duration,m.elapsed+dt)
    if m.duration-m.elapsed<1e-8 then m.elapsed=m.duration end
    local t=Clamp(m.elapsed/m.duration,0,1)
    if m.holo then self:AdvanceHolo(entry,m,t);return end
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
            goal=CopyVec(goal,socket:LocalToWorld(self.swingOffset))
            HandRotation(self,self.poseRotation)
            CopyRot(self.moveRotation,socket.worldRotation*self.poseRotation)
        else goal=CopyVec(goal,self.hangPosition);CopyRot(self.moveRotation,self.hangRotation) end
        self.moveTarget=goal
        local u=1-(1-t)*(1-t)
        m.curve=Rotate(m.curve,self.body.worldRotation,m.arc)
        local arc=4*u*(1-u)
        m.output=SetVec(m.output,m.from.x+(goal.x-m.from.x)*u+m.curve.x*arc,
            m.from.y+(goal.y-m.from.y)*u+m.curve.y*arc,m.from.z+(goal.z-m.from.z)*u+m.curve.z*arc)
        BlendRot(m.outRotation,m.rotation,self.moveRotation,u)
        entry.pivot.worldPosition=m.output;entry.pivot.worldRotation=m.outRotation
        -- Discrete fade-out / blackout / fade-in while the SAME pooled pivot
        -- follows its arc. No fractional scale, no two-position crossfade.
        local alpha=t<.4 and m.visibleFrom*(1-t/.4) or (t<=.6 and 0 or (t-.6)/.4)
        MainAlpha(self,entry.mesh,math.floor(Clamp(alpha,0,1)*6+1e-7)/6)
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
    recycled.root=SetVec(recycled.root,rx,ry,rz);recycled.tip=SetVec(recycled.tip,tx,ty,tz);recycled.tangent=SetVec(recycled.tangent,dx,dy,dz)
    self.sampleCount=math.min(TRAIL_SEGMENTS,self.sampleCount+1)
end

---@param entry WeaponRigEntry
function Rig:SampleBlade(entry)
    local root=entry.pivot:LocalToWorld(self.bladeRoot)
    local tip=entry.pivot:LocalToWorld(self.bladeTip)
    if self.visualActive and self.trailEnabled then
        self.slashRibbon:Sample(root,tip)
    end
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
    self.previousRoot=CopyVec(previousRoot,root);self.previousTip=CopyVec(previousTip,tip)
end

function Rig:DrawBands()
    local flying=self.visualState=='fly_to_hand'
    local fade=(self.visualActive or flying) and 1 or math.ceil(Clamp(self.tailLeft/TRAIL_TAIL,0,1)*4)/4
    for i,band in ipairs(self.trails) do
        band.node.enabled=i<=math.ceil(self.sampleCount*fade) and self.sampleCount>=2 and fade>0 and (not flying or i<=4) and (self.trailEnabled or i<=4)
        if band.node.enabled then
            local sample=self.samples[i]
            local x,y,z=band.xAxis,band.yAxis,band.zAxis
            y=SetVec(y,sample.tip.x-sample.root.x,sample.tip.y-sample.root.y,sample.tip.z-sample.root.z)
            local length=math.sqrt(y.x*y.x+y.y*y.y+y.z*y.z)
            y=SetVec(y,y.x/length,y.y/length,y.z/length)
            local d=sample.tangent
            local dot=d.x*y.x+d.y*y.y+d.z*y.z
            x=SetVec(x,d.x-dot*y.x,d.y-dot*y.y,d.z-dot*y.z)
            length=math.sqrt(x.x*x.x+x.y*x.y+x.z*x.z)
            if length<1e-6 then
                if math.abs(y.x)<.9 then x=SetVec(x,1-y.x*y.x,-y.x*y.y,-y.x*y.z)
                else x=SetVec(x,-y.z*y.x,-y.z*y.y,1-y.z*y.z) end
                length=math.sqrt(x.x*x.x+x.y*x.y+x.z*x.z)
            end
            x=SetVec(x,x.x/length,x.y/length,x.z/length)
            z=SetVec(z,x.y*y.z-x.z*y.y,x.z*y.x-x.x*y.z,x.x*y.y-x.y*y.x)
            band.xAxis,band.yAxis,band.zAxis=x,y,z
            band.rotation:FromAxes(x,y,z)
            local halfWidth,halfDepth=Catalog.VOXEL_SIZE*2.5,Catalog.VOXEL_SIZE*.5
            band.position=SetVec(band.position,sample.root.x-x.x*halfWidth-z.x*halfDepth,
                sample.root.y-x.y*halfWidth-z.y*halfDepth,sample.root.z-x.z*halfWidth-z.z*halfDepth)
            band.node.worldPosition=band.position;band.node.worldRotation=band.rotation
            -- White centre/accent edges share one solid mesh. Tail recedes in
            -- four discrete steps rather than stacking transparent full-blade strips.
        end
    end
end

---@param entry WeaponRigEntry
---@param dt number
function Rig:UpdateImages(entry,dt)
    -- Event flash + one silhouette, or up to two silhouettes without the flash.
    -- Also retain only one silhouette over the band for a clean swing outline.
    local limit=((self.sampleCount>=2 or self.flashLeft>0) and 1 or 2)
    local pool=self.active=='sword' and self.images or self.bowImages
    local other=self.active=='sword' and self.bowImages or self.images
    local minimum=self.active=='sword' and self.imageMin or self.bowImageMin
    for i=1,2 do
        local shot=self.afterimages and self.afterimages[i]
        local image=pool[i]
        other[i].node.enabled=false
        local age=shot and (shot.age or 0)+self.imageElapsed or 1
        local life=.10
        local clipOK=shot and type(shot.clip)=='string' and (self.active=='sword' and shot.clip:sub(1,6)=='sword_')
        local valid=i<=limit and clipOK and age>=0 and age<life-1e-8 and Distance(entry.pivot.worldPosition,shot.position)<2
        image.node.enabled=not not valid
        if valid then
            image.node.worldPosition=shot.position+shot.rotation*minimum
            image.node.worldRotation=shot.rotation
            local tail=self.visualActive and 1 or Clamp(self.tailLeft/TRAIL_TAIL,0,1)
            Alpha(self,image,Clamp(math.min(shot.alpha or 1,1-age/life),0,1)*.5*tail)
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
            particle.offset=SetVec(particle.offset,d.x*radius,self.bladeRoot.y+d.y*radius,d.z*radius)
            local point=entry.pivot:LocalToWorld(particle.offset)
            local half=Catalog.VOXEL_SIZE*.5
            particle.position=SetVec(particle.position,point.x-half,point.y-half,point.z-half)
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
    local vibrating=self.bowReleaseAt and self.visualClock-self.bowReleaseAt<.05
    local showString=self.active=='bow' and self.visualState=='hand' and (drawn or vibrating)
    local nock=self:GetBowNockLocal()
    if vibrating then
        local t=self.visualClock-self.bowReleaseAt
        nock=nock+Vector3(.03*math.cos(t*math.pi*60)*(1-t/.05),0,0)
    end
    local thorn=self.entries.bow.thorn
    local thornOn=thorn and thorn.ready and true or false
    -- Thorn bow: limb tips pull toward the archer while drawn; the voxel string follows them.
    local bend=thornOn and drawn and (.02+self.bowStage*.03) or 0
    local tipZ=thornOn and (ThornVisual.StringZ(thorn)-bend) or (-2-self.bowStage)*.03
    if thornOn then
        ThornVisual.SetBend(thorn,bend);ThornVisual.SetStringVisible(thorn,not showString)
        self.thornAim=(drawn or vibrating) and 1 or 0
    end
    for i,mesh in ipairs(self.bowStrings) do
        mesh.node.enabled=showString
        if showString then
            local tip=thornOn and thorn.node.rotation*Vector3(0,(i==1 and 1 or -1)*ThornVisual.StringHalf(thorn),tipZ)
                or Vector3(0,(i==1 and 1 or -1)*self.bowHalfHeight,tipZ)
            local delta=tip-nock
            mesh.node:SetDirection(delta:Normalized())
            mesh.node.scale=Vector3(.35,.35,delta:Length()/.03)
            mesh.node.position=nock-mesh.node.rotation*Vector3(.00525,.00525,0)
        end
    end
    for i,mesh in ipairs(self.bowDrawMeshes) do mesh.node.enabled=not thornOn and drawn and i==self.bowStage+1 end
    self.bowArrow.node.enabled=drawn
    if self.active=='bow' and self.visualState=='hand' then
        self.entries.bow.mesh.node.enabled=not (drawn or vibrating)
        if vibrating and not drawn and not thornOn then self.bowDrawMeshes[1].node.enabled=true end
    end
    if drawn then
        local minimum=self.bowArrow.minimum
        local launch=self.entries.bow.mesh.blueprint.hit.origin
        self.bowArrowOffset=SetVec(self.bowArrowOffset,minimum.x+launch[1],minimum.y+launch[2],minimum.z+nock.z)
        self.bowArrow.node.position=self.bowArrowOffset
        self.bowArrow.material:SetShaderParameter('MatDiffColor',self.fxAlpha[17])
        if not thornOn then self.bowDrawMeshes[self.bowStage+1].material:SetShaderParameter('MatDiffColor',self.fxAlpha[17]) end
    end
end

function Rig:UpdateMaterializeParticles()
    local state=self.visualState
    local visible=self.pose~='hidden' and state=='materialize'
    local t=visible and self.motion.elapsed/self.motion.duration or 0
    local center=self.entries[self.active].pivot.worldPosition
    for _,particle in ipairs(self.particles) do
        particle.node.enabled=visible
        if visible then
            local radius=.02+.3*(state=='materialize' and 1-t or t)
            local d=particle.direction
            particle.position=SetVec(particle.position,center.x+d.x*radius,center.y+d.z*radius,center.z+d.y*radius)
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
function Rig:UpdateCore(dt)
    if self.disposed then return end
    dt=math.max(0,dt)
    self.visualClock=self.visualClock+dt
    self.combatFx:Update(dt)
    if not self.visualActive and not self.combatFx.plunging then self.slashRibbon:Clear() end
    self.slashRibbon:Update(dt)
    self.shockBurst:Update(dt)
    self:UpdateHang(dt)
    -- W2 submits the real hit_on state before Update and performs AfterPose
    -- sweeps afterwards. Never leave its first hit using a mid-flight pivot.
    if self.visualActive and self.visualFresh and self.pose=='hand' and self.visualState=='fly_to_hand' then
        self:CancelRetiring() -- hit timing wins; never sweep using an old/back pivot
        self.motion.elapsed=self.motion.duration
    end
    local motionDt=self:AdvanceRetiring(dt)
    if self.retiring.weapon then return end
    self:AdvanceTransition(motionDt)
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
    self:UpdateFlash(self.arrivalFresh and 0 or dt);self.arrivalFresh=false
    self:UpdateHitImpulse()
    if self.contactArc then self:ClearTrail() end -- one presented contact frame
    if self.visualState~='hand' then
        if self.visualState=='fly_to_hand' and self.active=='sword' and entry.mesh.alpha>0 and not (self.transition and self.transition.holo) then
            self:SampleBlade(entry);self:DrawBands()
        else self:ClearTrail() end
        if self.trailEnabled then self:UpdateMaterializeParticles() end
        self:UpdateGlow()
        self.tailLeft=0;return
    end
    if self.pose~='hand' or self.attached~='hand' or entry.mesh.alpha<1 then self:ClearTrail();self.tailLeft=0;return end
    if self.active~='sword' then self:ClearTrail();self.tailLeft=0;return end
    if self.trailEnabled and self.combatFx.plunging then
        local root,tip=entry.pivot:LocalToWorld(self.bladeRoot),entry.pivot:LocalToWorld(self.bladeTip)
        self.combatFx:Descent(root,tip)
        self.slashRibbon:Sample(root,tip) -- falling sheet of light behind the blade
    end
    if not self.visualActive then self.combatFx.valid=false end
    if self.visualActive or self.tailLeft>0 then
        if self.visualActive then self:SampleBlade(entry) end
        if self.trailEnabled then self:UpdateCharge(entry) end
    else self:ClearTrail() end
    if self.trailEnabled then self:UpdateCharge(entry) end
end

--- Wing sword visual (WingSwordVisual): shown instead of the voxel sword mesh when it loads.
--- Hit geometry, sockets, trails and afterimages keep using the voxel blueprint.
---@param entry table sword entry
---@param blueprint table? freshly compiled blueprint (Apply) else entry.mesh.blueprint
function Rig:AttachWing(entry,blueprint)
    blueprint=blueprint or entry.mesh.blueprint
    local tipY=Catalog.Definitions.sword.visualTip
    local colors=blueprint.config and blueprint.config.colors
    if entry.wing and math.abs((entry.wingTip or 0)-tipY)>1e-6 then
        WingVisual.Dispose(entry.wing);entry.wing=nil
    end
    if entry.wing then WingVisual.Recolor(entry.wing,colors)
    else
        local wing,err=WingVisual.New(entry.pivot,tipY,colors)
        if not wing then
            if not Rig.wingWarned then Rig.wingWarned=true;print('WeaponRig: wing sword unavailable, voxel sword kept: '..tostring(err)) end
            return
        end
        entry.wing,entry.wingTip=wing,tipY
    end
    entry.mesh.node.scale=Vector3(1e-4,1e-4,1e-4) -- keep the voxel mesh alive for opacity/pools, just invisible
end
---@param dt number?
function Rig:SyncWing(dt)
    local entry=self.entries.sword
    if not (entry and entry.wing) then return end
    if self.transition and self.transition.holo and self.active=='sword' then
        WingVisual.SetVisible(entry.wing,self.holoSolid==true)
        WingVisual.SetHolo(entry.wing,self.holoGlow or 0,self.holoCut or 1)
    else
        WingVisual.SetVisible(entry.wing,self.active=='sword' and entry.mesh.alpha>=.5)
        WingVisual.SetHolo(entry.wing,0,1)
    end
    -- Crystal glow: swings/hits spike it, heavy charge holds it, then ~0.3s decay.
    local glow=math.max(0,(self.wingGlow or 0)-(dt or 0)*3.2)
    if self.visualActive then glow=math.max(glow,.55) end
    if self.visualCharge then glow=math.max(glow,.25+.75*self.visualCharge) end
    self.wingGlow=glow
    WingVisual.SetCharge(entry.wing,glow)
end
--- Thorn-flower bow visual (ThornBowVisual): replaces the voxel bow's look in hand and on the back.
--- Nock, draw stages, arrows and the drawn string keep using the voxel blueprint.
---@param entry table bow entry
function Rig:AttachThorn(entry)
    if not entry then return end
    local half=self.bowHalfHeight
    if not half then return end
    if entry.thorn and math.abs((entry.thornHalf or 0)-half)>1e-6 then
        ThornVisual.Dispose(entry.thorn);entry.thorn=nil
    end
    if not entry.thorn then
        local thorn,err=ThornVisual.New(entry.pivot,half)
        if not thorn then
            if not Rig.thornWarned then Rig.thornWarned=true;print('WeaponRig: thorn bow unavailable, voxel bow kept: '..tostring(err)) end
            return
        end
        entry.thorn,entry.thornHalf=thorn,half
        self.sockets.back_bow.rotation=ThornVisual.BackRotation()
    end
end
---@param dt number?
function Rig:SyncThorn(dt)
    local entry=self.entries.bow
    local thorn=entry and entry.thorn
    if not thorn then return end
    if not thorn.ready then ThornVisual.Step(thorn) end
    if not thorn.ready then return end
    -- Voxel bow mesh stays alive for opacity/pools/hit data but is invisible while the thorn bow shows.
    local node=entry.mesh.node
    if node.scale.x>.01 then node.scale=Vector3(1e-4,1e-4,1e-4) end
    ThornVisual.SetVisible(thorn,self.active=='bow' and entry.mesh.alpha>=.5)
    -- Aim stance eases in/out (~.15s); the voxel string tips follow the rotated limbs (UpdateBowVisual).
    local target=(self.visualState=='hand' and self.thornAim) or 0
    local k=thorn.aimK or 0
    local step=(dt or 0)/.15
    k=k<target and math.min(target,k+step) or math.max(target,k-step)
    thorn.aimK=k
    ThornVisual.SetAim(thorn,k)
end
function Rig:Update(dt)
    self:UpdateCore(dt)
    self:SyncWing(dt)
    self:SyncThorn(dt)
end

function Rig:Dispose()
    if self.disposed then return end
    self.disposed=true
    self.combatFx:Dispose()
    self.slashRibbon:Dispose()
    self.shockBurst:Dispose()
    for _,layers in pairs(self.layers) do for _,layer in ipairs(layers) do DisposeEffect(self,layer) end end
    for _,mesh in ipairs(self.bowDrawMeshes) do DisposeEffect(self,mesh) end
    DisposeEffect(self,self.bowArrow)
    for _,mesh in ipairs(self.bowStrings or {}) do DisposeEffect(self,mesh) end
    for _,mesh in ipairs(self.flightArrows or {}) do DisposeEffect(self,mesh);mesh.root:Remove() end
    for _,trail in ipairs(self.trails) do self.world:RemoveVolume(trail.volume); trail.material:Dispose() end
    for _,image in ipairs(self.images) do self.world:RemoveVolume(image.volume);image.material:Dispose() end
    for _,image in ipairs(self.bowImages) do self.world:RemoveVolume(image.volume);image.material:Dispose() end
    for _,particle in ipairs(self.particles) do self.world:RemoveVolume(particle.volume);particle.material:Dispose() end
    for _,flash in pairs(self.flashes) do self.world:RemoveVolume(flash.volume);flash.material:Dispose() end
    for _,entry in pairs(self.entries) do WingVisual.Dispose(entry.wing);entry.wing=nil;ThornVisual.Dispose(entry.thorn);entry.thorn=nil;Builder.Dispose(entry.mesh); entry.pivot:Remove() end
    self.sockets.back_sword:Remove()
    self.sockets.back_bow:Remove()
    -- Both palms are shared character-owned nodes: never delete, move or reset
    -- them. Our weapon pivots and child flash volumes have already been removed.
    self.trails,self.samples,self.images,self.particles={},{},{},{}
    self.bowImages={}
    self.afterimages=nil
end
return Rig
