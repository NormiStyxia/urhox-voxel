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
-- ULP here is <0.25mm (weapon cells=30mm). The room's half extent is 12m.
-- Draw budget: one combined unlit backdrop/podium batch, plus one weapon batch.
-- Native Commit is indivisible; StepPreview's 2ms budget is cooperative, not a
-- guarantee that a GPU upload/Compile cannot exceed 2ms on a slow platform.
local Builder=require('combat.WeaponBuilder')
local M={}
local MASK=0x40000000
local KEEP=0xffffffff~MASK
local AUTO_SPEED,HOME_YAW,DRAG_SCALE=12,25,.35
local OFF,BUILDING,READY,FAILED='off','building','ready','failed'
---@type table?
local session
local state=OFF

local function Finite(v,fallback)
    return type(v)=='number' and v==v and math.abs(v)<math.huge and v or fallback
end
local function Clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function Remove(node) if node then pcall(node.Remove,node) end end
local function Cancel(s)
    if s.job then pcall(Builder.CancelPreview,s.job);s.job=nil end
    Remove(s.pendingRoot);s.pendingRoot=nil;s.pending=nil
end
local function Cleanup(s)
    if not s then return end
    Cancel(s)
    if s.mesh then pcall(Builder.DisposePreview,s.mesh);s.mesh=nil end
    -- Attempt every cleanup even if one native handle was already invalidated.
    if s.switched then
        local ok,err=pcall(renderer.SetViewport,renderer,0,s.previousViewport)
        if not ok then print('Forge showroom: viewport restore failed '..tostring(err)) end
    end
    for i=#s.masks,1,-1 do
        local saved=s.masks[i]
        pcall(function() saved.object[saved.field]=saved.value end)
    end
    Remove(s.root)
    if s.roomMaterial then pcall(s.roomMaterial.Dispose,s.roomMaterial) end
end
local function Failed(reason)
    local old=session;session=nil;state=FAILED
    Cleanup(old)
    print('Forge showroom: failed ('..tostring(reason):sub(1,300)..')')
end
local function Protect(fn,...)
    if not session then return end
    local ok,err=pcall(fn,session,...)
    if not ok then Failed(err) end
end

---@param drawable Drawable
local function Isolate(drawable)
    drawable.viewMask=MASK;drawable.lightMask=MASK;drawable.zoneMask=MASK
    drawable.castShadows=false
end
local function SaveMask(s,object,field)
    local value=assert(tonumber(object[field]),field..' binding unavailable')
    s.masks[#s.masks+1]={object=object,field=field,value=value}
    object[field]=value&KEEP
end
local function IsolateWorld(s,scene)
    -- Enumerate exact types (GetComponents does not promise derived-type lookup).
    for _,light in ipairs(scene:GetComponents('Light',true)) do
        SaveMask(s,light,'viewMask');SaveMask(s,light,'lightMask')
    end
    for _,kind in ipairs({'Skybox','CustomGeometry'}) do
        for _,drawable in ipairs(scene:GetComponents(kind,true)) do SaveMask(s,drawable,'viewMask') end
    end
end

---@param g CustomGeometry
local function Triangle(g,a,b,c,color)
    for _,p in ipairs({a,b,c}) do g:DefineVertex(p);g:DefineNormal(Vector3.UP);g:DefineColor(color) end
end
---@param s table
local function Room(s)
    local mat=Material:new();s.roomMaterial=mat
    mat:SetTechnique(0,assert(cache:GetResource('Technique','Techniques/NoTextureUnlit.xml'),'unlit technique missing'))
    mat.vertexShaderDefines='VERTEXCOLOR';mat.pixelShaderDefines='VERTEXCOLOR'
    mat:SetShaderParameter('MatDiffColor',Variant(Color(1,1,1,1)))
    mat.cullMode=CULL_NONE
    local node=s.root:CreateChild('BackdropAndPodium')
    local g=assert(node:CreateComponent('CustomGeometry'),'room geometry missing')
    Isolate(g);g.occluder=false
    g:BeginGeometry(0,TRIANGLE_LIST)
    local dark,top,side=Color(.025,.04,.07,1),Color(.12,.16,.21,1),Color(.055,.075,.11,1)
    -- A closed, inward-visible room prevents sky/clear-color leaks at any aspect.
    for axis=1,3 do for _,sign in ipairs({-1,1}) do
        local a,b,c,d={0,0,0},{0,0,0},{0,0,0},{0,0,0}
        local u,v=axis%3+1,(axis+1)%3+1
        for _,p in ipairs({a,b,c,d}) do p[axis]=sign*12 end
        a[u],a[v]=-12,-12;b[u],b[v]=12,-12;c[u],c[v]=12,12;d[u],d[v]=-12,12
        local va,vb,vc,vd=Vector3(table.unpack(a)),Vector3(table.unpack(b)),Vector3(table.unpack(c)),Vector3(table.unpack(d))
        Triangle(g,va,vb,vc,dark);Triangle(g,va,vc,vd,dark)
    end end
    -- Sixteen-sided low circular stand, sharing the single unlit room material.
    for i=0,15 do
        local a,b=i*math.pi/8,(i+1)*math.pi/8
        local p,q=Vector3(math.cos(a)*.38,.08,math.sin(a)*.38),Vector3(math.cos(b)*.38,.08,math.sin(b)*.38)
        local lowP,lowQ=Vector3(p.x,0,p.z),Vector3(q.x,0,q.z)
        Triangle(g,Vector3(0,.08,0),p,q,top)
        Triangle(g,p,lowP,lowQ,side);Triangle(g,p,lowQ,q,side)
    end
    assert(g:Commit()~=false,'room Commit failed')
    assert(g:SetMaterial(0,mat)~=false,'room material failed')
end

local function Focus(s,x,y)
    s.focusX=Clamp(Finite(x,s.focusX),.1,.9)
    s.focusY=Clamp(Finite(y,s.focusY),.15,.85)
    -- Camera projection offsets are screen fractions (doubled into NDC). Positive Y
    -- is up, whereas panel fractions have top-left origin. No RTT flip involved.
    s.camera.projectionOffset=Vector2(s.focusX-.5,.5-s.focusY)
    s.fitDirty=true
end
local function Fit(s,bp)
    local b=bp.bounds;local lo,hi=b.min,b.max
    local halfY=(hi[2]-lo[2])*.5
    local radius=math.sqrt(((hi[1]-lo[1])*.5)^2+((hi[3]-lo[3])*.5)^2)
    local w,h=graphics:GetWidth(),graphics:GetHeight()
    assert(w>0 and h>0,'invalid drawable size')
    s.width,s.height=w,h
    local tan=math.tan(math.rad(s.camera.fov)*.5)
    local vertical=2*math.min(s.focusY,1-s.focusY)*.82
    -- The panel occupies the right: reserve at most 25% screen width each side
    -- of the pivot, and shrink automatically near an edge / on portrait phones.
    local horizontal=2*math.min(s.focusX,1-s.focusX,.25)*.82
    local distance=math.max(halfY/(tan*vertical),radius/(tan*(w/h)*horizontal))+radius+.18
    assert(distance<10,'weapon cannot fit within showroom')
    s.spin.position=Vector3(0,.20+halfY,0)
    s.cameraNode.position=Vector3(0,.20+halfY,-math.max(1.8,distance))
    s.fitDirty=false
end
local function EnterImpl(s,scene,opts)
    assert(scene and scene:GetComponent('Octree'),'main scene Octree required')
    s.previousViewport=renderer:GetViewport(0) -- retain same Viewport, never compare userdata wrappers
    IsolateWorld(s,scene)
    s.root=assert(scene:CreateChild('ForgeShowroom'),'showroom root missing')
    s.root.temporary=true;s.root.position=Vector3(2304,1200,0)
    local zone=s.root:CreateComponent('Zone');assert(zone,'showroom Zone missing')
    Isolate(zone);zone.boundingBox=BoundingBox(Vector3(-20,-20,-20),Vector3(20,20,20))
    zone.priority=100;zone.ambientSource=AMBIENT_COLOR;zone.ambientColor=Color(.12,.14,.18,1)
    zone.depthFogEnable=false;zone.heightFogEnable=false;zone.volumetricFogEnabled=false
    zone.autoExposureEnabled=false;zone.fogColor=Color(.025,.04,.07,1)
    for i=1,2 do
        local n=s.root:CreateChild(i==1 and 'WarmKey' or 'CoolRim')
        n.position=i==1 and Vector3(-2,3,-2) or Vector3(2,2,2)
        local light=assert(n:CreateComponent('Light'),'showroom light missing')
        Isolate(light);light.lightType=LIGHT_POINT;light.range=8
        light.brightness=i==1 and 5 or 4
        light.color=i==1 and Color(1,.91,.78,1) or Color(.40,.65,1,1)
        light.affectVolumetricFog=false
    end
    Room(s)
    s.spin=s.root:CreateChild('WeaponTurntable');s.rotation=Quaternion(0,HOME_YAW,0);s.spin.rotation=s.rotation
    s.cameraNode=s.root:CreateChild('ForgeCamera');s.cameraNode.position=Vector3(0,1,-3)
    s.camera=assert(s.cameraNode:CreateComponent('Camera'),'showroom Camera missing')
    s.camera.fov=34;s.camera.nearClip=.05;s.camera.farClip=32;s.camera.viewMask=MASK
    Focus(s,opts and opts.focusX,opts and opts.focusY)
    s.viewport=Viewport:new(scene,s.camera)
    assert(s.viewport,'showroom Viewport missing')
    s.switched=true -- even a partially successful binding must be rolled back
    renderer:SetViewport(0,s.viewport)
end

---@param scene Scene
---@param opts table?
---@return boolean
function M.Enter(scene,opts)
    M.Exit()
    local s={masks={},focusX=.30,focusY=.5,yaw=HOME_YAW,velocity=0,idle=1.5,dragging=false,home=false}
    session=s;state=BUILDING
    local ok,err=pcall(EnterImpl,s,scene,opts)
    if not ok then Failed(err);return false end
    return true
end
function M.Exit()
    local old=session;session=nil;state=OFF
    Cleanup(old)
end
local function Weapon(s,single)
    assert(type(single)=='table' and (single.weapon=='sword' or single.weapon=='bow'),'invalid weapon config')
    -- Snapshot caller's draft, since BeginPreview is deferred until Update.
    local copy={weapon=single.weapon,parts={},colors={}}
    for k,v in pairs(single.parts or {}) do copy.parts[k]=v end
    for k,v in pairs(single.colors or {}) do copy.colors[k]=v end
    Cancel(s);s.pending=copy;s.buildAge=0;state=BUILDING
end
---@param single table
function M.SetWeapon(single) Protect(Weapon,single) end

local function BuildStep(s,dt)
    if s.pending then
        local single=s.pending;s.pending=nil
        s.pendingRoot=s.spin:CreateChild('PendingWeapon');s.pendingRoot.enabled=false
        s.job=Builder.BeginPreview(s.pendingRoot,single)
        return -- Compile and native emission never share one frame
    end
    local job=s.job
    if not job then return end
    s.buildAge=s.buildAge+dt;assert(s.buildAge<=5,'mesh build timeout')
    local done,mesh,err=Builder.StepPreview(job,2)
    if job.geometry then Isolate(job.geometry) end -- hidden ancestor until atomic publish
    if not done then return end
    assert(mesh,err or 'mesh missing')
    local b=mesh.blueprint.bounds
    s.pendingRoot.position=Vector3(-(b.min[1]+b.max[1])*.5,-(b.min[2]+b.max[2])*.5,-(b.min[3]+b.max[3])*.5)
    Fit(s,mesh.blueprint)
    if s.mesh then Builder.DisposePreview(s.mesh) end
    Remove(s.meshRoot)
    s.mesh,s.meshRoot=mesh,s.pendingRoot;s.pendingRoot=nil;s.job=nil
    s.meshRoot.enabled=true;state=READY
    print('Forge showroom: ready')
end
local function UpdateImpl(s,dt)
    dt=Clamp(Finite(dt,0),0,1)
    BuildStep(s,dt)
    if s.mesh and (s.fitDirty or graphics:GetWidth()~=s.width or graphics:GetHeight()~=s.height) then Fit(s,s.mesh.blueprint) end
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
    s.yaw=s.yaw%360;s.rotation:FromEulerAngles(0,s.yaw,0);s.spin.rotation=s.rotation
end
---@param dt number
function M.Update(dt) Protect(UpdateImpl,dt) end
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
function M.SetFocus(fractionX,fractionY) Protect(Focus,fractionX,fractionY) end
---@return boolean
function M.IsReady() return session~=nil and state==READY end
---@return string
function M.State() return state end
---@return boolean
function M.Active() return session~=nil end
return M
