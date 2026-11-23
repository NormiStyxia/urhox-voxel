-- Run from the project root with Lua 5.4. The capture scheduler and resource lifecycle
-- come from HomeIsland. These stand-ins record calls made to the renderer.
package.path = 'scripts/?.lua;' .. package.path
local home = require('ruins.HomeIsland')
local Vec = {}; Vec.__index = Vec
Vector3 = setmetatable({}, {__call = function(_, x, y, z) return setmetatable({x=x,y=y,z=z}, Vec) end})
Vector3.UP = Vector3(0,1,0)
function Vec.__sub(a,b) return Vector3(a.x-b.x,a.y-b.y,a.z-b.z) end
function Vec.__mul(a,s) return Vector3(a.x*s,a.y*s,a.z*s) end
function Vec:DotProduct(b) return self.x*b.x+self.y*b.y+self.z*b.z end
function Vec:LengthSquared() return self:DotProduct(self) end
function Vec:Length() return math.sqrt(self:LengthSquared()) end
function Vec:Normalized() return self*(1/self:Length()) end
function Vec:Cross(b) return Vector3(self.y*b.z-self.z*b.y,self.z*b.x-self.x*b.z,self.x*b.y-self.y*b.x) end
function Vector4(x,y,z,w) return {x=x,y=y,z=z,w=w} end
function Variant(v) return v end
function Color(r,g,b,a) return {r=r,g=g,b=b,a=a} end
function Plane(n,p) return {normal=n,point=p} end
function BoundingBox(lo,hi) return {min=lo,max=hi} end
OUTSIDE, CMD_CLEAR, CMD_SCENEPASS, CMD_FORWARDLIGHTS = 0,1,2,4
TEXTURE_RENDERTARGET, FILTER_BILINEAR, COORD_U, COORD_V, ADDRESS_CLAMP, SURFACE_MANUALUPDATE = 13,14,15,16,17,18
local mirrorBit, waterBit = 0x08000000, 0x10000000
local visible, width, height = true,2560,1352
local sky = {viewMask=0xffffffff}
local source = {node={}, fov=55, zoom=1, nearClip=.1, farClip=600, viewMask=0xffffffff, viewOverrideFlags=5}
source.frustum = {IsInsideFast=function(_,b)
    assert(b.min.y<5.625 and b.max.y>5.625)
    return visible and 1 or OUTSIDE
end}
local material = {}; home.spring=material
local failure, current, captureNode, path
local allocated, disposed, created, removed, queued = 0,0,0,0,0
function material:SetShaderParameter(name,value) self[name]=value end
function material:SetSurfaceTexture(name,t) self[name]=t; return t==nil or failure~='bind' end
Graphics = {GetRGBAFloat16Format=function() return 23 end}
graphics = {GetWidth=function() return width end, GetHeight=function() return height end}
cache = {GetResource=function(_,kind,res)
    assert(kind=='XMLFile' and res=='RenderPaths/Forward.xml')
    return failure~='path' and {} or nil
end}
Texture2D = {new=function()
    allocated=allocated+1
    local t,surface={},{}
    t.surface=surface; current=t
    function t:SetNumLevels(n) assert(n==1); self.levels=n end
    function t:SetSRGB(on) assert(on==false); self.srgb=on end
    function t:SetSize(w,h,format,usage)
        assert(self.srgb==false and self.levels==1 and format==23 and usage==TEXTURE_RENDERTARGET)
        self.w,self.h=w,h
        return failure~='format'
    end
    function t:SetFilterMode(mode) assert(mode==FILTER_BILINEAR) end
    function t:SetAddressMode(axis,mode) assert((axis==COORD_U or axis==COORD_V) and mode==ADDRESS_CLAMP) end
    function t:GetRenderSurface() if failure~='surface' then return surface end end
    function surface:SetUpdateMode(mode) assert(mode==SURFACE_MANUALUPDATE); self.mode=mode end
    function surface:SetViewport(i,v) assert(i==0); self.view=v end
    function surface:SetNumViewports(n) assert(n==0); self.view=nil end
    function surface:QueueUpdate() assert(self.view and self.mode); queued=queued+1 end
    function t:Dispose()
        assert(not self.disposed and not self.surface.view and material.mirror_color~=self)
        self.disposed=true; disposed=disposed+1
    end
    return t
end}
local function setDirection(n,dir)
    n.worldDirection=dir; n.worldRight=Vector3.UP:Cross(dir):Normalized(); n.worldUp=dir:Cross(n.worldRight)
end
local scene = {CreateChild=function(_,name)
    assert(name=='HomeSpringMirror'); created=created+1
    local n={}; captureNode=n
    function n:CreateComponent(kind) assert(kind=='Camera'); self.camera={}; return self.camera end
    function n:SetWorldTransform(pos,rot) self.worldPosition=pos; setDirection(self,rot.forward) end
    function n:SetWorldDirection(dir) setDirection(self,dir) end
    function n:Remove() assert(not self.removed); self.removed=true; removed=removed+1 end
    return n
end}
Viewport = {new=function(_,s,c)
    assert(s==scene and c==captureNode.camera)
    local commands={{type=CMD_CLEAR},{type=CMD_SCENEPASS,pass=failure=='pass' and 'other' or 'base'},
        {type=CMD_FORWARDLIGHTS},{type=CMD_SCENEPASS,pass='alpha'},{type=CMD_SCENEPASS,pass='refract'}}
    path={GetNumCommands=function() return #commands end, GetCommand=function(_,i) return commands[i+1] end,
        RemoveCommand=function(_,i) table.remove(commands,i+1) end}
    return {SetRenderPath=function(_,p) assert(p) end,GetRenderPath=function() return path end}
end}
local function face(x,y,z)
    local f=Vector3(x,y,z):Normalized()
    setDirection(source.node,f); source.node.worldRotation={forward=f}
end
local function update(tier,dt) home.UpdateReflection(dt or 1/120,scene,source,tier,sky) end
local function released()
    assert(allocated==disposed and created==removed and sky.viewMask==0xffffffff)
    assert(not material.mirror_color and (material.mirror_weight or 0)==0)
end
local centre=Vector3(712.5,5.625,-5.25)
local function uv(point)
    local eye=material.mirror_eye; local d=point-Vector3(eye.x,eye.y,eye.z)
    local z=d:DotProduct(material.mirror_forward)
    return .5+d:DotProduct(material.mirror_right)/z,.5+d:DotProduct(material.mirror_up)/z
end
source.node.worldPosition=Vector3(712.5,8,-24); face(0,-.2,1)
visible=false; update('low'); assert(allocated==0); visible=true
for _,stage in ipairs({'format','surface','path','pass','bind'}) do
    failure=stage; local before=allocated
    for _=1,240 do update('low') end
    assert(allocated==before+1 and queued==0); released()
    home.ReleaseReflection(); print('PASS low falls back to the Zone, no per-frame retry:',stage)
end
failure=nil
for _,tier in ipairs({{'low',288,152,6,2},{'medium',448,237,16,.5},{'high',640,338,24,.5}}) do
    local name,w,h,hz,idle=table.unpack(tier)
    home.ReleaseReflection(); update(name); assert(material.mirror_weight==0)
    local q0=queued
    for i=1,240 do source.node.worldPosition=Vector3(709+i/30,9,-24); update(name) end
    local moving=queued-q0
    assert(current.w==w and current.h==h and math.abs(moving-2*hz)<=1)
    assert(material.mirror_color==current and material.mirror_weight==1)
    local cam=captureNode.camera
    assert(cam.viewMask==mirrorBit and cam.viewMask & waterBit==0 and sky.viewMask & mirrorBit==0 and sky.viewMask & 1==1)
    assert(cam.useReflection and cam.reflectionPlane.point.y==5.625 and cam.useClipping and math.abs(cam.clipPlane.point.y-5.565)<1e-7)
    local clear=path:GetCommand(0)
    assert(path:GetNumCommands()==3 and clear.useFogColor==false and clear.clearColor.a==0)
    assert(source.viewOverrideFlags==5 and cam.viewOverrideFlags==(source.viewOverrideFlags | 2))
    q0=queued
    for _=1,480 do update(name) end
    local stationary=queued-q0; assert(math.abs(stationary-4/idle)<=1)
    print(('PASS %s %dx%d linear RGBA16F: %d updates/2s moving, %d/4s stationary'):format(name,w,h,moving,stationary))
end
for _,offset in ipairs({-18,18}) do
    for _,elevation in ipairs({2.1,12}) do
        home.ReleaseReflection(); source.node.worldPosition=Vector3(centre.x,centre.y+elevation,centre.z+offset)
        local maxError,behind=0,0
        for i=0,240 do
            local a=i*math.pi/240; face(math.sin(a),-elevation/18*(1-i/240)-.05,(offset<0 and 1 or -1)*math.cos(a)); update('low')
            local u,v=uv(centre); maxError=math.max(maxError,math.abs(u-.5),math.abs(v-.5))
            if (Vector3(714,10,8)-source.node.worldPosition):DotProduct(source.node.worldDirection)<0 then behind=behind+1 end
        end
        local eye=material.mirror_eye; local pos=source.node.worldPosition
        assert(eye.x==pos.x and eye.y==pos.y and eye.z==pos.z and eye.w==centre.y)
        assert(material.mirror_up:DotProduct(captureNode.worldUp)<0 and material.mirror_right:DotProduct(captureNode.worldRight)>0)
        assert(behind>0 and maxError<1e-6 and captureNode.camera.farClip<61)
        print(('PASS low 180-degree turn, bank z=%+d, eye %.1f m, house behind camera %d frames, centre UV drift %.8f'):format(offset,elevation,behind,maxError))
    end
end
-- Inside the pool the capture follows the primary lens. Check a metre on
-- either axis as well as the capture origin and centre point.
home.ReleaseReflection()
source.node.worldPosition=Vector3(centre.x,centre.y+2,centre.z-2); face(0,-1,1)
update('low'); local u,v=uv(centre)
local rightU,rightV=uv(Vector3(centre.x+1,centre.y,centre.z))
local sy=.5/(1.36*math.tan(math.rad(source.fov)*.5))
assert(math.abs(u-.5)<1e-6 and math.abs(v-.5)<1e-6 and math.abs(rightV-v)<1e-6)
assert(math.abs(rightU-u-sy/(width/height)/math.sqrt(8))<1e-6)
local _,farV=uv(Vector3(centre.x,centre.y,centre.z+1)); assert(farV<v)
print('PASS low near-camera capture axes, zoom, vertical orientation and perspective projection')
local before=queued; visible=false; update('low',5); assert(queued==before and material.mirror_weight==0)
visible=true; update('low'); update('low'); assert(material.mirror_weight>0 and material.mirror_weight<.1)
source.node.worldPosition=Vector3(centre.x,5.5,centre.z); before=queued; update('low',3); assert(queued==before and material.mirror_weight==0)
source.node.worldPosition=Vector3(centre.x,8,-24); source.viewMask=1; update('low',3); assert(queued==before); source.viewMask=0xffffffff
home.planarReflectionEnabled=false; update('low'); released()
home.planarReflectionEnabled=true; width,height=810,1440; update('low'); assert(current.w==162 and current.h==288)
home.ReleaseReflection(); released()

local nearby=Vector3(centre.x,8,-24)
local atLimit=Vector3(home.x+110,8,home.z)
local far=Vector3(home.x+110.01,8,home.z)
local function at(pos,inView,dt)
    source.node.worldPosition=pos; visible=inView; update('low',dt)
end
local function checkVisibleReturn()
    local allocations,captures=allocated,queued
    at(nearby,false,2); assert(allocated==allocations and queued==captures)
    at(nearby,true,1/60)
    assert(allocated==allocations+1 and queued==captures+1 and material.mirror_color==current)
    assert(material.mirror_weight==0)
    update('low',.05); assert(material.mirror_weight>0 and material.mirror_weight<1)
    update('low',.17); assert(material.mirror_weight==1)
end

checkVisibleReturn()
local original,allocations,captures=current,allocated,queued
at(nearby,false,3); at(Vector3(centre.x,5,centre.z),true,3)
for _=1,4 do at(far,false,.75); at(atLimit,false,.05) end
at(nearby,true,.10)
assert(material.mirror_color==original and not original.disposed and allocated==allocations and queued==captures+1)
captures=queued
at(far,true,.75); at(far,false,.1875); assert(material.mirror_color==original and not original.disposed)
at(far,false,.0625); released(); assert(original.disposed and queued==captures)
at(far,true,5); assert(allocated==allocations and queued==captures)
checkVisibleReturn(); assert(current~=original)
print('PASS 3 s out of view, 3 s underwater and four 110 m boundary crossings reused one RTT; 0.9375 s far retained it, 1.0000 s released it, visible return rebuilt and faded in')

home.ReleaseReflection(); failure='bind'; at(nearby,true,.1); released()
failure=nil; allocations=allocated; captures=queued
at(nearby,true,3); at(far,true,.875); at(atLimit,false,.125); at(far,true,.5); at(nearby,true,2)
assert(allocated==allocations and queued==captures and material.mirror_weight==0)
at(far,false,.5); at(Vector3(far.x,5,far.z),false,.5); at(far,true,3); released()
assert(allocated==allocations and queued==captures)
checkVisibleReturn()
print('PASS same-size failure stayed cached inside the range and through boundary jitter; a continuous 1 s exit cleared it and visible return recovered once at the same resolution')

home.Stop(); home.Stop(); released()
print(('PASS frustum, waterline, view mask, fade, A/B switch, portrait, re-entry and repeated Stop; %d textures allocated/disposed, %d nodes created/removed'):format(allocated,created))
