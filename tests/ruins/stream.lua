-- Held ordinary breath regression; mocked rendering and ray queries.
package.path='scripts/?.lua;'..package.path
local V={}; V.__index=V
Vector3=setmetatable({}, {__call=function(_,x,y,z)return setmetatable({x=x,y=y,z=z},V)end})
function V.__add(a,b)return Vector3(a.x+b.x,a.y+b.y,a.z+b.z)end
function V.__sub(a,b)return Vector3(a.x-b.x,a.y-b.y,a.z-b.z)end
function V.__mul(a,b)if type(a)=='number'then a,b=b,a end return Vector3(a.x*b,a.y*b,a.z*b)end
function V.__unm(a)return a*(-1)end
function V:CrossProduct(b)return Vector3(self.y*b.z-self.z*b.y,self.z*b.x-self.x*b.z,self.x*b.y-self.y*b.x)end
function V.__div(a,b)return a*(1/b)end
function V:LengthSquared()return self.x*self.x+self.y*self.y+self.z*self.z end
function V:Length()return math.sqrt(self:LengthSquared())end
function V:Normalized()return self/math.max(1e-9,self:Length())end
function V:DotProduct(b)return self.x*b.x+self.y*b.y+self.z*b.z end
Vector3.UP=Vector3(0,1,0);Vector3.DOWN=Vector3(0,-1,0);Vector3.ZERO=Vector3(0,0,0)
Vector3.RIGHT=Vector3(1,0,0);Vector3.FORWARD=Vector3(0,0,1)
Quaternion=function(from,to)
    return setmetatable({}, {__mul=function(_,v)
        local axis = from:CrossProduct(to)
        local dot = from:DotProduct(to)
        if dot < -.9999 then return Vector3(-v.x,v.y,-v.z) end
        return v + axis:CrossProduct(v) + axis:CrossProduct(axis:CrossProduct(v))/(1+dot)
    end})
end
Color=function(r,g,b,a)return {r=r,g=g,b=b,a=a or 1}end
Variant=function(x)return x end
Vector4=function(x,y,z,w)return {x=x,y=y,z=z,w=w}end
Ray=function(o,d)return {origin=o,direction=d}end
Sphere=function(c,r)return {center=c,radius=r}end
package.loaded['urhox-libs.Platform.PlatformUtils']={IsWebPlatform=function()return true end,IsMobilePlatform=function()return false end}

Vector2=function(x,y)return {x=x,y=y}end
TRIANGLE_LIST=0
FC_NONE=0
local nodes,vertices,slots=0,0,0
local function BillboardSet()
    local boards = {}
    return {SetMaterial=function()end, SetRelative=function()end, SetSorted=function()end,
        SetFaceCameraMode=function(self,mode) self.faceCameraMode=mode end,
        SetNumBillboards=function(_,n)
            slots=slots+n
            for i=0,n-1 do boards[i]={} end
        end,
        GetBillboard=function(_,i)return assert(boards[i]) end, Commit=function()end}
end
local function Node()
    nodes=nodes+1
    return {CreateChild=function()return Node()end,
        CreateComponent=function(_,kind)
            if kind=='BillboardSet' then return BillboardSet() end
            return {BeginGeometry=function()end,DefineVertex=function()vertices=vertices+1 end,
            DefineNormal=function()end,DefineTexCoord=function()end,Commit=function()end,SetMaterial=function()end}end,
        Remove=function()end}
end
Material={new=function()return {SetSurfaceShader=function()return true end,SetShaderParameter=function()end}end}
require('dragon.VoxelFX').Material=function()return Material:new()end
local Stream=require('dragon.DragonStream')
local hit={hit=true,position=Vector3(0,2,5),distance=5,normal=Vector3(0,0,-1),volume={}}
local hits=0
local ctrl={state='FLY',loco={airborne=true}}
local breath={ctrl=ctrl,S=1,listeners={function(info)
    hits=hits+1;assert(info.ordinary and info.power==1.8 and info.pos.z==5)
end}}
function breath:MouthFrame()return Vector3(0,2,0),Vector3.FORWARD end
function breath:TraceSurface(_,_,range)assert(range==18);return hit end

local s=Stream.New(Node(),breath)
local allocated=nodes
for i=1,120 do s:Update(1/60,true,Vector3(0,2,20),true) end
assert(s.active and hits>100 and ctrl.state=='FLY','holding must spray without changing flight state')
assert(s.node.scale.z==5,'visible stream must end at first wall')
assert(nodes==allocated and vertices==18,'render geometry must be reused while holding')
local contact=s.contact
assert(contact.core.sprites.faceCameraMode==FC_NONE and contact.core.node.enabled)
local function near(a,b) return (a-b):LengthSquared()<1e-8 end
assert(near(contact.core.node.worldRotation*Vector3.FORWARD,hit.normal),'halo must face wall')
assert(slots==96+32+5*(6+1)+1,'fixed ribbon, ice, mist and core budgets')
local previous=hits
local deadline=s.time+.33
local spawned=0
local spawn=contact.chips.Spawn
function contact.chips:Spawn(p)
    spawned=spawned+1
    local lift=p.vel:DotProduct(hit.normal)
    assert(lift>0 and lift<1.21 and (p.vel-hit.normal*lift):Length()>1.4,'chips eject along surface')
    return spawn(self,p)
end
while s.time < deadline do s:Update(1/60,true,nil,true) end
assert(hits>previous and spawned>=3 and spawned<=6,'stationary contact uses sparse maintenance bursts')
local oldWave=contact.waves[(contact.nextWave-2)%#contact.waves+1]
local oldPos=oldWave.node.worldPosition
hit.normal=Vector3.UP
hit.position=Vector3(2,0,5)
local before=spawned
for i=1,9 do s:Update(1/60,true,nil,true) end
assert(spawned==before+7 and near(oldWave.node.worldPosition,oldPos),'new face bursts while old mist remains')
assert(near(contact.core.node.worldRotation*Vector3.FORWARD,hit.normal),'halo must face floor')
hit.normal=Vector3(0,1,-1):Normalized()
for i=1,600 do
    hit.position=Vector3(i*.5,1,5)
    s:Update(1/60,true,nil,true)
    assert(contact.chips:Count()<=32)
end
assert(spawned-before<=7*(10.15/.12+1),'sweeping must respect global burst cooldown')
assert(nodes==allocated and near(contact.core.node.worldRotation*Vector3.FORWARD,hit.normal))
hit.hit=false
s:Update(1/60,true,nil,true)
assert(contact.core.node.enabled and contact.lastPos==nil,'miss should begin tail')
hit.hit=true
local n=hits
s:Update(1/60,false,Vector3(0,2,20),true)
assert(not s.active and not s.node.enabled and hits==n,'release stops damage and ribbon immediately')
local coreAlpha=contact.core.sprites:GetBillboard(0).color.a
for i=1,8 do s:Update(1/60,false,nil,true) end
assert(contact.core.node.enabled and contact.core.sprites:GetBillboard(0).color.a<coreAlpha,'glow fades after release')
local residual=false
for _,w in ipairs(contact.waves) do residual=residual or w.node.enabled end
assert(residual,'mist survives release')
for i=1,50 do s:Update(1/60,false,nil,true) end
assert(not contact.core.node.enabled and contact.chips:Count()==0)
for _,w in ipairs(contact.waves) do assert(not w.node.enabled,'mist must expire') end
s:Update(1/60,true,nil,true);assert(s.active)
s:Update(1/60,true,nil,false);assert(not s.active)
s:Update(1/60,true,nil,true);assert(not s.active,'focus/menu cancellation requires a fresh press')
s:Update(1/60,false,nil,true);s:Update(1/60,true,nil,true);assert(s.active)
ctrl.state='BREATH';s:Update(1/60,true,nil,true);assert(not s.active,'cinematic breath excludes ordinary breath')
ctrl.state='WALK';s:Update(1/60,true,nil,true);assert(not s.active,'held input must not restart after special')
s:Update(1/60,false,nil,true);s:Update(1/60,true,nil,true);assert(s.active and ctrl.state=='WALK')
local pose={j={},body={}}
ctrl:overlayPose(pose);assert(pose.j.jaw[1]>0,'jaw opens as overlay')
local oldCast=s.castId
s:Stop(true);s:Update(1/60,true,nil,true);assert(not s.active)
s:Update(1/60,false,nil,true);s:Update(1/60,true,nil,true);assert(s.castId==oldCast+1)
s:Destroy();assert(ctrl.stream==nil and ctrl.overlayPose==nil)
print('ordinary stream PASS: held/release, ground+air, first-hit limit, cancel/rearm, special exclusion, bounded geometry')
