-- Sky showroom in the EXISTING scene; never creates a Scene, RTT or voxel world.
-- Binding evidence: .emmylua/Drawable.d.lua exposes viewMask/lightMask/zoneMask;
-- Light and Zone inherit Drawable. Camera.d.lua exposes viewMask/projectionOffset.
-- rendering.md: small high-priority Zone + AMBIENT_COLOR, depth/height fog off.
-- lights-and-shadows.md: ordinary unshadowed point lights work across Web/mobile.
-- Reserved view/light bit 0x40000000: temporarily exclude existing lights,
-- Skyboxes and CustomGeometry (including camera-relative clouds), restore on Exit.
-- Main camera and its viewport are borrowed, never modified by this module.
-- Room (2304,1200,0): Terrain HALF=84; DragonFlight AIR_EDGE=60 and
-- DragonAnimationController altitude<=40. SkyClouds has +/-2048 CPU bounds
-- around player, despite visible radii 522..548: y=1200 ALONE does not avoid it!
-- x=2304 leaves >150m beyond that inflated bound at the island edge. Float32
-- ULP here is <0.25mm (weapon cells=30mm). The dressing dome radius is 90m (still outside main-cloud bounds).
-- Draw budget: eight dressing batches plus one weapon; low quality uses seven.
-- Dressing spans <100m (same x=2304 clearance); Zone includes the full sky dome.
-- Native Commit is indivisible; StepPreview's 2ms budget is cooperative, not a
-- guarantee that a GPU upload/Compile cannot exceed 2ms on a slow platform.
local Builder=require('combat.WeaponBuilder')
local Dressing=require('combat.ForgeShowroomScene')
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
local function Cancel(s)
    if s.job then CleanupFunction(s,'WeaponBuilder.CancelPreview',Builder.CancelPreview,s.job);s.job=nil end
    Remove(s,s.pendingRoot);s.pendingRoot=nil;s.pending=nil
end
local function Cleanup(s)
    if not s then return end
    Cancel(s)
    if s.mesh then CleanupFunction(s,'WeaponBuilder.DisposePreview',Builder.DisposePreview,s.mesh);s.mesh=nil end
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
    s.zone.depthFogEnable=true;s.zone.depthFogStart=distance+2
    s.zone.depthFogEnd=distance+32;s.zone.depthFogDensity=.35
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
    local scale=2.05/rawHeight -- display-only; Compile bounds/fingerprint stay untouched
    local halfY=1.025
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
    zone.priority=100;zone.ambientSource=AMBIENT_COLOR;zone.ambientColor=Color(.55*.55,.62*.55,.78*.55,1)
    zone.depthFogEnable=false;zone.heightFogEnable=false;zone.volumetricFogEnabled=false
    zone.autoExposureEnabled=false;zone.fogColor=Color(.93,.90,.82,1)
    for i=1,2 do
        local n=Call(s,'light',s.root,'CreateChild','Node:CreateChild',i==1 and 'WarmKey' or 'CoolRim')
        n.position=i==1 and Vector3(-2,3,-2) or Vector3(2,2,2)
        local light=assert(Call(s,'light',n,'CreateComponent','Node:CreateComponent','Light'),'showroom light missing')
        Isolate(s,'light',light);light.lightType=LIGHT_POINT;light.range=8
        light.brightness=i==1 and 1.2 or 1.0
        light.color=i==1 and Color(1,.93,.78,1) or Color(.40,.65,1,1)
        light.affectVolumetricFog=false
    end
    s.dressing=Dressing.Begin(s.root,MASK,opts)
    s.spin=Call(s,'geometry',s.root,'CreateChild','Node:CreateChild','WeaponTurntable');s.rotation=Quaternion(0,HOME_YAW,0);s.spin.rotation=s.rotation
    s.cameraNode=Call(s,'camera',s.root,'CreateChild','Node:CreateChild','ForgeCamera');s.cameraNode.position=Vector3(0,1,-3)
    s.camera=assert(Call(s,'camera',s.cameraNode,'CreateComponent','Node:CreateComponent','Camera'),'showroom Camera missing')
    Read(s,'camera',s.camera,'viewMask','Camera.viewMask')
    s.camera.fov=34;s.camera.nearClip=.05;s.camera.farClip=180;s.camera.viewMask=MASK
    Focus(s,opts and opts.focusX,opts and opts.focusY)
    Dof(s)
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
    local s={masks={},focusX=.30,focusY=.5,yaw=HOME_YAW,velocity=0,idle=1.5,dragging=false,home=false}
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
    Cancel(s);s.pending=copy;s.buildAge=0;state=BUILDING
end
---@param single table
function M.SetWeapon(single) Protect('SetWeapon',Weapon,single) end

local function BuildStep(s,dt)
    if s.pending then
        local single=s.pending;s.pending=nil
        s.pendingRoot=Call(s,'geometry',s.spin,'CreateChild','Node:CreateChild','PendingWeapon');s.pendingRoot.enabled=false
        s.job=Check(s,'geometry',Builder,'BeginPreview','WeaponBuilder.BeginPreview')(s.pendingRoot,single)
        return -- Compile and native emission never share one frame
    end
    local job=s.job
    if not job then return end
    s.stage,s.api,s.apiType='geometry','WeaponBuilder.StepPreview',type(Builder.StepPreview)
    s.buildAge=s.buildAge+dt;assert(s.buildAge<=5,'mesh build timeout')
    local done,mesh,err=Check(s,'geometry',Builder,'StepPreview','WeaponBuilder.StepPreview')(job,1)
    if job.geometry and not err then Isolate(s,'geometry',job.geometry) end -- hidden ancestor until atomic publish
    if not done then return end
    assert(mesh,err or 'mesh missing')
    local b=mesh.blueprint.bounds
    s.pendingRoot.position=Vector3(-(b.min[1]+b.max[1])*.5,-(b.min[2]+b.max[2])*.5,-(b.min[3]+b.max[3])*.5)
    Fit(s,mesh.blueprint)
    if s.mesh then Check(s,'geometry',Builder,'DisposePreview','WeaponBuilder.DisposePreview')(s.mesh) end
    Remove(s,s.meshRoot)
    s.mesh,s.meshRoot=mesh,s.pendingRoot;s.pendingRoot=nil;s.job=nil
    s.meshRoot.enabled=true;state=READY
    print('Forge showroom: ready')
end
local function UpdateImpl(s,dt)
    dt=Clamp(Finite(dt,0),0,1)
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
