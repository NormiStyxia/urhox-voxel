-- Positions below are in island-local metres, looking north from the waterfall.
local Brush = require('ruins.VoxelBrush')
local Noise = require('ruins.Noise')
local Terrain = require('ruins.RuinsTerrain')
local P = require('ruins.RuinsPalette').P
local H = { x = 720, z = 0, base = 6, planarReflectionEnabled = true }
local abs, floor, sin, cos, sqrt = math.abs, math.floor, math.sin, math.cos, math.sqrt
local oak, amber, cedar, slate, ember, flame = 150,151,152,153,154,155
local window = 156
-- Axial grain survives greedy meshing because the palette ID stays on each face.
local cedarPost, oakPlankZ, cedarBeamZ = 157,158,159
local WATER_LEVEL = -.375
local WATER_VIEW = 0x10000000
local MIRROR_VIEW = 0x08000000
-- The mirror keeps direct sun lighting but must not prepare the sun shadow map.
-- The generated Lua metadata leaves this enum nil; UrhoXRuntime registers 2.
local MIRROR_VIEW_FLAGS = rawget(_G, 'VO_DISABLE_SHADOWS') or 2
local mirror
local mirrorTiers={
    high={size=640,hz=24,idleSeconds=.5,moveMetres=.025},
    medium={size=448,hz=16,idleSeconds=.5,moveMetres=.025},
    low={size=288,hz=6,idleSeconds=2,moveMetres=.10},
}
local function pattern(x,z)
    return sin(x*.49 + z*.17) + .65*cos(z*.81-x*.23)
end
local function edge(x,z)
    local a = math.atan(z/19,x/26)
    return 19*(1 + .045*cos(5*a)+.032*sin(9*a) - sqrt((x/26)^2+(z/19)^2))
end
local function pool(x,z)
    return ((x+7.5)/10)^2 + ((z+5.25)/6.25)^2
end
local function channel(x,z) return abs(x+11.75)<1.65 and z < -6 end
local function pad(x,z) return sqrt((x-12)^2+(z-3)^2) end
local function top(x,z)
    -- The water mesh occupies half-metre cells. Keep the submerged columns on that footprint.
    local wx,wz=(floor(x*2)+.5)*.5,(floor(z*2)+.5)*.5
    if channel(wx,wz) then return -1.5 end
    local basin=pool(wx,wz)
    if basin<1 then return -.75-.25*floor(4*(1-basin)) end
    x,z=(floor(x*4)+.5)*.25,(floor(z*4)+.5)*.25
    if pad(x,z)<8.8 then return 1.5 end
    if x>9 and x<15 and z<0 then return math.max(0,math.min(1.5,floor((z+10)*1.3)*.25)) end
    local north=2*(1-((x+6)/18)^2-((z-19+.55*sin(x*.31))/5.7)^2)
    local bench=math.max(0,math.min(1,2-math.max(abs(x+13),abs(z-15))))
    north=north+(.875-north)*bench -- a level tread around the mature golden tree's spreading roots
    local west=1.25*(1-((x+24+.4*sin(z*.42))/5.7)^2-((z-1)/11)^2)
    local south=1-((x+2)/10)^2-((z+18+.45*sin(x*.52))/4.2)^2
    local east=.85*(1-((x-17)/8)^2-((z+13)/5)^2)
    return .25*floor(4*math.max(0,north,west,south,east))
end
function H.Contains(x,z) return abs(x-H.x)<35 and abs(z-H.z)<28 end
function H.Ground(x,z,margin) return edge(x-H.x,z-H.z)>=(margin or 0) end
function H.Height(x,z) return H.base+top(x-H.x,z-H.z) end
function H.Safe(x,y,z)
    local lx,lz=x-H.x,z-H.z
    return edge(lx,lz)>1.6 and pool(lx,lz)>1.06 and not channel(lx,lz) and abs(y-H.Height(x,z))<.46
end
function H.NearForge(p) return (p.x-H.x-1.25)^2+(p.z-H.z-6.0)^2<15 and abs(p.y-H.base)<2 end
local activeJob
local ripples,nextSlot,wet,lastX,lastZ={},1,false,nil,nil
local stepTime,travel=0,0
local WAVE_LIFE, STEP_TIME, STEP_DISTANCE = 1.4,.35,.82

-- The pool mesh samples the centre of each half-metre cell. Use the same
-- sample for contact, including the last cells at the waterfall lip.
local function waterBed(x,z)
    local cx,cz=floor(x*2)*.5+.25,floor(z*2)*.5+.25
    if edge(cx,cz)>0 then
        local bed=top(cx,cz)
        if bed<0 then return bed end
    end
end

function H.ClearRipples()
    for slot in pairs(ripples) do
        H.spring:SetShaderParameter('foot_wave'..slot,Variant(Vector4(0,0,0,0)))
        ripples[slot]=nil
    end
    nextSlot,wet,lastX,lastZ,stepTime,travel=1,false,nil,nil,0,0
end

function H.ReleaseReflection()
    if not mirror then return end
    if mirror.surface then mirror.surface:SetNumViewports(0) end
    if H.spring then
        H.spring:SetShaderParameter('mirror_weight',Variant(0.0))
        if mirror.bindingAttempted then H.spring:SetSurfaceTexture('mirror_color',nil) end
    end
    if mirror.node then mirror.node:Remove() end
    if mirror.skybox then mirror.skybox.viewMask=mirror.skybox.viewMask | MIRROR_VIEW end
    if mirror.texture then mirror.texture:Dispose() end
    mirror=nil
end

local function createReflection(r,scene,skybox,w,h)
    r.texture=Texture2D:new()
    r.texture:SetNumLevels(1)
    r.texture:SetSRGB(false)
    if not r.texture:SetSize(w,h,Graphics:GetRGBAFloat16Format(),TEXTURE_RENDERTARGET) then return false end
    r.texture:SetFilterMode(FILTER_BILINEAR)
    r.texture:SetAddressMode(COORD_U,ADDRESS_CLAMP)
    r.texture:SetAddressMode(COORD_V,ADDRESS_CLAMP)
    r.surface=r.texture:GetRenderSurface()
    if not r.surface then return false end
    r.node=scene:CreateChild('HomeSpringMirror')
    local camera=r.node:CreateComponent('Camera')
    r.camera=camera
    camera.useReflection=true
    camera.reflectionPlane=Plane(Vector3.UP,Vector3(H.x,H.base+WATER_LEVEL,H.z))
    camera.useClipping=true
    camera.clipPlane=Plane(Vector3.UP,Vector3(H.x,H.base+WATER_LEVEL-.06,H.z))
    camera.autoAspectRatio=false
    -- A single reserved bit selects ordinary world drawables. Sky stays in the
    -- Zone's time-sliced cube; transparent black represents a miss in this view.
    camera.viewMask=MIRROR_VIEW
    if skybox and (skybox.viewMask & MIRROR_VIEW)~=0 then
        r.skybox=skybox
        skybox.viewMask=skybox.viewMask & ~MIRROR_VIEW
    end
    r.view=Viewport:new(scene,camera)
    r.view.drawDebug=false
    local forward=cache:GetResource('XMLFile','RenderPaths/Forward.xml')
    if not forward then return false end
    r.view:SetRenderPath(forward)
    -- Opaque and alpha-tested voxel/leaf geometry plus actual local lights.
    -- Exclude transparent passes (including their scene-colour copies) and post FX.
    local path=r.view:GetRenderPath()
    local hasBase=false
    for i=path:GetNumCommands()-1,0,-1 do
        local cmd=path:GetCommand(i)
        if cmd.type==CMD_CLEAR then
            cmd.useFogColor=false
            cmd.clearColor=Color(0,0,0,0)
        elseif cmd.type==CMD_SCENEPASS and cmd.pass=='base' then
            hasBase=true
        elseif cmd.type~=CMD_FORWARDLIGHTS then
            path:RemoveCommand(i)
        end
    end
    if not hasBase then return false end
    r.surface:SetUpdateMode(SURFACE_MANUALUPDATE)
    r.surface:SetViewport(0,r.view)
    r.bindingAttempted=true
    return H.spring:SetSurfaceTexture('mirror_color',r.texture)
end

-- On the banks, aim the capture at the pool independently of camera yaw. A
-- stationary player can turn right around using the same projective texture.
function H.UpdateReflection(dt,scene,source,tier,skybox)
    if not H.spring then return end
    if not H.planarReflectionEnabled then H.ReleaseReflection(); return end
    if not H.poolBounds then
        H.poolBounds=BoundingBox(Vector3(H.x-18.5,H.base+WATER_LEVEL-.08,H.z-21),
            Vector3(H.x+5,H.base+WATER_LEVEL+.08,H.z+2.5))
    end
    local node=source.node
    local pos=node.worldPosition
    local beyondRange=(pos.x-H.x)^2+(pos.z-H.z)^2>110^2
    if mirror then
        -- A failed allocation follows the same lifetime as a live capture.
        -- Crossing back inside resets the grace period even with the pool offscreen.
        mirror.farSeconds=beyondRange and ((mirror.farSeconds or 0)+dt) or 0
        if mirror.farSeconds>=1 then H.ReleaseReflection(); return end
    end
    if pos.y<=H.base+WATER_LEVEL or beyondRange or source.viewMask & MIRROR_VIEW==0
        or source.frustum:IsInsideFast(H.poolBounds)==OUTSIDE then
        if mirror and mirror.queued then
            mirror.queued,mirror.weight,mirror.elapsed=false,0,1
            H.spring:SetShaderParameter('mirror_weight',Variant(0.0))
        end
        return
    end
    local profile=mirrorTiers[tier] or mirrorTiers.medium
    local sw,sh=graphics:GetWidth(),graphics:GetHeight()
    if sw<=0 or sh<=0 then return end
    local scale=math.min(.5,profile.size/math.max(sw,sh))
    local w,h=math.max(1,floor(sw*scale+.5)),math.max(1,floor(sh*scale+.5))
    if not mirror or mirror.w~=w or mirror.h~=h then
        H.ReleaseReflection()
        mirror={w=w,h=h,elapsed=1,weight=0}
        local ok,ready=pcall(createReflection,mirror,scene,skybox,w,h)
        if not ok or not ready then
            H.ReleaseReflection()
            mirror={w=w,h=h,failed=true}
            print('HomeSpring: local reflection unavailable; using Zone environment ('..tostring(ready)..')')
        end
    end
    local r=mirror
    if r.failed then return end
    if r.queued and r.weight<1 then
        r.weight=math.min(1,r.weight+dt/.22)
        H.spring:SetShaderParameter('mirror_weight',Variant(r.weight))
    end
    r.elapsed=r.elapsed+dt
    local interval=1/profile.hz
    if r.elapsed<interval then return end
    local centre=Vector3(H.x-7.5,H.base+WATER_LEVEL,H.z-5.25)
    local distance=sqrt((pos.x-centre.x)^2+(pos.z-centre.z)^2)
    local aim=math.max(0,math.min(1,(distance-5)/6))
    aim=aim*aim*(3-2*aim)
    local direction=aim==1 and (centre-pos):Normalized() or node.worldDirection
    -- Refresh still views for changing foliage and light. On low, wait up to
    -- two seconds and ignore small movements of the camera between captures.
    if r.queued and r.elapsed<profile.idleSeconds and (pos-r.eye):LengthSquared()<profile.moveMetres^2
        and direction:DotProduct(r.forward)>.9998 and source.fov==r.fov and source.zoom==r.zoom then return end
    r.elapsed=r.elapsed%interval
    local c=r.camera
    r.node:SetWorldTransform(pos,node.worldRotation)
    if aim>0 then
        r.node:SetWorldDirection((centre-pos):Normalized())
        if aim<1 then r.node.worldRotation=node.worldRotation:Slerp(r.node.worldRotation,aim) end
    end
    -- A queued reflection is a second scene view. Reusing the main flags here
    -- makes its Forward/base pass prepare the directional shadow map again and
    -- lets the view order move the map under the primary camera. Keep direct
    -- illumination in the reflection while excluding only shadow-map work.
    c.viewOverrideFlags=(source.viewOverrideFlags or 0) | MIRROR_VIEW_FLAGS
    -- Keep a guard band around the near shore even as waves displace the sample.
    c.fov,c.zoom,c.aspectRatio=source.fov,source.zoom/(1.36+.39*aim),sw/sh
    c.nearClip,c.farClip=source.nearClip,math.min(145,source.farClip,(pos-centre):Length()+38)
    c.lodBias=.8
    local sy=.5*c.zoom/math.tan(math.rad(c.fov)*.5)
    H.spring:SetShaderParameter('mirror_eye',Variant(Vector4(pos.x,pos.y,pos.z,H.base+WATER_LEVEL)))
    H.spring:SetShaderParameter('mirror_right',Variant(r.node.worldRight*(sy/c.aspectRatio)))
    H.spring:SetShaderParameter('mirror_up',Variant(r.node.worldUp*(-sy)))
    H.spring:SetShaderParameter('mirror_forward',Variant(r.node.worldDirection))
    r.surface:QueueUpdate()
    r.queued,r.eye,r.forward,r.fov,r.zoom=true,pos,direction,source.fov,source.zoom
end

local houseStage=0
local houseParts
local houseReady=false
local function inStage(p,n) return n>=p.first and n<=p.last end
local function enableHousePart(p,on)
    if p.on==on then return end
    if p.volume then
        -- Jolt uses the live filters; IsCollidable alone only governs adoption on load.
        p.volume.collisionMask=on and p.mask or 0
        p.volume.collisionLayer=on and p.layer or 0
    end
    p.node.enabled=on
    p.on=on
end
local function occupiesPart(p,pos,r,height)
    if not pos or not p.brush or p.mask==0 then return false end
    local b=p.brush
    local x,y,z=pos.x-H.x,pos.y-H.base,pos.z-H.z
    r=r+b.s*.5
    local i0,i1=b:Range(x-r,x+r,1)
    local j0,j1=b:Range(y-.20,y+height+.10,2)
    local k0,k1=b:Range(z-r,z+r,3)
    for i=i0,i1 do for k=k0,k1 do for j=j0,j1 do
        if b.grid:IsSolid(i,j,k) then return true end
    end end end
    return false
end
function H.GetHouseStage() return houseStage end
function H.SetHouseStage(stage)
    if type(stage)~='number' or stage%1~=0 or stage<0 or stage>3 then return false,'无效房屋阶段' end
    if stage==houseStage then return true end
    if houseParts and not houseReady then return false,'请等待家园展开' end
    if houseReady then
        local walker,dragonBounds
        if H.GetHouseOccupants then walker,dragonBounds=H.GetHouseOccupants() end
        for _,p in ipairs(houseParts) do
            if p.on~=inStage(p,stage) then
                local blocked=occupiesPart(p,walker,.5,1.85)
                for _,bounds in ipairs(dragonBounds or {}) do
                    if occupiesPart(p,bounds.base,bounds.radius,bounds.height) then blocked=true;break end
                end
                if blocked then return false,'请先离开即将变化的墙、楼板或屋顶' end
            end
        end
    end
    houseStage=stage
    for _,p in ipairs(houseParts or {}) do enableHousePart(p,inStage(p,stage)) end
    H.RefreshWindowLights(stage)
    return true
end

-- A staged part contributes its sockets on creation. Two short, down-facing
-- cones cover the nearest sills; the recessed panes carry the light at pond distance.
local windows={sockets={},lamps={},materials={},stage=0,active=false,budget=2,dimmer=0,spill=0}

function H.BindWindowMaterial(material)
    H.housing=material
    if not windows.materials[material] then
        windows.materials[material]=true
        material:SetShaderParameter('window_light',Variant(windows.active and windows.stage>0 and windows.dimmer or 0.0))
    end
end

local function chooseWindowLamp(previous)
    local best
    for _,s in ipairs(windows.sockets) do
        if s~=previous and windows.stage>=s.first and windows.stage<=s.last then
            -- Give the first lamp to the inhabited ground floor and the other
            -- to the highest visible storey. Priority breaks ties on that floor.
            if not best or (s.first==best.first and s.priority<best.priority)
                or (previous and s.first>best.first) or (not previous and s.first<best.first) then best=s end
        end
    end
    return best
end

function H.RefreshWindowLights(stage)
    windows.stage=stage
    for m in pairs(windows.materials) do
        m:SetShaderParameter('window_light',Variant(windows.active and stage>0 and windows.dimmer or 0.0))
    end
    local previous
    for i=1,2 do
        local socket
        if windows.active and stage>0 and i<=windows.budget and windows.spill>0 then socket=chooseWindowLamp(previous) end
        local lamp=windows.lamps[i]
        if socket then
            if not lamp then
                local node=socket.root:CreateChild('HomeWindowLight'..i)
                local light=node:CreateComponent('Light')
                light.lightType=LIGHT_SPOT; light.fov=54; light.range=1.05
                light.drawDistance=28; light.fadeDistance=19; light.specularIntensity=.08
                light.castShadows=false; light.affectVolumetricFog=false; light.volumetricFogIntensity=0
                lamp={node=node,light=light}; windows.lamps[i]=lamp
            end
            if lamp.socket~=socket then
                local nx,nz=socket.nx,socket.nz
                lamp.node.worldPosition=Vector3(H.x+socket.x-.125*nx,H.base+socket.y+.13,H.z+socket.z-.125*nz)
                lamp.node:SetWorldDirection(Vector3(.28*nx,-1,.28*nz):Normalized())
                lamp.light.color=socket.first==1 and Color(1,.69,.38) or Color(1,.60,.32)
                lamp.socket=socket
            end
            lamp.light.brightness=windows.spill
            lamp.node.enabled=true
            previous=socket
        elseif lamp then lamp.node.enabled=false end
    end
end

function H.RegisterWindowLamps(root,sockets,first,last)
    for _,s in ipairs(sockets) do
        windows.sockets[#windows.sockets+1]={root=root,first=first,last=last,x=s.x,y=s.y,z=s.z,
            nx=s.nx or 0,nz=s.nz or ((s.nx or 0)==0 and -1 or 0),priority=s.priority or 1}
    end
    H.RefreshWindowLights(windows.stage)
end

function H.SetWindowLightingActive(on,quality)
    local budget=quality and (quality=='low' and 1 or 2) or windows.budget
    if on==windows.active and budget==windows.budget then return end
    windows.active,windows.budget=on,budget
    H.RefreshWindowLights(windows.stage)
end

function H.Stop()
    houseParts,houseReady=nil,false
    H.ReleaseReflection()
    H.poolBounds=nil
    H.ClearRipples()
    H.SetWindowLightingActive(false)
    for _,lamp in ipairs(windows.lamps) do lamp.node:Remove() end
    windows.sockets,windows.lamps,windows.materials={},{},{}
    windows.stage,windows.active,windows.budget,windows.dimmer,windows.spill=0,false,2,0,0
    if H.meadowMaterial then H.meadowMaterial:SetSurfaceTexture('splat_map',nil) end
    H.spring,H.hearth,H.field,H.housing,H.meadowMaterial=nil,nil,nil,nil,nil
    H.lastDay,H.lastDusk,H.lastNight,H.zoneFallback=nil,nil,nil,nil
end

local function updateWater(dt,feet)
    for slot,wave in pairs(ripples) do
        wave.age=wave.age+dt
        if wave.age>=WAVE_LIFE then wave.strength=0; ripples[slot]=nil end
        H.spring:SetShaderParameter('foot_wave'..slot,Variant(Vector4(wave.x,wave.z,wave.age,wave.strength)))
    end
    local x,z,bed
    if feet and feet.y<=H.base+WATER_LEVEL+(wet and .04 or 0) then
        x,z=feet.x-H.x,feet.z-H.z
        bed=waterBed(x,z)
    end
    -- Permit solver slop on a submerged step and reject positions below the island.
    if not bed or feet.y<H.base+bed-.12 then
        wet=false
        return
    end
    if feet.y>H.base+WATER_LEVEL then
        -- Retain contact across the small surface swell, without counting dry travel.
        lastX,lastZ=x,z
        return
    end
    if wet then
        local distance=sqrt((x-lastX)^2+(z-lastZ)^2)
        if distance>=.035 then
            travel=travel+distance
            lastX,lastZ=x,z
        end
        stepTime=stepTime+dt
    end
    if not wet or (stepTime>=STEP_TIME and travel>=STEP_DISTANCE) then
        local strength=wet and .72 or 1
        ripples[nextSlot]={x=x,z=z,age=0,strength=strength}
        H.spring:SetShaderParameter('foot_wave'..nextSlot,Variant(Vector4(x,z,0,strength)))
        nextSlot=nextSlot%4+1
        stepTime,travel=0,0
        lastX,lastZ=x,z
    end
    wet=true
end

local function linearChannel(srgb)
    if srgb<=.04045 then return srgb/12.92 end
    return ((srgb+.055)/1.055)^2.4
end

function H.Update(dt,feet,dn)
    if H.spring then updateWater(dt,feet) end
    local day,dusk,night=floor(dn.day*128+.5)/128,floor(dn.dusk*128+.5)/128,floor(dn.nightK*128+.5)/128
    local zone=dn.zone
    local target=(dn.capture.ready or zone.envSpecTexture) and 0 or 1
    local fallback=target
    if H.zoneFallback then
        local step=math.min(dt/.32,1)
        fallback=math.max(H.zoneFallback-step,math.min(target,H.zoneFallback+step))
    end
    if day==H.lastDay and dusk==H.lastDusk and night==H.lastNight and fallback==H.zoneFallback then return end
    H.lastDay,H.lastDusk,H.lastNight=day,dusk,night
    H.zoneFallback=fallback
    if H.spring then
        local color=zone.fogColor
        local intensity=zone.envTextureSpecIntensity or 1
        H.spring:SetShaderParameter('zone_fallback',Variant(Vector4(linearChannel(color.r)*intensity,
            linearChannel(color.g)*intensity,linearChannel(color.b)*intensity,fallback)))
    end
    if H.meadowMaterial then H.meadowMaterial:SetShaderParameter('meadow_sun',Variant(day*(1-night))) end
    local dimmer=.035+.39*(1-day)+.10*dusk*(1-night)+.32*night
    local spill=1.15*math.max(0,1-day-.16)*(.65+.35*night)
    if dimmer~=windows.dimmer or spill~=windows.spill then
        windows.dimmer,windows.spill=dimmer,spill
        H.RefreshWindowLights(windows.stage)
    end
    if H.hearth then H.hearth.brightness=.78+.34*(1-day) end
end

local function brush(world,lo,hi,s)
    if activeJob then coroutine.yield() end
    local b=Brush.New(world,{origin=Vector3(H.x,H.base,H.z),min=lo,max=hi,size=s})
    if activeJob then activeJob.ids[b.volume:GetVolumeId()]=true end
    return b
end
local function lawnPath(x,z)
    return pool(x,z)<1.22 or abs(z-4)<1.35 and x<8 and x>-18 or abs(x-4)<1.3 and abs(z)<10
end
local function lawnMaterial(x,z,h)
    local patch=pattern(x*.65,z*.65)+.36*pattern(x*1.8,z*1.8)
    if h<0 then return patch>0 and P.SAND or P.STONE_MOSS end
    if pad(x,z)<8.85 or (x>9 and x<15 and z>-10 and z<0) then return P.STONE_B end
    if lawnPath(x,z) then
        return patch>0 and P.PATH or P.PATH_B
    end
    if patch>1.45 then return P.GRASS_D end
    if patch>.48 then return P.GRASS_B end
    return patch<-.65 and P.GRASS_C or P.GRASS_A
end

local function rockFloor(x,z,d)
    local rim=1.15+1.05*pattern(x*.51,z*.51)
    return math.max(-18,math.min(-2.5,floor((-3.5-rim-d*1.45)*2)*.5))
end

-- A bank rock may straddle both the fine turf and the coarser cliff below -2 m.
-- Keep only the rock cells outside their respective occupied columns. The union
-- stays identical, but the waterline and cliff no longer have two coplanar skins.
local function clearColumnRange(b,i,k,low,high)
    local j0,j1=b:Range(low,high,2)
    if j0<=j1 then b.grid:FillBox(i,j0,k,i,j1,k,false) end
end
local function trimGround(b)
    for i=0,b.nx-1 do for k=0,b.nz-1 do
        local x,_,z=b:Center(i,0,k)
        if edge(x,z)>0 then clearColumnRange(b,i,k,-2,top(x,z)) end
        if b.lmin[2]<-2 then
            local cx,cz=(floor(x*2)+.5)*.5,(floor(z*2)+.5)*.5
            local d=edge(cx,cz)
            if d>0 then clearColumnRange(b,i,k,rockFloor(cx,cz,d),-2) end
        end
    end end
end

-- Both brushes are aligned to island-local axes. The owning grid is the same
-- size or coarser, so each occupied vertical run can be removed in one box.
local function trimCovered(b,owner)
    local s=owner.s
    local ix0,ix1=owner:Range(b.lmin[1],b.lmin[1]+b.nx*b.s,1)
    local iy0,iy1=owner:Range(b.lmin[2],b.lmin[2]+b.ny*b.s,2)
    local iz0,iz1=owner:Range(b.lmin[3],b.lmin[3]+b.nz*b.s,3)
    if ix0>ix1 or iy0>iy1 or iz0>iz1 then return end
    for i=ix0,ix1 do
        if activeJob and (i-ix0)%16==0 then coroutine.yield() end
        for k=iz0,iz1 do
            local x,z=owner.lmin[1]+i*s,owner.lmin[3]+k*s
            local start=nil
            for j=iy0,iy1+1 do
                if j<=iy1 and owner.grid:IsSolid(i,j,k) then
                    start=start or j
                elseif start then
                    b:Carve(x,owner.lmin[2]+start*s,z,x+s,owner.lmin[2]+j*s,z+s)
                    start=nil
                end
            end
        end
    end
end

local function terrain(world)
    local rocks={P.DEEP_A,P.CLIFF_C,P.CLIFF_B,P.CLIFF_A}
    for bx=-28,14,14 do for bz=-21,7,14 do
        local b=brush(world,{bx,-18,bz},{bx+14,-2,bz+14},.5)
        for i=0,b.nx-1 do for k=0,b.nz-1 do
            local x,z=bx+(i+.5)*.5,bz+(k+.5)*.5
            local d=edge(x,z)
            if d>0 then
                local low=rockFloor(x,z,d)
                local first=floor((low+18)*2)
                b.grid:FillBox(i,first,k,i,b.ny-1,k,true)
                local tilt=pattern(x*.70,z*.70)
                for j=first,b.ny-1,4 do
                    local band=math.max(1,math.min(4,4+floor((j*.5-18)*.2+tilt*.85)))
                    b.grid:PaintBox(i,j,k,i,math.min(j+3,b.ny-1),k,rocks[band])
                end
            end
        end end
        b:Finish()
        local cap=brush(world,{bx,-2,bz},{bx+14,2,bz+14},.25)
        local g=cap.grid
        for i=0,cap.nx-1 do for k=0,cap.nz-1 do
            local x,z=bx+(i+.5)*.25,bz+(k+.5)*.25
            if edge(x,z)>0 then
                local h=top(x,z)
                local last=floor((h+2)*4)-1
                local skin=lawnMaterial(x,z,h)
                g:FillBox(i,0,k,i,last,k,true)
                if last>0 then
                    local grain=pattern(x*.72,z*.72)
                    g:PaintBox(i,0,k,i,last-1,k,grain>0 and P.CLIFF_A or P.CLIFF_B)
                    if skin>=P.GRASS_A and skin<=P.GRASS_D then
                        g:PaintBox(i,math.max(0,last-(grain>.55 and 2 or 1)),k,i,last-1,k,grain>0 and P.DIRT or P.DIRT_B)
                    end
                end
                g:SetVoxelMaterial(i,last,k,skin)
            end
        end end
        cap:Finish({masonry='meadow'})
    end end
end
-- The coarse solids still own collision. Only the exposed outside courses use the fine grid.
local function columnTrim(world,owner,x,z,y,h,building)
    local s=owner.s
    -- A circular placement can land between grid lines. Use the actual cap faces on each axis.
    local function capEdges(center,axis)
        local origin=owner.lmin[axis]
        local first=math.ceil((center-.75-origin)/s-.5-1e-6)
        local last=floor((center+.75-origin)/s-.5+1e-6)
        return origin+first*s,origin+(last+1)*s
    end
    local x0,x1=capEdges(x,1)
    local z0,z1=capEdges(z,3)
    local cap=y+h+.25
    local foot=math.max(y,top(x,z),pad(x,z)<=8.55 and 1.75 or y)
    local function detailBrush(bottom,ceiling)
        return brush(world,{x0-.125,bottom,z0-.125},{x1+.125,ceiling,z1+.125},.0625)
    end
    local function courses(trim,level,bands)
        for _,band in ipairs(bands) do
            local offset,mat=band[3],band[4]
            trim:Shape(x0-offset,level+band[1],z0-offset,x1+offset,level+band[2],z1+offset,function(px,py,pz)
                if owner:IsSolidLocal(px,py,pz) or py<top(px,pz) then return end
                local dx,dz=floor(px*4)*.25+.125,floor(pz*4)*.25+.125
                if py>=1.5 and py<1.75 and pad(dx,dz)<=8.55 then return end
                -- Keep the sheared face of the south relic and the openings of both old arches.
                if building and (pz<owner.lmin[3] or building:IsSolidLocal(px,py,pz)) then return end
                return mat
            end)
        end
    end
    -- Short exposed shafts use a shallower neck and one compact detail volume.
    -- On high columns the two thin brushes avoid allocating the empty span of the shaft.
    local exposed=cap-foot
    local short=exposed<=1.5
    local capital=detailBrush(short and foot or cap-.5625,cap+.0625)
    if exposed>=.875 then
        local base=short and capital or detailBrush(foot,foot+.4375)
        courses(base,foot,{{0,.125,.125,P.HOME_PLINTH},{.125,.1875,.0625,P.HOME_COPING},
            {.1875,.3125,-.0625,P.HOME_PLINTH},{.3125,.375,0,P.HOME_COPING},
            {.375,.4375,-.125,P.HOME_PLINTH}})
        if not short then base:Finish({visual=true,masonry='homeMasonry'}) end
    end
    courses(capital,cap,{{short and -.5 or -.5625,-.4375,-.0625,P.HOME_PLINTH},
        {-.4375,-.375,.0625,P.HOME_COPING},{-.1875,-.0625,.0625,P.HOME_COPING},
        {0,.0625,-.0625,P.HOME_COPING}})
    capital:Finish({visual=true,masonry='homeMasonry'})
end
local function column(b,columns,x,z,y,h)
    b:Box(x-.75,y,z-.75,x+.75,y+.5,z+.75,P.HOME_PLINTH)
    b:Box(x-.5,y+.5,z-.5,x+.5,y+h,z+.5,P.HOME_ASHLAR)
    b:Box(x-.125,y+.9,z-.625,x+.125,y+h-.35,z-.5,P.HOME_PLINTH)
    b:Box(x-.625,y+h-.5,z-.625,x+.625,y+h-.25,z+.625,P.HOME_PLINTH)
    b:Box(x-.75,y+h-.25,z-.75,x+.75,y+h+.25,z+.75,P.HOME_COPING)
    columns[#columns+1]={x,z,y,h}
end
local function trimColumns(world,b,columns,building)
    for _,p in ipairs(columns) do columnTrim(world,b,p[1],p[2],p[3],p[4],building) end
end
local function entranceColumn(world,x,z,h)
    local y=1.5
    local b=brush(world,{x-.75,y,z-.75},{x+.75,y+h+.25,z+.75},.125)
    b:Box(x-.75,y,z-.75,x+.75,y+.375,z+.75,P.HOME_PLINTH)
    b:Box(x-.625,y+.375,z-.625,x+.625,y+.625,z+.625,P.HOME_PLINTH)
    b:Shape(x-.5,y+.625,z-.5,x+.5,y+h-.25,z+.5,function(px,_,pz)
        if abs(px-x)+abs(pz-z)<.82 then return P.HOME_ASHLAR end
    end)
    b:Box(x-.625,y+h-.25,z-.625,x+.625,y+h,z+.625,P.HOME_PLINTH)
    b:Box(x-.75,y+h,z-.75,x+.75,y+h+.25,z+.75,P.HOME_COPING)
    b:Finish({masonry='homeMasonry'})
    columnTrim(world,b,x,z,y,h)
end
local function courtyard(world)
    local columns={}
    local b=brush(world,{2,1, -7},{22,6,13},.25)
    b:Shape(3,1.5,-6,21,1.75,12,function(x,_,z)
        if pad(x,z)<=8.55 then return P.HOME_PAVING end
    end)
    for i=0,11 do
        local a=i*math.pi/6
        if i~=9 and i~=6 and i~=5 and i~=7 then column(b,columns,12+8.3*cos(a),3+8.3*sin(a),1.5,i%4==1 and 2.75 or 1.25) end
    end
    b:Finish({masonry='homeMasonry'})
    trimColumns(world,b,columns)
    entranceColumn(world,4.875,7.125,2.75)
    entranceColumn(world,4.875,-1.125,1.25)
end
local function arch(b,columns,x,z,w,spring,rise)
    for _,side in ipairs({-1,1}) do column(b,columns,x+side*w,z,0,spring) end
    b:Shape(x-w-1,spring-.5,z-.625,x+w+1,spring+rise+1.25,z+.625,function(px,y,pz)
        local dx,dy=(px-x)/w,(y-spring)/rise
        local r=sqrt(dx*dx+dy*dy)
        if dy>=0 and r>=.88 and r<=1.13 then
            local wedge=floor(math.atan(dy,dx)*14)
            return wedge%7==1 and P.STONE_MOSS or (wedge%3==0 and P.STONE_C or P.MARBLE_A)
        end
    end)
end
-- Reuse the upper storeys' staggered clay tiles, raised rolls and capped ridge.
local function tiledRoof(b,cx,cz,halfRidge,halfRun,eave,rise,frontGable)
    local along=frontGable and cz or cx
    require('ruins.HomeHouseUpper').TileRoof(b,frontGable,frontGable and cx or cz,halfRun,
        along-halfRidge,along+halfRidge,eave-.25,rise)
end
local function houseBase(ctx)
    local b=ctx.brush({-16.5,0,3.5},{-.75,.75,13.25},.125)
    b:Box(-16.25,0,6.75,-.75,.625,13.25,P.HOME_PLINTH)
    b:Box(-16.125,.625,6.875,-.875,.75,13.125,P.HOME_PAVING)
    b:Box(-7,0,4,-1.5,.625,7,P.HOME_PLINTH)
    b:Box(-7,.625,4,-1.5,.75,7,P.HOME_PAVING)
    b:Box(-5.625,0,3.5,-2.875,.25,4,P.HOME_COPING)
    b:Box(-5.625,.25,3.75,-2.875,.5,4,P.HOME_COPING)
    ctx.finish('foundation',b,0,3,{masonry='homeMasonry'})
end
local function fallenHouse(ctx)
    local b=ctx.brush({-16,.75,6.875},{-1,3.25,13},.25)
    -- Rear and side walls survive in broad courses. The collapsed frontage has gaps down to the slab.
    for _,p in ipairs({{-16,12.5,-12,13,2.00},{-12,12.5,-9.5,13,1.75},{-9.5,12.5,-8,13,1.50},
        {-8,12.5,-2.5,13,1.75},{-2.5,12.5,-1,13,2.00},{-16,8.5,-15.5,10,1.25},{-16,10,-15.5,12.5,1.75},
        {-1.5,10,-1,12.5,1.50},{-1.5,9,-1,10,1.00},{-16,7,-13,7.5,1.25},{-13,7,-12,7.5,1.00},
        {-10.5,7,-8.75,7.5,1.00},{-8.75,7,-7.75,7.5,1.25},{-2.5,7,-1,7.5,1.00}}) do
        b:Box(p[1],.75,p[2],p[3],p[5],p[4],P.HOME_ASHLAR)
    end
    for i,p in ipairs({{-15.75,7.25,1.75},{-8.5,7.25,1.50},{-1.5,12.5,2.25},{-12,12.5,2.25}}) do
        b:Box(p[1]-.25,.75,p[2]-.25,p[1]+.5,p[3],p[2]+.5,P.HOME_ASHLAR)
        b:Box(p[1]-.25,p[3],p[2]-.25,p[1]+.5,p[3]+.25,p[2]+.5,i==4 and P.STONE_MOSS or P.HOME_COPING)
    end
    for i,p in ipairs({{-14.5,7.75},{-13.75,8.25},{-11.5,7.75},{-10.75,8},{-8.75,11.5},
        {-7.25,12},{-6.75,11.5},{-3.5,11.75},{-2.5,9.5},{-14.75,11.75}}) do
        b:Box(p[1],.75,p[2],p[1]+(i%3+1)*.25,1,p[2]+.5,i%4==1 and P.STONE_MOSS or P.STONE_C)
        if i%3==1 then b:Box(p[1],1,p[2],p[1]+.25,1.25,p[2]+.25,P.LEAF_C) end
    end
    ctx.finish('ruin',b,0,0,{masonry='homeWindows'})
end
local function archedWindow(b,along,face,normal,side)
    -- u spans the opening; depth increases toward the inside of each wall.
    local function box(u,y,d,uu,yy,dd,mat)
        local a,c=face-normal*d,face-normal*dd
        if side then b:Box(a,y,along+u,c,yy,along+uu,mat) else b:Box(along+u,y,a,along+uu,yy,c,mat) end
    end
    box(-.875,1.25,0,.875,3.375,.375,false)
    -- Elliptical crown over straight jambs. Frame, inset glazing and crossbars have separate depths.
    local function arch(px,py,pz)
        local dx=abs((side and pz or px)-along)
        local depth=(face-(side and px or pz))*normal
        local dy=math.max(0,py-2.5)
        local outer=dx*dx+dy*dy/.875^2
        local inner=(dx/.75)^2+(dy/.625)^2
        if inner<1 and py>1.5 then
            if depth>=.125 and depth<.25 then return window end
            return false
        elseif outer<=1 then
            return P.HOME_COPING
        elseif depth>=0 then return P.HOME_ASHLAR end
    end
    local outer,inner=face+normal*.125,face-normal*.375
    if side then b:Shape(outer,1.25,along-1,inner,3.5,along+1,arch)
    else b:Shape(along-1,1.25,outer,along+1,3.5,inner,arch) end
    box(-1.125,1.25,-.25,1.125,1.5,.25,P.HOME_PLINTH)
    box(-.75,1.375,0,.75,1.5,.125,P.HOME_WINDOW_REVEAL)
end
-- Pond elevation, scaled between the two outside wall faces (15 m).
-- The three window axes sit at 7%, 21% and 43% of that span. The shallow
-- 1/16 m front wall meets the 1/8 m side walls at Z=7.375.
local frontWindows={
    {x=-14.9375,r=.375,sill=1.375,spring=2.625,rise=.375,panes=2},
    {x=-12.875,r=.6875,sill=1.3125,spring=2.5625,rise=.5625,panes=4},
    {x=-9.625,r=.5,sill=1.375,spring=2.5625,rise=.4375,panes=3},
}
local doorX=-4.625
local function frontWindow(b,w)
    local cell=.0625
    local trim=.125
    local topY=w.spring+w.rise
    b:Shape(w.x-w.r-trim,w.sill,6.875,w.x+w.r+trim,topY+trim,7.375,function(x,y,z)
        local u=x-w.x
        local dy=math.max(0,y-w.spring)
        local outer=(u/(w.r+trim))^2+(dy/(w.rise+trim))^2
        if outer>1 then return end
        local inner=(u/w.r)^2+(dy/w.rise)^2
        if inner>=1 then
            local wedge=floor(math.atan(dy/w.rise,u/w.r)*9/math.pi)
            return dy>0 and wedge%3==1 and P.HOME_ASHLAR or P.HOME_COPING
        end
        -- Bare reveal at the front, wood sash and a separate recessed glass plane.
        if z<7.125 or z>=7.3125 then return false end
        local frame=(u/(w.r-cell))^2+(dy/(w.rise-cell))^2>=1 or y<w.sill+cell
        if frame then return cedarPost end
        return z>=7.25 and window or false
    end)
    b:Box(w.x-w.r-.1875,w.sill-.125,6.75,w.x+w.r+.1875,w.sill,7.25,P.HOME_COPING)
    b:Box(w.x-w.r,w.sill,7,w.x+w.r,w.sill+.0625,7.125,P.HOME_WINDOW_REVEAL)
end

local function wallLantern(b,x,y)
    b:Box(x-.0625,y,6.875,x+.0625,y+.375,7,slate)
    b:Box(x-.0625,y+.25,6.6875,x+.0625,y+.3125,6.9375,slate)
    b:Box(x-.1875,y+.1875,6.5,x+.1875,y+.25,6.8125,slate)
    b:Box(x-.125,y-.125,6.5625,x+.125,y+.1875,6.75,window)
    for _,edgeX in ipairs({x-.125,x+.0625}) do
        b:Box(edgeX,y-.125,6.5625,edgeX+.0625,y+.1875,6.625,P.GOLD_DARK)
    end
    b:Box(x-.125,y-.1875,6.5625,x+.125,y-.125,6.75,slate)
    b:Box(x-.0625,y-.25,6.625,x+.0625,y-.1875,6.6875,P.GOLD_DARK)
end

local function planter(b,x,y,width)
    local left,right=x-width/2,x+width/2
    b:Box(left,y,6.4375,right,y+.25,6.875,oak)
    b:Box(left-.0625,y+.1875,6.375,right+.0625,y+.3125,6.9375,cedar)
    for i=0,floor(width/.25)-1 do
        local stem=left+.125+i*.25
        local z=6.5+(i%3)*.0625
        local h=y+.4375+(i*2%3)*.0625
        b:Box(stem-.125,y+.3125,z-.0625,stem+.125,h,z+.125,i%3==1 and P.LEAF_C or P.LEAF_A)
        if i%3~=1 then b:Box(stem-.0625,h,z,stem+.0625,h+.0625,z+.125,i%2==0 and P.FLOWER_W or P.FLOWER_B) end
    end
end

local function frontWall(ctx)
    local b=ctx.brush({-16,.75,6.375},{-1,3.5,7.375},.0625)
    b:Box(-16,.75,7,-1,3.5,7.375,P.HOME_ASHLAR)
    for _,w in ipairs(frontWindows) do frontWindow(b,w) end
    -- The voussoirs, darker inner jamb and inset arched transom have separate depths.
    b:Shape(doorX-1.375,.75,6.875,doorX+1.375,3.5,7.375,function(x,y,z)
        local u=x-doorX
        local dy=math.max(0,y-2.75)
        if (u/1.375)^2+(dy/.75)^2>1 then return end
        if (u/1.1875)^2+(dy/.5625)^2>=1 then return P.HOME_COPING end
        if z<7.125 then return false end
        if abs(u)>=1.125 or (y>=2.875 and y<3) then return cedar end
        if y>=3 then
            if z>=7.3125 or z<7.1875 then return false end
            if abs(u)<.0625 or abs(abs(u)-(y-2.875)*1.2)<.045 then return cedarPost end
            return z>=7.25 and window or false
        end
        return false
    end)
    for _,x in ipairs({-15.875,-11,-7.875,-1.25}) do
        b:Box(x,.875,6.9375,x+.1875,3.5,7.0625,cedarPost)
        b:Box(x-.0625,.75,6.875,x+.25,1.0625,7.125,P.HOME_PLINTH)
    end
    for _,x in ipairs({-13.9375,-11.6875,-8.6875,-6.1875,-3.0625}) do wallLantern(b,x,2.1875) end
    -- Iron brackets anchor the wide window box. Low beds further along sit on the plinth.
    for _,x in ipairs({-13.4375,-12.3125}) do
        b:Box(x-.0625,.875,6.5,x+.0625,1.0625,7,P.GOLD_DARK)
    end
    planter(b,-12.875,1.0625,1.625)
    for _,bed in ipairs({{-15.125,1},{-10.875,1},{-7.375,1},{-2.125,.75}}) do
        local x,width=bed[1],bed[2]
        b:Box(x-width/2,.75,6.75,x+width/2,.875,7,P.HOME_PLINTH)
        planter(b,x,.875,width)
    end
    ctx.finish('ground-front',b,1,3,{masonry='homeWindows'})
end

-- Each strip is two 1/32 m cells deep, directly in front of its glass.
-- Group coplanar windows while keeping the longest brush below 255 cells.
local function windowBars(ctx,name,windows,face,normal,side,inset)
    local cell=.03125
    local near,far=face-normal*(inset-2*cell),face-normal*inset
    local lo,hi=math.min(near,far),math.max(near,far)
    local left,right=windows[1].x-windows[1].r,windows[#windows].x+windows[#windows].r
    local function coords(u,y,d) return side and {d,y,u} or {u,y,d} end
    local b=ctx.brush(coords(left,1.3125,lo),coords(right,3.125,hi),cell)
    for _,w in ipairs(windows) do
        local function lattice(x,y,z)
            local u=(side and z or x)-w.x
            local dy=math.max(0,y-w.spring)
            if (u/w.r)^2+(dy/w.rise)^2>=1 then return end
            local pane=(u+w.r)*w.panes/(2*w.r)
            local bar=floor(pane+.5)
            local barX=-w.r+bar*2*w.r/w.panes
            local halfWidth=(w.panes==4 and bar==2) and cell or cell/2
            if bar>0 and bar<w.panes and u>=barX-halfWidth and u<barX+halfWidth then return cedarPost end
            if (y>=w.sill+.5 and y<w.sill+.5+cell) or (y>=w.spring and y<w.spring+2*cell) then return cedar end
            if dy>0 and abs(abs(u)-dy*.82)<cell*.6 then return oak end
        end
        local a=coords(w.x-w.r,w.sill,lo)
        local c=coords(w.x+w.r,w.spring+w.rise,hi)
        b:Shape(a[1],a[2],a[3],c[1],c[2],c[3],lattice)
    end
    ctx.finish(name,b,1,3,{visual=true,masonry='homeWindows'})
end

local function porchDoors(ctx)
    -- Open leaves have individual tight brushes. The panel beads, rails and
    -- panes have separate depths within each grid, leaving a clear centre.
    local cell=.03125
    local alongX=.40625
    local alongZ=sqrt(1-alongX^2)
    for _,sign in ipairs({-1,1}) do
        local hinge=doorX-sign*1.125
        local tip=hinge+sign*.46875
        local left,right=math.min(hinge,tip)-.125,math.max(hinge,tip)+.125
        local b=ctx.brush({left,.75,7.25},{right,2.875,8.5625},cell)
        b:Box(hinge-.09375,.75,7.25,hinge+.09375,2.875,7.53125,cedarPost)
        b:Shape(left,.78125,7.375,right,2.875,8.5625,function(x,y,z)
            local dx,dz=(x-hinge)*sign,z-7.4375
            local u,d=dx*alongX+dz*alongZ,dx*alongZ-dz*alongX
            if u<0 or u>1.125 or abs(d)>.09375 then return end
            if d>.0625 and u>.9375 and u<1.03125 and y>=1.5625 and y<1.6875 then return P.GOLD_DARK end
            local low=y<1.6875
            local bottom,topY=low and .9375 or 1.8125,low and 1.5625 or 2.6875
            local edge=math.min(u-.125,1-u,y-bottom,topY-y)
            if edge<0 then return abs(d)<=.0625 and cedar or nil end
            if edge<cell then return oak end
            if low then return abs(d)<=cell and oak or nil end
            if abs(u-.5625)<cell/2 or (y>=2.25 and y<2.25+cell) then return abs(d)<=.0625 and cedarPost or nil end
            return abs(d)<=cell and window or nil
        end)
        ctx.finish(sign==1 and 'ground-door-left' or 'ground-door-right',b,1,3,{masonry='homeWindows'})
    end
end

local function porchTimber(ctx,ridge)
    local b=ctx.brush({ridge-2.875,1.25,3.625},{ridge+2.875,4.875,4.5},.0625)
    for _,x in ipairs({ridge-2.25,ridge+2.25}) do
        b:Box(x-.125,1.25,4.125,x+.125,3,4.375,cedarPost)
        b:Box(x-.1875,2.875,4.0625,x+.1875,3.0625,4.4375,oak)
        b:Box(x-.125,3,3.75,x+.125,3.3125,4.5,cedarBeamZ)
        -- Through-tenon with a narrowed shoulder and a pin standing proud of its end grain.
        b:Box(x-.0625,3.0625,3.6875,x+.0625,3.1875,3.75,oakPlankZ)
        b:Box(x,3.0625,3.625,x+.0625,3.125,3.6875,P.WOOD)
    end
    b:Box(ridge-2.5625,3.0625,3.8125,ridge+2.5625,3.3125,4.125,cedar)
    b:Box(ridge-.125,3.1875,3.75,ridge+.125,4.8125,3.9375,cedarPost)
    b:Box(ridge-.125,3.0625,3.6875,ridge+.125,3.25,3.8125,oak)
    b:Shape(ridge-2.875,2.375,3.75,ridge+2.875,4.875,4.3125,function(x,y,z)
        local u=abs(x-ridge)
        if z<3.9375 and abs(y-(4.75-.61*u))<.109375 then return cedar end
        if z>=3.9375 and z<4.0625 and u<=1.125 and abs(y-(3.25+.76*u))<.078125 then return oak end
        if z>=4.125 and u>=1.375 and u<=2.25 and abs(y-(3.25-.88*(u-1.375)))<.09375 then return cedar end
    end)
    ctx.finish('ground-porch-frame',b,1,3,{masonry='homeWindows'})
    local rails=ctx.brush({ridge-2.375,3,4.5},{ridge+2.375,3.3125,7.125},.0625)
    for _,x in ipairs({ridge-2.25,ridge+2.25}) do
        rails:Box(x-.125,3,4.5,x+.125,3.3125,7.125,cedarBeamZ)
    end
    ctx.finish('ground-porch-rails',rails,1,3,{masonry='homeWindows'})
end

local function firstStorey(ctx)
    local b=ctx.brush({-16.5,.75,3.375},{-.75,5.125,13.25},.125)
    b:Box(-16,.75,7.375,-1,3.75,13,P.HOME_ASHLAR)
    b:Carve(-15.625,.75,7.375,-1.375,3.75,12.625)
    archedWindow(b,10.75,-16,-1,true)
    archedWindow(b,11.375,-1,1,true)
    for _,x in ipairs({-12.5,-7}) do archedWindow(b,x,13,1,false) end
    b:Box(-16,3.5,6.875,-1,3.75,7.375,cedar)
    local ridge=-4.125
    for _,x in ipairs({-6.375,-1.875}) do
        b:Box(x-.3125,.75,4,x+.3125,1.125,4.625,P.HOME_PLINTH)
        b:Box(x-.25,1.125,4,x+.25,1.25,4.625,P.HOME_COPING)
    end
    tiledRoof(b,ridge,5.3125,1.8125,2.875,3.125,1.875,true)
    ctx.finish('ground-floor',b,1,3,{masonry='homeWindows',windowLamps={
        {x=frontWindows[2].x,y=1.875,z=7,nz=-1,priority=1},
        {x=frontWindows[3].x,y=1.875,z=7,nz=-1,priority=2}}})
    frontWall(ctx)
    porchTimber(ctx,ridge)
    porchDoors(ctx)
    windowBars(ctx,'ground-front-bars',frontWindows,7,-1,false,.25)
    local function sideWindow(x) return {x=x,r=.75,sill=1.5,spring=2.5,rise=.625,panes=3} end
    windowBars(ctx,'ground-west-bars',{sideWindow(10.75)},-16,-1,true,.125)
    windowBars(ctx,'ground-east-bars',{sideWindow(11.375)},-1,1,true,.125)
    windowBars(ctx,'ground-back-bars',{sideWindow(-12.5),sideWindow(-7)},13,1,false,.125)
end
local function singleRoof(ctx)
    local b=ctx.brush({-16.75,3.625,6.25},{-.25,6.5,13.75},.125)
    tiledRoof(b,-8.5,10,8,3.625,3.875,2.5,false)
    for _,x in ipairs({-16,-1.25}) do
        b:Shape(x,3.75,7,x+.25,6.125,13,function(_,y,z)
            if y<=6.125-abs(z-10)*.69 then return abs(z-10)<.13 and cedarPost or P.STONE_A end
        end)
    end
    b:Box(-12.5,4.625,10.75,-11.75,6.375,11.5,P.HOME_ASHLAR)
    b:Box(-12.625,6.375,10.625,-11.625,6.5,11.625,P.HOME_COPING)
    b:Carve(-12.25,6.125,11,-12,6.5,11.25)
    ctx.finish('one-storey-roof',b,1,1,{masonry='homeWindows'})
end

local function house(world,scene)
    local old=brush(world,{-22,0,6},{5,12,17},.25)
    local columns={}
    arch(old,columns,-9.5,13.5,6,5,5.25); arch(old,columns,-18,9,2.8,3.25,3.1)
    for _,p in ipairs({{-20,6,5.25},{2.5,11.5,6},{-1,15,4.5}}) do column(old,columns,p[1],p[2],0,p[3]) end
    trimGround(old)
    old:Finish({masonry='ashlar'})
    local b=brush(world,{-.625,0,4.5},{3,5.25,10.125},.125)
    -- Stone oven with a recessed vaulted mouth, coals and an iron anvil.
    b:Box(-.5,0,7.125,2.875,2.875,10,P.HOME_HEARTH)
    -- The voussoirs continue three voxels into the reveal; the original opening trims their inner edge.
    b:Shape(-.5,1.375,7.125,2.875,2.875,7.5,function(x,y)
        local dx,dy=(x-1.2)/1.25,(y-1.4)/1.05
        if dy>=0 and dx*dx+dy*dy<=1.34^2 then return P.HOME_ARCH end
    end)
    b:Shape(-.125,.5,7,2.5,2.75,9.375,function(x,y) if y<1.4+1.05*sqrt(math.max(0,1-((x-1.2)/1.25)^2)) then return false end end)
    b:Box(0,.5,7.375,2.375,.75,9.375,ember)
    for j=0,6 do local x=.125+j*.3125; b:Box(x,.75,8.375,x+.25,1+(j*3%5)*.125,9,flame) end
    b:Box(-.625,2.875,7,3,3.25,10.125,P.HOME_COPING); b:Box(.5,3.25,8.5,1.75,5.25,9.75,P.HOME_HEARTH)
    b:Box(.625,0,4.625,1.625,.75,5.625,P.WOOD); b:Box(.375,.75,4.5,1.875,1,5.75,slate)
    b:Box(.875,1,4.875,1.375,1.375,5.5,slate); b:Box(.125,1.375,4.75,2.125,1.625,5.625,slate)
    trimGround(b)
    trimCovered(b,old)
    b:Finish({masonry='homeWindows'})
    -- Project the cut stone face one fine cell, and the keystone two. Read the finished opening
    -- so the lip cannot bridge a stair in the vaulted reveal or change the solid furnace.
    local lip=brush(world,{-.5,1.375,7},{2.875,2.875,7.125},.0625)
    local k=math.floor((7.1875-b.lmin[3])/b.s)
    lip:Shape(-.5,1.375,7,2.875,2.875,7.125,function(x,y,z)
        local i,j=math.floor((x-b.lmin[1])/b.s),math.floor((y-b.lmin[2])/b.s)
        if b.grid:GetVoxelMaterial(i,j,k)==P.HOME_ARCH and b.grid:IsSolid(i,j,k) then
            if z>=7.0625 or abs((x-1.2)/1.25)<(y-1.4)/1.05*.1438 then return P.HOME_ARCH end
        end
    end)
    lip:Finish({visual=true,masonry='homeMasonry'})
    houseParts={}
    houseReady=false
    local ctx={brush=function(lo,hi,size) return brush(world,lo,hi,size) end}
    function ctx.finish(name,part,first,last,options)
        trimGround(part)
        trimCovered(part,old)
        trimCovered(part,b)
        -- Earlier permanent pieces own their cells, including the porch where the roof returns.
        for _,p in ipairs(houseParts) do
            if p.first<=first and last<=p.last then trimCovered(part,p.brush) end
        end
        local v=part:Finish(options)
        if not v then return end
        local node=v:GetNode()
        node.name=options.nodeName or ('HomeHouse-'..name)
        local entry={volume=v,node=node,brush=part,first=first,last=last,mask=v.collisionMask,layer=v.collisionLayer}
        houseParts[#houseParts+1]=entry
        enableHousePart(entry,inStage(entry,houseStage))
        if options.windowLamps and scene then H.RegisterWindowLamps(scene,options.windowLamps,first,last) end
        return v
    end
    houseBase(ctx)
    fallenHouse(ctx)
    firstStorey(ctx)
    singleRoof(ctx)
    local upper=require('ruins.HomeHouseUpper')
    local groups={second={2,3},secondRoof={2,2},third={3,3}}
    upper.Build(ctx.brush,function(name,part,options)
        local ages=groups[name]
        ctx.finish(name,part,ages[1],ages[2],options)
    end)
    local structure={IsSolidLocal=function(_,x,y,z)
        if b:IsSolidLocal(x,y,z) then return true end
        for _,p in ipairs(houseParts) do
            if p.brush:IsSolidLocal(x,y,z) then return true end
        end
        return false
    end}
    trimColumns(world,old,columns,structure)
    houseReady=true
    H.RefreshWindowLights(houseStage)
end
local function banks(world)
    local b=brush(world,{-21,-1.5,-19},{5,5,4},.25)
    local rng=Noise.Rng(8305)
    for i=0,71 do
        local a=i*math.pi/36;local x,z=-7.5+10.25*cos(a),-5.25+6.5*sin(a)
        if not channel(x,z) and not(abs(x+4)<1.75 and z>0) and not(x>0 and z>=-6.5 and z<=-3.75) then
            local rx,rz=rng:Range(.47,.95),rng:Range(.38,.78)
            local crest=rng:Int(0,2)*.25
            b:Ellipsoid(x,-.5,z,rx,crest+.55,rz,rng:Next()<.35 and P.STONE_MOSS or P.STONE_C)
        end
    end
    for i=0,16 do local z=2-i*.5
        b:Box(-5.5,.25,z-.375,-2.75,.5,z+.0625,i%4==1 and amber or oak)
    end
    for _,z in ipairs({1.5,-2.5,-5.75}) do for _,x in ipairs({-5.25,-3}) do
        b:Box(x-.25,-1.5,z-.25,x+.25,.875,z+.25,cedarPost)
    end end
    local columns={}
    for _,p in ipairs({{-18,-7,2.75},{-14,-13,1.5},{2,-8,2.0},{4,2,3}}) do column(b,columns,p[1],p[2],0,p[3]) end
    -- Terraced front parapet follows the pond lip, with an open spillway and stair entrance.
    for i=0,31 do
        local a=math.pi+i*math.pi/31
        local x,z=-7.5+11*cos(a),-5.25+7.5*sin(a)
        if not channel(x,z) then
            local broken=sin(a*5+.3)+.5*sin(a*9)<-.55
            local h=broken and .25 or (i%8==0 and 1.25 or .5)
            local wide=broken and .45 or .75
            b:Box(x-wide+.125,0,z-.375,x+wide-.125,h,z+.375,P.STONE_C)
            b:Box(x-wide,h,z-.5,x+wide,h+.25,z+.5,broken and P.STONE_MOSS or P.MARBLE_B)
        end
    end
    trimGround(b)
    -- The western edge of the launch paving crosses one surviving pond pillar.
    b:Shape(3,1.5,-6,21,1.75,12,function(x,_,z) if pad(x,z)<=8.55 then return false end end)
    b:Finish()
    trimColumns(world,b,columns)
end
local function trees(world,scene)
    local foliage=require('ruins.RuinsTrees')
    local hidden=require('ruins.RuinsTerrain').HiddenMaterial()
    for i,p in ipairs({{-19.5,8,5.6,2.3},{-13,15,7.2,3},{-22.5,1,4,2},{3,13.25,5,2.4},{9,15,3,1.6},{20,-5,3.9,2.1},{-18,-10,3.2,1.7},{-2,-13.25,2.8,1.6}}) do
        local x,z,h,r=table.unpack(p)
        local y=H.Height(H.x+x,H.z+z)-H.base
        local trunk=brush(world,{x-.375,y,z-.375},{x+.375,y+h*.65,z+.375},.25)
        trunk:Box(x-.25,y,z-.25,x+.25,y+h*.65,z+.25,P.BARK)
        local collider=trunk:Finish()
        if hidden then collider.material=hidden end
        foliage.Tree(scene,nil,H.x+x,H.base+y,H.z+z,{h=h,r=r,trunk=.24+h*.022,gold=i==2,lean=.35+i%3*.18,leanA=i*2.4})
    end
end
local function water(scene)
    local node=scene:CreateChild('HomeSpring')
    node.position=Vector3(H.x,H.base,H.z)
    local g=node:CreateComponent('CustomGeometry')
    -- Both the pool and the waterfall are excluded from their own render target.
    g.viewMask=WATER_VIEW
    g:BeginGeometry(0,TRIANGLE_LIST)
    local function quad(a,b,c,d,fall)
        for _,v in ipairs({a,b,c,a,c,d}) do
            g:DefineVertex(v); g:DefineNormal(fall and Vector3(0,0,-1) or Vector3.UP)
            g:DefineTexCoord(Vector2(v.x,fall and v.y or v.z)); g:DefineColor(Color(fall and 1 or 0,0,0,1))
        end
    end
    for i=-37,9 do for k=-42,4 do
        local x,z=i*.5,k*.5
        if waterBed(x+.25,z+.25) then
            local h=WATER_LEVEL
            quad(Vector3(x,h,z),Vector3(x,h,z+.5),Vector3(x+.5,h,z+.5),Vector3(x+.5,h,z),false)
            if channel(x+.25,z+.25) and edge(x+.25,z-.25)<=0 then
                local low=-9.5-2*cos(x*3)
                quad(Vector3(x,h,z),Vector3(x+.5,h,z),Vector3(x+.5,low,z-.7),Vector3(x,low,z-.7),true)
            end
        end
    end end
    g:Commit()
    local mat=Material:new()
    if mat:SetSurfaceShader('Shaders/BLGL/HomeSpring.shader') then
        H.spring=mat
    else
        mat:SetTechnique(0,cache:GetResource('Technique','Techniques/PBR/PBRNoTextureAlpha.xml'))
        mat:SetShaderParameter('MatDiffColor',Variant(Color(.19,.62,.60,.76)))
    end
    g:SetMaterial(mat);g.castShadows=false
end
local function shoreDetails(world)
    local rng=Noise.Rng(9423)
    for sector=0,7 do
        local rocks={}
        local xmin,xmax,zmin,zmax=math.huge,-math.huge,math.huge,-math.huge
        local ymin,ymax=math.huge,-math.huge
        -- Short runs of adjacent slabs are separated by stretches of bare cliff.
        for _=1,rng:Int(2,4) do
            local center=(sector+rng:Range(.12,.88))*math.pi/4
            for j=0,rng:Int(1,3) do
                local a=center+j*.036
                local radius=1+.045*cos(5*a)+.032*sin(9*a)
                local x,z=26*radius*cos(a),19*radius*sin(a)
                if not (z< -6 and abs(x+11.75)<3.4) then
                    local y=top(x*.98,z*.98)
                    local low=rockFloor(x,z,0)
                    local rx,rz=rng:Range(.60,1.55),rng:Range(.55,1.35)
                    rocks[#rocks+1]={x=x,z=z,y=y,low=low,rx=rx,rz=rz}
                    xmin,xmax=math.min(xmin,x-rx),math.max(xmax,x+rx)
                    zmin,zmax=math.min(zmin,z-rz),math.max(zmax,z+rz)
                    ymin,ymax=math.min(ymin,low-.65,y-2),math.max(ymax,y+.30)
                end
            end
        end
        if #rocks>0 then
            local b=brush(world,{xmin,ymin,zmin},{xmax,ymax,zmax},.25)
            for _,r in ipairs(rocks) do
                local x,z=r.x,r.z
                local y=rng:Range(r.low+.4,r.y-.75)
                b:Ellipsoid(x,y,z,r.rx,rng:Range(.45,1.05),r.rz,rng:Next()<.32 and P.CLIFF_D or P.CLIFF_B)
                if rng:Next()<.42 then
                    local length=rng:Int(2,7)
                    for j=0,length do
                        local drift=j*.055
                        local w=.15+.22*(1-j/(length+1))
                        b:Box(x-w+drift,r.y-(j+1)*.25,z-w,x+w+drift,r.y-j*.25,z+w,j==length and P.LEAF_C or P.LEAF_A)
                    end
                end
            end
            trimGround(b)
            b:Finish({visual=true})
        end
    end
    -- Submerged steps at the eastern bank lead onto the lane. Each rise fits the capsule step height.
    local stairs=brush(world,{-1,-1.5,-7},{4,.75,-3},.25)
    for i=0,5 do stairs:Box(-1+i*.65,-1.5,-6.25,-.25+i*.65,-1.25+i*.25,-4,P.STONE_MOSS) end
    trimGround(stairs)
    stairs:Finish()
end
local function meadowClearance(x,z,shore)
    return shore<.65 or pool(x,z)<1.55 or pad(x,z)<9.2 or abs(x+11.75)<2.1 and z< -6
        or x>-18 and x<3.5 and z>3 and z<13 or abs(x-4)<1.6 and abs(z)<11
        or x>8.5 and x<15.5 and z>-11 and z<2 or abs(z-4)<1.7 and x>-19 and x<9
        or (x-5)^2+(z+12)^2<1.7^2
end

local function meadowWeights(x,z,h)
    local shore=edge(x,z)
    if shore<=0 then return 0,0,0,0 end
    local skin=lawnMaterial(x,z,h)
    if skin==P.PATH or skin==P.PATH_B then return 1,0,0,0 end
    if skin==P.STONE_B or skin==P.STONE_MOSS then return 0,0,1,0 end
    if skin==P.SAND then return 0,1,0,0 end
    local dirt=Terrain.DirtPatch(x,z,lawnPath)
    if meadowClearance(x,z,shore) then return 0,dirt,0,0 end
    return 0,dirt,0,Terrain.MeadowDensity(x,z,dirt)
end

function H.GrassAt(wx,wz)
    local x,z=wx-H.x,wz-H.z
    local _,_,_,grass=meadowWeights(x,z,top(x,z))
    return grass
end

local function yieldBuild()
    if activeJob then coroutine.yield() end
end

local MEADOW_HALF, MEADOW_STEP = 32, .25
local function meadowMaps()
    local spacing=MEADOW_STEP
    local cells=math.floor(MEADOW_HALF*2/spacing)
    local height,coverage=Image:new(),Image:new()
    height:SetSize(cells+1,cells+1,3)
    coverage:SetSize(cells,cells,4)
    local previous={}
    for row=0,cells do
        if row%8==0 then yieldBuild() end
        -- Terrain vertices span [-32,32]. Each mask texel owns the quad between four vertices.
        local z=MEADOW_HALF-row*spacing
        local current={}
        for col=0,cells do
            local x=col*spacing-MEADOW_HALF
            local h=top(x,z)
            current[col]=h
            height:SetPixelInt(col,row,floor((h+2)*32))
            if row>0 and col>0 then
                local cx,cz=x-spacing*.5,z+spacing*.5
                local tread=top(cx,cz)
                local path,dirt,rock,w=meadowWeights(cx,cz,tread)
                -- A density texel fits exactly one cap voxel. Interpolation must stay on that tread.
                if h~=tread or h~=current[col-1] or h~=previous[col] or h~=previous[col-1] then w=0 end
                coverage:SetPixelInt(col-1,row-1,(path*255) | (floor(dirt*255+.5)<<8)
                    | ((rock*255)<<16) | (floor(w*255+.5)<<24))
            end
        end
        previous=current
    end
    yieldBuild()
    local mask=Texture2D:new();mask:SetNumLevels(1);mask:SetData(coverage,true)
    mask:SetFilterMode(FILTER_NEAREST)
    mask:SetAddressMode(COORD_U,ADDRESS_CLAMP);mask:SetAddressMode(COORD_V,ADDRESS_CLAMP)
    return height,mask
end

local function meadow(scene)
    yieldBuild()
    local node=scene:CreateChild('HomeGrassHeight')
    node.position=Vector3(H.x,H.base-2,H.z)
    local field={x=H.x,z=H.z,grassExtent=30,terrainNode=node,GrassAt=H.GrassAt,Height=H.Height,HasGround=H.Ground}
    local height,mask=meadowMaps()
    field.splat=mask
    H.meadowMaterial=Terrain.NewGroundMaterial(mask,MEADOW_HALF,Vector4(H.x,H.base,H.z,1))
    field.terrain=node:CreateComponent('Terrain')
    local t=field.terrain
    -- Only native GrassField needs the height patches; the collidable caps own the visible surface.
    t.visible=false;t.castShadows=false;t.viewMask=0;t.occluder=false
    Terrain.BuildGrass(scene,field,function()
        t.patchSize=32
        t.spacing=Vector3(MEADOW_STEP,1/32,MEADOW_STEP)
        t.smoothing=false;t.heightMap=height
    end,yieldBuild)
    if not field.grass then
        node:Remove()
        field.terrain,field.terrainNode=nil,nil
    end
    require('ruins.SceneQuality').ApplyGrass(field,require('ruins.GameSettings').GetProfile())
    H.field=field
end
function H.Build(world,scene,dayNight)
    for _,entry in ipairs({
        -- Deep walnut frame, warm mid-tone trim, and a muted blue-grey pane.
        {oak,.31,.18,.10,.72,0,.36}, {amber,.46,.25,.11,.68,0,.38},
        {cedar,.25,.13,.065,.77,0,.34}, {slate,.22,.24,.24,.64,.65,.45},
        {ember,.93,.32,.09,.83,0,.30}, {flame,1,.73,.30,.34,0,.34},
        {window,.36,.43,.45,.24,0,.52},
        {cedarPost,.28,.15,.08,.75,0,.34}, {oakPlankZ,.34,.20,.10,.70,0,.36},
        {cedarBeamZ,.25,.13,.065,.77,0,.34},
    }) do
        local id,r,g,b,roughness,metallic,specular=table.unpack(entry)
        world:SetPaletteEntry(id,Color(r,g,b),50)
        local glow=Color(0,0,0,0)
        if id==ember or id==flame then glow=Color(r,g,b,id==flame and 1.6 or 1) end
        if id==window then glow=Color(1,.65,.30,1) end
        world:SetPaletteEntryPBR(id,roughness,metallic,specular,glow)
    end
    meadow(scene); terrain(world); courtyard(world); house(world,scene); banks(world); trees(world,scene); shoreDetails(world); water(scene)
    local fire=scene:CreateChild('HomeForgeFire'); fire.position=Vector3(H.x+1.15,H.base+1.65,H.z+7.5)
    local light=fire:CreateComponent('Light'); light.lightType=LIGHT_POINT
    light.color=Color(1,.53,.21); light.range=5; light.brightness=.78
    H.hearth=light
    if dayNight then H.Update(0,nil,dayNight) end
    world:OptimizeBroadPhase()
end
-- Build one bounded brush per update. Record only our volumes for interruption/retry.
function H.BeginBuild(world,scene,dayNight)
    local job={ids={},root=scene:CreateChild('HomeIslandScenery')}
    houseParts,houseReady={},false
    local thread=coroutine.create(function() H.Build(world,job.root,dayNight) end)
    function job:Cancel()
        if self.cancelled then return end
        self.cancelled=true
        thread=nil
        for i=world:GetVolumeCount()-1,0,-1 do
            local v=world:GetVolume(i)
            if v and self.ids[v:GetVolumeId()] then
                local node=v:GetNode()
                world:RemoveVolume(v)
                v:Dispose()
                if node then node:Dispose() end
            end
        end
        H.Stop()
        self.root:Remove()
    end
    function job:Step()
        if self.cancelled then return false,'home island build cancelled' end
        if not thread then return true end
        activeJob=self
        local ok,err=coroutine.resume(thread)
        activeJob=nil
        if not ok then self:Cancel();return false,err end
        if coroutine.status(thread)=='dead' then thread=nil;return true end
        return false
    end
    return job
end
return H
