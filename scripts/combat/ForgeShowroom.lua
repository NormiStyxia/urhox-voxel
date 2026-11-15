-- Sky showroom in the EXISTING scene; never creates a Scene, RTT or voxel world.
-- Binding evidence: .emmylua/Drawable.d.lua exposes viewMask/lightMask/zoneMask;
-- Light and Zone inherit Drawable. Camera.d.lua exposes viewMask/projectionOffset.
-- rendering.md: high-priority Zone + AMBIENT_COLOR, local depth/volumetric fog.
-- lights-and-shadows.md: directional shadows + ordinary point lights on Web.
-- Reserved view/light bit 0x40000000: temporarily exclude existing lights,
-- Skyboxes and CustomGeometry (including camera-relative clouds), restore on Exit.
-- Main camera and its viewport are borrowed, never modified by this module.
-- Room (2304,1200,0): Terrain HALF=84; DragonFlight AIR_EDGE=60 and
-- DragonAnimationController altitude<=40. SkyClouds has +/-2048 CPU bounds
-- around player, despite visible radii 522..548: y=1200 ALONE does not avoid it!
-- x=2304 leaves >150m beyond that inflated bound at the island edge. Float32
-- ULP here is <0.25mm (weapon cells=30mm). The dressing dome radius is 90m (still outside main-cloud bounds).
-- Twelve dressing material batches plus one weapon; low uses seven plus one.
-- Native per-light/shadow/post-process passes are additional, not included here.
-- Dressing spans <100m (same x=2304 clearance); Zone includes the full sky dome.
-- Native Commit is indivisible; StepPreview's 2ms budget is cooperative, not a
-- guarantee that a GPU upload/Compile cannot exceed 2ms on a slow platform.
-- Round 3: Zone-only Bloom/ACES/vignette/fog; camera-only DOF. No renderer
-- pipeline/HDR/shadow-map/compute switches are mutated. docs post-processing
-- and volumetric-fog: Web forward has simplified directional fog, mobile
-- forward may have none. Three feathered additive shafts ALWAYS remain as
-- fallback. No compute-only local fog or unsupported area lights are required.
local Builder=require('combat.WeaponBuilder')
local Dressing=require('combat.ForgeShowroomScene')
local Blades=require('combat.ForgeShowroomBlades')
-- Temporary showroom-only comparison; nil restores the voxel sword default.
local MODEL_TEST='model/c8d2cfd2bc29455abb72b044deb16d5d/Meshes/c8d2cfd2bc29455abb72b044deb16d5d.mdl'
local MODEL_MATERIAL='model/c8d2cfd2bc29455abb72b044deb16d5d/Materials/c8d2cfd2bc29455abb72b044deb16d5d_00_tripo_material_af5190d1-e320-4160-9951-ed50bff7a75e.xml'
local MODEL_TEXTURE='model/c8d2cfd2bc29455abb72b044deb16d5d/Textures/c8d2cfd2bc29455abb72b044deb16d5d_00_'
local modelOverride=nil -- original voxel sword remains the startup default
local modelRoute='original'
local flowStrength=.7
local M={}
local MASK=0x40000000
local KEEP=0xffffffff~MASK
local AUTO_SPEED,HOME_YAW,DRAG_SCALE=12,25,.35
local OFF,BUILDING,READY,FAILED='off','building','ready','failed'
---@type table?
local session
local state=OFF
local diagnostic=''
local failureTimes,failureKeys={},{} -- bounded, survives Exit/reopen for 10s dedup
local fallbackSeconds=0

local function Finite(v,fallback)
    return type(v)=='number' and v==v and math.abs(v)<math.huge and v or fallback
end
local function Clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function OneLine(value) return tostring(value):gsub('[\r\n]+',' '):sub(1,500) end
-- Property lookup can itself throw on a platform-specific binding. Record the
-- stage/API BEFORE touching it; the surrounding operation owns the pcall.
local function Read(s,stage,object,key,label)
    s.stage,s.api,s.apiType=stage,label,'unread'
    local value=object and object[key]
    s.apiType=type(value)
    if value==nil then error('missing API '..label..' (nil)',0) end
    return value
end
local function Check(s,stage,object,key,label)
    local method=Read(s,stage,object,key,label)
    if type(method)~='function' then error('missing callable API '..label..' ('..type(method)..')',0) end
    return method
end
local function Call(s,stage,object,key,label,...)
    return Check(s,stage,object,key,label)(object,...)
end
local function FailureClock()
    local ok,value=pcall(function() return time:GetElapsedTime() end)
    if ok and Finite(value,nil) then return value end
    ok,value=pcall(function() return os.time() end)
    return ok and Finite(value,nil) or fallbackSeconds
end
local function ReportFailure(s,origin,reason)
    local stage=s and s.stage or 'unknown'
    local errorText=OneLine(reason)
    diagnostic='stage='..stage..' error='..errorText..' origin='..origin
        ..' api='..tostring(s and s.api)..' api_type='..tostring(s and s.apiType)
        ..' mask='..MASK..' last_mask='..tostring(s and s.lastMask)
        ..' masks_saved='..tostring(s and #s.masks or 0)
        ..' viewport_acquired='..tostring(s~=nil and s.previousViewport~=nil)
        ..' switched='..tostring(s~=nil and s.switched==true)
        ..' root='..tostring(s~=nil and s.root~=nil)..' camera='..tostring(s~=nil and s.camera~=nil)
        ..' state='..state..' geometry_stage='..tostring(s and s.job and s.job.stage)
    local operation=origin=='Enter' and 'enter' or 'update'
    local key=operation..'|'..stage..'|'..tostring(s and s.api)..'|'..errorText
    local now=FailureClock();local previous=failureTimes[key]
    if previous and now>=previous and now-previous<10 then return end
    if not previous then
        if #failureKeys>=32 then failureTimes[table.remove(failureKeys,1)]=nil end
        failureKeys[#failureKeys+1]=key
    end
    failureTimes[key]=now
    print('ForgeShowroom: '..operation..' failed '..diagnostic)
end
local function CleanupError(s,label,err)
    local text=label..': '..OneLine(err)
    if diagnostic=='' then
        s.stage,s.api,s.apiType='cleanup',label,'unavailable'
        ReportFailure(s,'Exit',text)
    elseif not diagnostic:find(' cleanup=',1,true) then
        diagnostic=diagnostic..' cleanup='..text -- preserve primary failure; never double-print
    end
end
local function CleanupFunction(s,label,fn,...)
    if type(fn)~='function' then CleanupError(s,label,'missing API (nil/non-callable)');return end
    local ok,err=pcall(fn,...)
    if not ok then CleanupError(s,label,err) end
end
local function CleanupMethod(s,object,key,label,...)
    local ok,method=pcall(function() return object and object[key] end)
    if not ok then CleanupError(s,label,method);return end
    CleanupFunction(s,label,method,object,...)
end
local function Remove(s,node) if node then CleanupMethod(s,node,'Remove','Node:Remove') end end
local function DisposeMesh(s,mesh)
    if not mesh then return end
    if mesh.bladeRoute then CleanupFunction(s,'ForgeShowroomBlades.Dispose',Blades.Dispose,mesh)
    elseif mesh.modelOverride then CleanupMethod(s,mesh.material,'Dispose','Material:Dispose')
    else CleanupFunction(s,'WeaponBuilder.DisposePreview',Builder.DisposePreview,mesh) end
end
local function Cancel(s)
    if s.job then CleanupFunction(s,'WeaponBuilder.CancelPreview',Builder.CancelPreview,s.job);s.job=nil end
    if s.pendingModel then DisposeMesh(s,s.pendingModel);s.pendingModel=nil end
    if s.bladeJob then DisposeMesh(s,s.bladeJob);s.bladeJob=nil end
    Remove(s,s.pendingRoot);s.pendingRoot=nil;s.pending=nil
end
local function Cleanup(s)
    if not s then return end
    Cancel(s)
    if s.mesh then DisposeMesh(s,s.mesh);s.mesh=nil end
    if s.weaponMaterial then CleanupMethod(s,s.weaponMaterial,'Dispose','Material:Dispose');s.weaponMaterial=nil end
    -- Attempt every cleanup even if one native handle was already invalidated.
    if s.switched then
        CleanupMethod(s,renderer,'SetViewport','renderer:SetViewport',0,s.previousViewport)
    end
    for i=#s.masks,1,-1 do
        local saved=s.masks[i]
        pcall(function() saved.object[saved.field]=saved.value end)
    end
    if s.dressing then CleanupFunction(s,'Dressing.Dispose',Dressing.Dispose,s.dressing);s.dressing=nil end
    Remove(s,s.root)
end
local function Failed(reason,origin)
    ReportFailure(session,origin or 'Update',reason) -- snapshot BEFORE cleanup
    local old=session;session=nil;state=FAILED
    Cleanup(old)
end
local function Protect(origin,fn,...)
    if not session then return end
    session.stage,session.api,session.apiType='start',origin,'function'
    local ok,err=pcall(fn,session,...)
    if not ok then Failed(err,origin) end
end

---@param drawable Drawable
local function Isolate(s,stage,drawable)
    for _,field in ipairs({'viewMask','lightMask','zoneMask'}) do
        s.lastMask=Read(s,stage,drawable,field,'Drawable.'..field)
        drawable[field]=MASK
    end
    drawable.castShadows=false
end
local function SaveMask(s,object,field)
    local value=assert(tonumber(Read(s,'mask',object,field,'Drawable.'..field)),field..' binding is not numeric')
    s.lastMask=value
    s.masks[#s.masks+1]={object=object,field=field,value=value}
    object[field]=value&KEEP
end
local function IsolateWorld(s,scene)
    -- Enumerate exact types (GetComponents does not promise derived-type lookup).
    local lights=Call(s,'light',scene,'GetComponents','Node:GetComponents','Light',true)
    assert(type(lights)=='table','Node:GetComponents(Light,true) returned '..type(lights))
    for _,light in ipairs(lights) do
        SaveMask(s,light,'viewMask');SaveMask(s,light,'lightMask')
    end
    for _,kind in ipairs({'Skybox','CustomGeometry'}) do
        local drawables=Call(s,'mask',scene,'GetComponents','Node:GetComponents',kind,true)
        assert(type(drawables)=='table','Node:GetComponents('..kind..',true) returned '..type(drawables))
        for _,drawable in ipairs(drawables) do SaveMask(s,drawable,'viewMask') end
    end
end

local function Focus(s,x,y)
    s.focusX=Clamp(Finite(x,s.focusX),.1,.9)
    s.focusY=Clamp(Finite(y,s.focusY),.15,.85)
    -- Camera projection offsets are screen fractions (doubled into NDC). Positive Y
    -- is up, whereas panel fractions have top-left origin. No RTT flip involved.
    Read(s,'camera',s.camera,'projectionOffset','Camera.projectionOffset')
    s.camera.projectionOffset=Vector2(s.focusX-.5,.5-s.focusY)
    s.fitDirty=true
end
-- DOF is camera-local (post-processing.md §5; Web supported). It never attaches
-- to scene root, so the borrowed main camera cannot inherit this effect.
local function Haze(s,distance)
    s.zone.depthFogEnable=true;s.zone.depthFogStart=distance+4
    s.zone.depthFogEnd=distance+42;s.zone.depthFogDensity=.42
end
-- Optional enhancement failure never destroys the ready weapon/viewport.
local function Enhancement(s,stage,fn)
    s.stage,s.api,s.apiType=stage,stage,'function'
    local ok,err=pcall(fn)
    if not ok then ReportFailure(s,'Update',err) end
    return ok
end
local function ZoneSet(s,stage,method,value)
    Call(s,stage,s.zone,method,'Zone:'..method,value)
end
local function PostEffects(s)
    -- Bloom's compositor also owns tone mapping. Low disables its blur weight,
    -- not the compositor (otherwise HDR highlights clip rather than tone map).
    Enhancement(s,'tonemap',function() ZoneSet(s,'tonemap','SetTonemapMode',TONEMAP_MODE_ACES) end)
    local bloom=Enhancement(s,'bloom',function()
        Call(s,'bloom',s.zone,'SetAttribute','Zone:SetAttribute','Bloom Enable',Variant(true))
        ZoneSet(s,'bloom','SetBloomMode',BLOOM_MODE_LEGACY)
        ZoneSet(s,'bloom','SetBloomThreshold',1.15)
        ZoneSet(s,'bloom','SetBloomWeight',s.low and 0 or .18)
    end)
    if not bloom then pcall(function() s.zone.bloomWeight=0 end) end
    if s.low then
        Enhancement(s,'vignette',function() ZoneSet(s,'vignette','SetVignetteEnabled',false) end)
        return
    end
    Enhancement(s,'vignette',function()
        -- Exact built-in resource used by examples/27-voxel-town TownDay.xml.
        local texture=Call(s,'vignette',cache,'GetResource','cache:GetResource','Texture2D','Editor/Textures/Engine/Vignetting.png')
        assert(texture,'built-in vignette texture unavailable')
        ZoneSet(s,'vignette','SetVignetteTexture',texture)
        ZoneSet(s,'vignette','SetVignetteIntensity',.32)
        ZoneSet(s,'vignette','SetVignetteEnabled',true)
    end)
end
local function NewLight(s,name,position,color,brightness,range,directional)
    local light,node
    local ok=Enhancement(s,'light.'..name,function()
        node=Call(s,'light.'..name,s.root,'CreateChild','Node:CreateChild',name)
        node.position=position
        light=Call(s,'light.'..name,node,'CreateComponent','Node:CreateComponent','Light')
        assert(light,'Light component unavailable')
        Isolate(s,'light.'..name,light)
        light.lightType=directional and LIGHT_DIRECTIONAL or LIGHT_POINT
        light.range=range;light.brightness=brightness;light.color=color
        light.affectVolumetricFog=false
    end)
    if not ok then Remove(s,node);return nil end
    s.lights[#s.lights+1]=light
    return light
end
local function Lighting(s)
    s.lights={}
    s.sun=NewLight(s,'WarmKey',Vector3(-6,7,-5),Color(1,.9,.72,1),s.low and 1.2 or 1.65,18,true)
    if s.sun then
        s.sun.node.direction=Vector3(.68,-.62,.52) -- light travels from upper-left/front toward right/back
        if not s.low then
            local ok=Enhancement(s,'shadow',function()
                s.sun.shadowCascade=CascadeParameters(10,32,0,0,.8)
                s.sun.shadowBias=BiasParameters(.00025,.5)
                s.sun.shadowResolution=.75;s.sun.shadowIntensity=.20
                s.sun.castShadows=true
            end)
            if not ok then s.sun.castShadows=false end
        end
    end
    NewLight(s,'CoolRim',Vector3(2.6,3.1,2.4),Color(.36,.58,1,1),s.low and .7 or 1.35,7,false)
    if s.low then return end
    s.crystalLeft=NewLight(s,'CrystalLeft',Vector3(-1.9,1.0,-1.5),Color(.22,.48,1,1),1.35,3.3,false)
    s.crystalRight=NewLight(s,'CrystalRight',Vector3(1.9,1.0,-1.5),Color(.22,.48,1,1),1.35,3.3,false)
    NewLight(s,'CompassGold',Vector3(0,.88,.05),Color(1,.72,.30,1),.45,2.1,false)
    s.weaponKey=NewLight(s,'WeaponSoftKey',Vector3(-1.25,2.5,-1.4),Color(1,.94,.83,1),.72,4,false)
    if s.sun and s.sun.castShadows then
        local ok=Enhancement(s,'volumetric',function()
            ZoneSet(s,'volumetric','SetVolumetricFogDensity',.003)
            ZoneSet(s,'volumetric','SetVolumetricFogHeight',0) -- Zone-local, not world y=1200
            ZoneSet(s,'volumetric','SetVolumetricFogHeightFalloff',.025)
            ZoneSet(s,'volumetric','SetVolumetricFogViewDistance',45)
            ZoneSet(s,'volumetric','SetVolumetricFogStartDistance',1.5)
            ZoneSet(s,'volumetric','SetVolumetricFogPhaseG',.5)
            ZoneSet(s,'volumetric','SetVolumetricFogMaxOpacity',.18)
            ZoneSet(s,'volumetric','SetVolumetricFogScatteringColor',Color(1,.94,.84,1))
            s.sun.affectVolumetricFog=true;s.sun.volumetricFogShadows=true;s.sun.volumetricFogIntensity=1.4
            ZoneSet(s,'volumetric','SetVolumetricFogEnabled',true)
        end)
        if not ok then pcall(function() s.zone.volumetricFogEnabled=false end) end
    end
end
local function AnimateLights(s,dt)
    s.lightAge=(s.lightAge or 0)+dt
    local breath=.92+.08*math.sin(s.lightAge*math.pi/2)
    if s.crystalLeft then s.crystalLeft.brightness=1.35*breath end
    if s.crystalRight then s.crystalRight.brightness=1.35*breath end
    if s.weaponKey then
        local a=math.rad(s.yaw)
        s.weaponKey.node.position=Vector3(-1.25*math.cos(a)-1.4*math.sin(a),2.5,1.25*math.sin(a)-1.4*math.cos(a))
    end
end
local function Dof(s)
    local ok,err=pcall(function()
        s.dof=Call(s,'dof',s.cameraNode,'CreateComponent','Node:CreateComponent','DepthOfField')
        assert(s.dof,'DepthOfField unavailable')
        Call(s,'dof',s.dof,'SetQuality','DepthOfField:SetQuality',DOF_QUALITY_MEDIUM)
        Call(s,'dof',s.dof,'SetMaxBlur','DepthOfField:SetMaxBlur',7)
        Call(s,'dof',s.dof,'SetFarBlurScale','DepthOfField:SetFarBlurScale',.9)
        Call(s,'dof',s.dof,'SetNearBlurScale','DepthOfField:SetNearBlurScale',.08)
    end)
    if not ok then
        if s.dof then pcall(function() s.dof.enabled=false end) end
        s.dof=nil;s.haze=true;Haze(s,6)
        ReportFailure(s,'Update',err)
    end
end
local function Fit(s,bp)
    local lo,hi=bp.bounds.min,bp.bounds.max
    local rawHeight=hi[2]-lo[2]
    assert(rawHeight>0,'weapon height must be positive')
    local height=bp.displayHeight or 2.05
    local scale=height/rawHeight -- display-only; Compile bounds/fingerprint stay untouched
    local halfY=height*.5
    local hx,hz=(hi[1]-lo[1])*.5*scale,(hi[3]-lo[3])*.5*scale
    local w=Call(s,'camera',graphics,'GetWidth','graphics:GetWidth')
    local h=Call(s,'camera',graphics,'GetHeight','graphics:GetHeight')
    assert(w>0 and h>0,'invalid drawable size')
    s.width,s.height=w,h
    local tan=math.tan(math.rad(s.camera.fov)*.5)
    local cp,sp=math.cos(math.rad(8)),math.sin(math.rad(8))
    local vertical=math.min(.59,2*math.min(s.focusY,1-s.focusY)*.94)
    local horizontal=2*math.min(s.focusX,math.max(.04,.55-s.focusX))*.94
    local distance=0
    for angle=0,345,15 do
        local ca,sa=math.cos(math.rad(angle)),math.sin(math.rad(angle))
        for _,x in ipairs({-hx,hx}) do for _,y in ipairs({-halfY,halfY}) do for _,z in ipairs({-hz,hz}) do
            local px,pz=ca*x+sa*z,-sa*x+ca*z
            local py,depth=cp*y+sp*pz,-sp*y+cp*pz
            distance=math.max(distance,math.abs(py)/(tan*vertical)-depth,
                math.abs(px)/(tan*(w/h)*horizontal)-depth)
        end end end
    end
    local pivotY=.65+halfY+.12
    s.spin.scale=Vector3(scale,scale,scale)
    s.spin.position=Vector3(0,pivotY,0)
    s.cameraNode.position=Vector3(0,pivotY+distance*sp,-distance*cp)
    s.cameraNode.rotation=Quaternion(8,0,0)
    if s.dof then
        local ok,err=pcall(function()
            Call(s,'dof',s.dof,'SetFocalDistance','DepthOfField:SetFocalDistance',distance)
            Call(s,'dof',s.dof,'SetFocalRange','DepthOfField:SetFocalRange',2*math.sqrt(hx*hx+hz*hz)+.8)
        end)
        if not ok then
            pcall(function() s.dof.enabled=false end);s.dof=nil;s.haze=true
            ReportFailure(s,'Update',err)
        end
    end
    if s.haze then Haze(s,distance) end
    s.fitDirty=false
end
local function EnterImpl(s,scene,opts)
    for _,name in ipairs({'Vector3','Vector2','Quaternion','BoundingBox','Color','Variant','CULL_NONE','TRIANGLE_LIST','LIGHT_POINT','AMBIENT_COLOR'}) do
        Read(s,'globals',_G,name,name)
    end
    assert(Call(s,'scene',scene,'GetComponent','Node:GetComponent','Octree'),'main scene Octree required')
    s.previousViewport=Call(s,'viewport',renderer,'GetViewport','renderer:GetViewport',0)
    Check(s,'viewport',renderer,'SetViewport','renderer:SetViewport') -- ensure rollback API before mutation
    IsolateWorld(s,scene)
    s.root=assert(Call(s,'root',scene,'CreateChild','Node:CreateChild','ForgeShowroom'),'showroom root missing')
    s.root.temporary=true;s.root.position=Vector3(2304,1200,0)
    local zone=Call(s,'zone',s.root,'CreateComponent','Node:CreateComponent','Zone');assert(zone,'showroom Zone missing');s.zone=zone
    Isolate(s,'zone',zone);zone.boundingBox=BoundingBox(Vector3(-110,-110,-110),Vector3(110,110,110))
    Read(s,'zone',zone,'ambientSource','Zone.ambientSource')
    zone.priority=100;zone.ambientSource=AMBIENT_COLOR;zone.ambientColor=Color(.5*.5,.58*.5,.78*.5,1)
    zone.depthFogEnable=false;zone.heightFogEnable=false;zone.volumetricFogEnabled=false
    zone.autoExposureEnabled=false;zone.fogColor=Color(.72,.79,.88,1)
    Lighting(s);PostEffects(s);s.haze=true
    s.dressing=Dressing.Begin(s.root,MASK,opts)
    s.spin=Call(s,'geometry',s.root,'CreateChild','Node:CreateChild','WeaponTurntable');s.rotation=Quaternion(0,HOME_YAW,0);s.spin.rotation=s.rotation
    s.cameraNode=Call(s,'camera',s.root,'CreateChild','Node:CreateChild','ForgeCamera');s.cameraNode.position=Vector3(0,1,-3)
    s.camera=assert(Call(s,'camera',s.cameraNode,'CreateComponent','Node:CreateComponent','Camera'),'showroom Camera missing')
    Read(s,'camera',s.camera,'viewMask','Camera.viewMask')
    s.camera.fov=34;s.camera.nearClip=.05;s.camera.farClip=180;s.camera.viewMask=MASK
    Focus(s,opts and opts.focusX,opts and opts.focusY)
    if not s.low then Dof(s) end
    Fit(s,{bounds={min={-.3,-.6,-.3},max={.3,.6,.3}}})
    s.viewport=Call(s,'viewport',Viewport,'new','Viewport:new',scene,s.camera)
    assert(s.viewport,'showroom Viewport missing')
    s.switched=true -- even a partially successful binding must be rolled back
    Call(s,'viewport',renderer,'SetViewport','renderer:SetViewport',0,s.viewport)
end

---@param scene Scene
---@param opts table?
---@return boolean
function M.Enter(scene,opts)
    M.Exit()
    local s={masks={},focusX=.30,focusY=.5,yaw=HOME_YAW,velocity=0,idle=1.5,dragging=false,home=false,low=opts and opts.quality=='low' or false}
    session=s;state=BUILDING;diagnostic=''
    local ok,err=pcall(EnterImpl,s,scene,opts)
    if not ok then Failed(err,'Enter');return false end
    return true
end
function M.Exit()
    local old=session;session=nil;state=OFF
    Cleanup(old)
end
local function Weapon(s,single)
    s.stage,s.api,s.apiType='weapon','SetWeapon.config',type(single)
    assert(type(single)=='table' and (single.weapon=='sword' or single.weapon=='bow'),'invalid weapon config')
    -- Snapshot caller's draft, since BeginPreview is deferred until Update.
    local copy={weapon=single.weapon,parts={},colors={}}
    for k,v in pairs(single.parts or {}) do copy.parts[k]=v end
    for k,v in pairs(single.colors or {}) do copy.colors[k]=v end
    Cancel(s);s.selection=copy;s.pending=copy;s.buildAge=0;state=BUILDING
end
---@param single table
function M.SetWeapon(single) Protect('SetWeapon',Weapon,single) end

---@param resPath string? nil disables the model experiment, including subsequent Enter calls
function M.SetModelOverride(resPath)
    assert(resPath==nil or type(resPath)=='string','model override must be a resource path or nil')
    modelOverride=resPath
    modelRoute=resPath and 'imported' or 'original'
    if session and session.selection then M.SetWeapon(session.selection) end
end

--- Showroom study only; does not write the inventory, rig or selected blade ID.
---@param route string original | A | B | imported
function M.SetModelRoute(route)
    assert(route=='original' or route=='A' or route=='B' or route=='imported','invalid blade route')
    modelRoute=route;modelOverride=route=='imported' and MODEL_TEST or nil
    if session and session.selection then M.SetWeapon(session.selection) end
    print('ForgeShowroom: blade route='..route)
end
function M.GetModelRoute() return modelRoute end
function M.CycleModelRoute()
    M.SetModelRoute(modelRoute=='original' and 'A' or (modelRoute=='A' and 'B' or 'original'))
end
---@param strength number 0 disables, 0.7 default, 2 maximum
function M.SetFlowStrength(strength)
    flowStrength=Clamp(Finite(strength,flowStrength),0,2)
    Protect('SetFlowStrength',function(s)
        if s.mesh and s.mesh.bladeRoute then Blades.SetFlowStrength(s.mesh,flowStrength) end
        if s.bladeJob then Blades.SetFlowStrength(s.bladeJob,flowStrength) end
    end)
end
function M.GetFlowStrength() return flowStrength end

local function PublishWeapon(s,mesh)
    local b=mesh.blueprint.bounds
    s.pendingRoot.position=Vector3(-(b.min[1]+b.max[1])*.5,-(b.min[2]+b.max[2])*.5,-(b.min[3]+b.max[3])*.5)
    Fit(s,mesh.blueprint)
    DisposeMesh(s,s.mesh);Remove(s,s.meshRoot)
    s.mesh,s.meshRoot=mesh,s.pendingRoot;s.pendingRoot=nil;s.job=nil;s.pendingModel=nil;s.bladeJob=nil
    s.meshRoot.enabled=true;state=READY
    print('Forge showroom: ready')
end

-- StaticModel/Model/Material signatures are from their .emmylua definitions.
-- Imported XML uses UUID textures; explicitly rebind the delivered paths on a
-- PRIVATE material so Web bundles without UUID resolution still show the skin.
local function TryModel(s,path)
    local node,mat
    local ok,result=pcall(function()
        local model=cache:GetResource('Model',path);assert(model,'Model resource unavailable: '..path)
        local b=model.boundingBox;assert(b,'Model.boundingBox unavailable')
        local lo,hi=b.min,b.max
        assert(Finite(hi.y-lo.y,0)>0,'Model has empty/invalid bounds')
        node=s.pendingRoot:CreateChild('ModelTest')
        local drawable=node:CreateComponent('StaticModel');assert(drawable,'StaticModel unavailable')
        drawable:SetModel(model);Isolate(s,'model_test',drawable);drawable.castShadows=not s.low
        local source=cache:GetResource('Material',MODEL_MATERIAL)
        if source then mat=source:Clone('ForgeModelTest') else
            mat=Material:new()
            local tech=cache:GetResource('Technique','Techniques/PBR/PBRDiffNormal.xml')
            assert(tech,'textured PBR technique unavailable');mat:SetTechnique(0,tech)
            mat:SetShaderParameter('Metallic',Variant(1));mat:SetShaderParameter('Roughness',Variant(1))
        end
        assert(mat,'model material clone unavailable')
        local diffuse=cache:GetResource('Texture2D',MODEL_TEXTURE..'D.jpg')
        local normal=cache:GetResource('Texture2D',MODEL_TEXTURE..'N.png')
        assert(diffuse and normal,'model diffuse/normal texture unavailable')
        mat:SetTexture(TU_DIFFUSE,diffuse);mat:SetTexture(TU_NORMAL,normal)
        local count=model:GetNumGeometries();assert(count>0,'Model has no geometry')
        local verts,tris=0,0
        for i=0,count-1 do
            assert(drawable:SetMaterial(i,mat)~=false,'StaticModel:SetMaterial failed')
            local geometry=model:GetGeometry(i,0)
            if geometry then verts=verts+geometry.vertexCount;tris=tris+geometry.indexCount/3 end
        end
        local mesh={modelOverride=true,material=mat,blueprint={displayHeight=1.7,
            bounds={min={lo.x,lo.y,lo.z},max={hi.x,hi.y,hi.z}}}}
        print(('ForgeShowroom: model test loaded verts=%d tris=%d bbox=(%.4f,%.4f,%.4f)-(%.4f,%.4f,%.4f)'):format(
            verts,tris,lo.x,lo.y,lo.z,hi.x,hi.y,hi.z))
        return mesh
    end)
    if ok then s.pendingModel=result;return result end
    Remove(s,node)
    if mat then CleanupMethod(s,mat,'Dispose','Material:Dispose') end
    print('ForgeShowroom: model test load failed: '..OneLine(result))
    s.stage,s.api,s.apiType='model_test',path,'resource';ReportFailure(s,'Update',result)
    return nil
end

local function BuildStep(s,dt)
    if s.pending then
        local single=s.pending;s.pending=nil
        s.pendingRoot=Call(s,'geometry',s.spin,'CreateChild','Node:CreateChild','PendingWeapon');s.pendingRoot.enabled=false
        if single.weapon=='sword' and (modelRoute=='A' or modelRoute=='B') then
            s.stage,s.api,s.apiType='blade_route','ForgeShowroomBlades.Begin','function'
            local job,err=Blades.Begin(s.pendingRoot,modelRoute,single.colors,MASK,s.low,flowStrength)
            if job then s.bladeJob=job;return end
            ReportFailure(s,'Update',err) -- unavailable shader/resources: retain voxel fallback
        end
        if single.weapon=='sword' and modelOverride then
            local mesh=TryModel(s,modelOverride)
            if mesh then PublishWeapon(s,mesh);return end
        end
        s.job=Check(s,'geometry',Builder,'BeginPreview','WeaponBuilder.BeginPreview')(s.pendingRoot,single)
        return -- Compile and native emission never share one frame
    end
    if s.bladeJob then
        s.stage,s.api,s.apiType='blade_route','ForgeShowroomBlades.Step','function'
        local ok,done=pcall(Blades.Step,s.bladeJob)
        if ok then
            if done then PublishWeapon(s,s.bladeJob) end
        else
            ReportFailure(s,'Update',done)
            DisposeMesh(s,s.bladeJob);Remove(s,s.bladeJob.node);s.bladeJob=nil
            s.job=Builder.BeginPreview(s.pendingRoot,s.selection)
        end
        return
    end
    local job=s.job
    if not job then return end
    s.stage,s.api,s.apiType='geometry','WeaponBuilder.StepPreview',type(Builder.StepPreview)
    s.buildAge=s.buildAge+dt;assert(s.buildAge<=5,'mesh build timeout')
    local done,mesh,err=Check(s,'geometry',Builder,'StepPreview','WeaponBuilder.StepPreview')(job,1)
    if job.geometry and not err then Isolate(s,'geometry',job.geometry);job.geometry.castShadows=not s.low end -- hidden ancestor until atomic publish
    if not done then return end
    assert(mesh,err or 'mesh missing')
    Enhancement(s,'weapon_material',function()
        if not s.weaponMaterialReady then
            local mat=s.weaponMaterial or Material:new();s.weaponMaterial=mat
            local tech=cache:GetResource('Technique','Techniques/PBR/PBRNoTexture.xml')
            assert(tech,'weapon PBR technique unavailable');mat:SetTechnique(0,tech)
            mat.vertexShaderDefines='VERTEXCOLOR';mat.pixelShaderDefines='VERTEXCOLOR'
            mat:SetShaderParameter('MatDiffColor',Variant(Color(1,1,1,1)))
            mat:SetShaderParameter('Metallic',Variant(.35));mat:SetShaderParameter('Roughness',Variant(.68))
            s.weaponMaterialReady=true -- partial failure retries setup, never reuses incomplete state
        end
        assert(mesh.geometry:SetMaterial(0,s.weaponMaterial)~=false,'weapon PBR SetMaterial failed')
    end)
    PublishWeapon(s,mesh)
end
local function UpdateImpl(s,dt)
    dt=Clamp(Finite(dt,0),0,1)
    -- Desktop debug entry. Mobile/UI buttons may call the same public methods.
    if s.selection and s.selection.weapon=='sword' and input and input.GetKeyPress then
        if KEY_F6 and input:GetKeyPress(KEY_F6) then M.CycleModelRoute() end
        if KEY_F7 and input:GetKeyPress(KEY_F7) then M.SetFlowStrength(flowStrength>0 and 0 or .7) end
    end
    local compiling=s.pending~=nil
    BuildStep(s,dt)
    if s.dressing and not compiling then
        -- Dressing failures cannot change weapon readiness or restore viewport.
        local ok,err=pcall(function()
            local reason=Dressing.Step(s.dressing,1)
            if reason then return reason end
            return Dressing.Animate(s.dressing,dt)
        end)
        if not ok or err then
            s.stage,s.api,s.apiType='dressing.'..s.dressing.stage,'ForgeShowroomScene','function'
            ReportFailure(s,'Update',err)
        end
    end
    if s.mesh and (s.fitDirty or Call(s,'camera',graphics,'GetWidth','graphics:GetWidth')~=s.width
        or Call(s,'camera',graphics,'GetHeight','graphics:GetHeight')~=s.height) then Fit(s,s.mesh.blueprint) end
    if s.home then
        local delta=(HOME_YAW-s.yaw+180)%360-180
        s.yaw=s.yaw+delta*(1-math.exp(-dt*10))
        if math.abs(delta)<.1 then s.yaw=HOME_YAW;s.home=false;s.idle=1.5 end
    elseif not s.dragging then
        local coast=math.min(dt,math.max(0,1.5-s.idle))
        s.yaw=s.yaw+s.velocity*(1-math.exp(-coast*4))/4
        s.velocity=s.velocity*math.exp(-dt*4);s.idle=s.idle+dt
        s.yaw=s.yaw+AUTO_SPEED*(dt-coast)
    end
    s.yaw=s.yaw%360;Call(s,'rotation',s.rotation,'FromEulerAngles','Quaternion:FromEulerAngles',0,s.yaw,0);s.spin.rotation=s.rotation
    if not s.lightsFailed then
        local ok,err=pcall(AnimateLights,s,dt)
        if not ok then s.lightsFailed=true;s.stage='light_animation';ReportFailure(s,'Update',err) end
    end
end
---@param dt number
function M.Update(dt)
    fallbackSeconds=fallbackSeconds+Clamp(Finite(dt,0),0,1)
    Protect('Update',UpdateImpl,dt)
end
function M.DragBegin() if session then session.dragging=true;session.home=false;session.velocity=0 end end
---@param dxPixels number
function M.DragBy(dxPixels)
    if session and session.dragging then session.yaw=(session.yaw+Finite(dxPixels,0)*DRAG_SCALE)%360 end
end
---@param velocityPixelsPerSec number
function M.DragEnd(velocityPixelsPerSec)
    if session then session.dragging=false;session.idle=0;session.velocity=Clamp(Finite(velocityPixelsPerSec,0)*DRAG_SCALE,-360,360) end
end
function M.Home() if session then session.dragging=false;session.home=true;session.velocity=0 end end
---@param fractionX number
---@param fractionY number?
function M.SetFocus(fractionX,fractionY) Protect('SetFocus',Focus,fractionX,fractionY) end
---@return boolean
function M.IsReady() return session~=nil and state==READY end
---@return string
function M.State() return state end
---@return boolean
function M.Active() return session~=nil end
--- Retained across Exit so the UI can inspect the failure after rollback.
--- A successful Enter clears it; rate-limit history is deliberately not cleared.
---@return string
function M.Diagnostic() return diagnostic end
return M
