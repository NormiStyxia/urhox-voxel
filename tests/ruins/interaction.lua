-- Offline integration of real spell/ride/scene adapter methods; engine queries are doubles.
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
local Spells=require('ruins.TimeSpells')
local count=0
local caster=Spells.NewCaster({})
caster.Cast=function(_,id,aim)count=count+1 end
local prev=0
for i=0,100 do local r=Spells.ShatterRadius(i/100);assert(r>=prev);prev=r end
assert(math.abs(Spells.ShatterRadius(0)-.9)<1e-6 and math.abs(prev-3.2)<1e-6)
caster:HandleCharge(true,{},true);caster:Update(.7);assert(math.abs(caster.charge-.5)<1e-6)
caster:Update(1);assert(caster.charge==1)
caster:HandleCharge(false,{},true);caster:HandleCharge(false,{},true);assert(count==1)
caster:HandleCharge(true,{},true);caster:Update(.4)
caster:HandleCharge(false,{},false);caster:HandleCharge(false,{},true)
assert(count==1 and not caster.charging and caster.charge==0,'focus/mount cancellation must not cast')
local rig={size=1,root={worldPosition=Vector3.ZERO,worldRotation=Quaternion(0)},
 bones={chest={worldPosition=Vector3(0,2,0)},pelvis={worldPosition=Vector3(0,2,-1)}}}
local ctrl={rig=rig,loco={pos=Vector3.ZERO,yaw=0,alt=0,airborne=false},state='IDLE'}
function ctrl:GroundHeight()return 0 end
local world={damage=0,expectedPower=3}
function world:SphereCast()return {hit=false}end
function world:RaycastSingle(ray,distance)
 if ray.direction.y<-.9 then return {hit=true,position=Vector3(ray.origin.x,0,ray.origin.z),normal=Vector3.UP} end
 return {hit=false}
end
function world:ApplyDamage(v,p,r,power)self.damage=self.damage+1;self.lastVolume=v;assert(power==self.expectedPower);return 10 end
function world:ApplyRadialImpulse()end
local nomi={pos=Vector3(.1,.8,0),node={}}
function nomi:Position()return self.pos end
nomi.cc={Teleport=function(_,p)nomi.pos=p end}
local host={rig=rig,ctrl=ctrl,ride={mode='free'},breath={OnHit=function(self,f)self.listener=f end}}
local puzzles={FindByVolume=function()return nil end}
local D=require('ruins.RuinsDragon').New(host,world,nomi,puzzles,{})
D:PushPlayer();assert(D:OutsideBody(nomi.pos,.33),'external character cannot pass through dragon body')
ctrl.loco.airborne=true;assert(D:DismountPoint()==nil,'airborne dismount unsafe')
ctrl.loco.airborne=false;assert(D:DismountPoint()~=nil,'open ground permits safe dismount')
world.SphereCast=function()return {hit=true,distance=.36,normal=Vector3(-1,0,0)}end
ctrl.loco.pos=Vector3(1,0,0);ctrl.loco.speed=12
D:ResolveMotion(ctrl,Vector3.ZERO,0,0)
assert(ctrl.loco.pos.x<=.301 and ctrl.loco.speed==0,'motion sweep must stop at wall')
world.SphereCast=function()return {hit=false}end
ctrl.loco.pos=Vector3(1,0,0);ctrl.loco.speed=5
D:ResolveMotion(ctrl,Vector3.ZERO,0,0);assert(ctrl.loco.pos.x==1 and ctrl.loco.speed==5)
local vol={destructible=true}
local info={pos=Vector3.ZERO,normal=Vector3.UP,radius=3,volume=vol,dir=Vector3.FORWARD,element='astral',cast=1}
for i=1,100 do D.time=i*.01;D:Hit(info) end
assert(world.damage>=7 and world.damage<=9,'damage must be frame rate limited')
assert(world.lastVolume==vol and #D.patches==1)
world.expectedPower=1.8;info.ordinary=true;info.power=1.8
D.time=D.time+.2;D:Hit(info)
world.expectedPower=3;info.ordinary=nil
local times=0;local obj={canShatter=true,state='WHOLE',Shatter=function()times=times+1 end}
puzzles.FindByVolume=function()return obj end
for i=1,5 do D.time=D.time+.2;D:Hit(info) end
assert(times==1,'do not repeatedly refine the same time object every breath frame')
info.cast=2;D.time=D.time+.2;D:Hit(info);assert(times==2)
for i=1,20 do D:AddIce(Vector3(i*12,0,0),5) end
assert(#D.patches==6,'frost patch pool bounded')
host.ride.mode='mounted';D:Update(19);assert(#D.patches==0,'ice expires')
local B=require('dragon.DragonBreath')
local breath=B.New(nil,rig,{world=world,time=0},'no-breath',nil)
local hit={hit=true,position=Vector3(0,1,3),normal=Vector3(0,0,-1),distance=3,volume=vol}
world.RaycastSingle=function(_,ray,d)assert(d==30 and ray.origin.y==1);return hit end
assert(breath:TraceSurface(Vector3(0,1,0),Vector3.FORWARD,30)==hit,'breath preserves first wall hit')
print('interaction PASS: charge/release/cancel, dragon push/motion/dismount, breath hit/damage/ice lifecycle')
