-- Held ordinary breath regression; mocked rendering and ray queries.
package.path='scripts/?.lua;'..package.path
local V={}; V.__index=V
Vector3=setmetatable({}, {__call=function(_,x,y,z)return setmetatable({x=x,y=y,z=z},V)end})
function V.__add(a,b)return Vector3(a.x+b.x,a.y+b.y,a.z+b.z)end
function V.__sub(a,b)return Vector3(a.x-b.x,a.y-b.y,a.z-b.z)end
function V.__mul(a,b)if type(a)=='number'then a,b=b,a end return Vector3(a.x*b,a.y*b,a.z*b)end
function V.__div(a,b)return a*(1/b)end
function V:LengthSquared()return self.x*self.x+self.y*self.y+self.z*self.z end
function V:Length()return math.sqrt(self:LengthSquared())end
function V:Normalized()return self/math.max(1e-9,self:Length())end
function V:DotProduct(b)return self.x*b.x+self.y*b.y+self.z*b.z end
Vector3.UP=Vector3(0,1,0);Vector3.DOWN=Vector3(0,-1,0);Vector3.ZERO=Vector3(0,0,0)
Vector3.RIGHT=Vector3(1,0,0);Vector3.FORWARD=Vector3(0,0,1)
Quaternion=function(a)return setmetatable({}, {__mul=function(_,v)
 local r=math.rad(type(a)=='number' and a or 0)
 return Vector3(v.x*math.cos(r)+v.z*math.sin(r),v.y,-v.x*math.sin(r)+v.z*math.cos(r))
end})end
Color=function(r,g,b,a)return {r=r,g=g,b=b,a=a or 1}end
Variant=function(x)return x end
Vector4=function(x,y,z,w)return {x=x,y=y,z=z,w=w}end
Ray=function(o,d)return {origin=o,direction=d}end
Sphere=function(c,r)return {center=c,radius=r}end
package.loaded['dragon.VoxelFX']={}
package.loaded['urhox-libs.Platform.PlatformUtils']={IsWebPlatform=function()return true end,IsMobilePlatform=function()return false end}

Vector2=function(x,y)return {x=x,y=y}end
TRIANGLE_LIST=0
local nodes,vertices=0,0
local function Node()
    nodes=nodes+1
    return {CreateChild=function()return Node()end,
        CreateComponent=function()return {BeginGeometry=function()end,DefineVertex=function()vertices=vertices+1 end,
            DefineNormal=function()end,DefineTexCoord=function()end,Commit=function()end,SetMaterial=function()end}end,
        Remove=function()end}
end
Material={new=function()return {SetSurfaceShader=function()return true end,SetShaderParameter=function()end}end}
package.loaded['dragon.VoxelFX']={Motes=function()return {Update=function()end,Spawn=function()end}end}
local Stream=require('dragon.DragonStream')
local hit={hit=true,position=Vector3(0,2,5),distance=5,normal=Vector3(0,0,-1),volume={}}
local hits,rings=0,0
local ctrl={state='FLY',loco={airborne=true}}
local breath={ctrl=ctrl,S=1,listeners={function(info)
    hits=hits+1;assert(info.ordinary and info.power==1.8 and info.pos.z==5)
end}}
function breath:MouthFrame()return Vector3(0,2,0),Vector3.FORWARD end
function breath:TraceSurface(_,_,range)assert(range==18);return hit end
function breath:SpawnRing()rings=rings+1 end
local s=Stream.New(Node(),breath)
local allocated=nodes
for i=1,120 do s:Update(1/60,true,Vector3(0,2,20),true) end
assert(s.active and hits>100 and ctrl.state=='FLY','holding must spray without changing flight state')
assert(s.node.scale.z==5,'visible stream must end at first wall')
assert(nodes==allocated and vertices==18,'render geometry must be reused while holding')
assert(rings>=4 and rings<=6,'impact rings must remain lightweight')
local n=hits
s:Update(1/60,false,Vector3(0,2,20),true)
assert(not s.active and not s.node.enabled and hits==n,'release stops damage and ribbon immediately')
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
