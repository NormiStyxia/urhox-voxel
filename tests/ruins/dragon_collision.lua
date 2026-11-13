-- Run through lupa.lua54; real collision/adapter code, analytic query doubles.
package.path='scripts/?.lua;'..package.path
local V={}; V.__index=V
Vector3=setmetatable({}, {__call=function(_,x,y,z)return setmetatable({x=x or 0,y=y or 0,z=z or 0},V)end})
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
local Q={};Q.__index=Q
Quaternion=function(a)return setmetatable({a=a or 0},Q)end
function Q:Inverse()return Quaternion(-self.a)end
function Q.__mul(q,v)local r=math.rad(q.a);return Vector3(v.x*math.cos(r)+v.z*math.sin(r),v.y,-v.x*math.sin(r)+v.z*math.cos(r))end
Sphere=function(c,r)return {center=c,radius=r}end
Ray=function(o,d)return {origin=o,direction=d}end
package.loaded['dragon.DragonStream']={}
local C=require('dragon.DragonCollision')
local checks=0
local function check(ok,msg)checks=checks+1;assert(ok,msg)end
local function close(a,b)return math.abs(a-b)<1e-5 end
local world={planes={},volumes={}}
function world:SphereCast(s,d,limit,mask)
    check(mask==C.MASK,'sweeps exclude visual dragon layer')
    local best={hit=false,distance=math.huge}
    for _,p in ipairs(self.planes)do
        local into=d:DotProduct(p.n)
        if into<-.000001 then
            local distance=math.max(0,(s.center:DotProduct(p.n)-p.d-s.radius)/-into)
            if distance<=limit and distance<best.distance then best={hit=true,distance=distance,normal=p.n}end
        end
    end
    return best
end
function world:GetVolumeCount()return #self.volumes end
function world:GetVolume(i)return self.volumes[i+1]end
function world:RaycastSingle(ray)
    local y=self.floor or 0
    if self.void or ray.origin.y<y then return {hit=false}end
    return {hit=true,position=Vector3(ray.origin.x,y,ray.origin.z),normal=Vector3.UP}
end
local hull={{offset=Vector3.ZERO,radius=.5}}
world.planes={{n=Vector3(-1,0,0),d=-2}}
local p=C.Slide(world,hull,Vector3.ZERO,0,Vector3(3,0,2))
check(p.x<1.5 and p.x>1.4 and close(p.z,2),'diagonal movement slides the full tangent distance')
p=C.Slide(world,hull,Vector3(1.48,0,0),0,Vector3(-1,0,0))
check(close(p.x,.48),'moving away from a contact is allowed')
world.planes[2]={n=Vector3(0,0,-1),d=-2}
p=C.Slide(world,hull,Vector3.ZERO,0,Vector3(3,0,4))
check(p.x<1.5 and p.z<1.5,'two-wall corner preserves both contact planes')
world.planes={{n=Vector3(1,0,0),d=0}}
local angle=C.Turn(world,{{offset=Vector3(0,0,2),radius=.005}},Vector3.ZERO,179,-179)
check(math.abs(angle)>178,'blocked yaw wrap never jumps to zero')
world.planes={}
check(close(C.Turn(world,hull,Vector3.ZERO,179,-179),-179),'unblocked yaw wraps by the short arc')

local function volume(pos,rot,scale,dims,solid)
    local node={worldPosition=pos,worldRotation=Quaternion(rot),worldScale=scale}
    function node:WorldToLocal(v)local d=self.worldRotation:Inverse()*(v-self.worldPosition);return Vector3(d.x/scale.x,d.y/scale.y,d.z/scale.z)end
    function node:LocalToWorld(v)return self.worldPosition+self.worldRotation*Vector3(v.x*scale.x,v.y*scale.y,v.z*scale.z)end
    local grid={GetDimensions=function()return dims end,IsSolid=function(_,x,y,z)return solid(x,y,z)end}
    return {collisionLayer=1,collisionMask=0xffffffff,voxelSize=1,GetNode=function()return node end,
        GetGrid=function()return grid end,IsCollidable=function()return true end}
end
local box=volume(Vector3.ZERO,0,Vector3(1,1,1),Vector3(1,1,1),function()return true end)
world.volumes={box}
check(C.Clear(world,hull,Vector3(-.2,.5,.5),0,{left=100})==false,'sphere edge overlap detected with its centre outside the solid')
check(C.Clear(world,hull,Vector3(.5,.5,.5),0,{left=100})==false,'fully contained sphere is not clear')
check(C.Clear(world,hull,Vector3(-.6,.5,.5),0,{left=100})==true,'nearby disjoint sphere is clear')
check(C.Clear(world,hull,Vector3(.5,.5,.5),0,{left=0})==nil,'query budget exhausted is unknown, not safe')
box.collisionMask=0
check(C.Clear(world,hull,Vector3(.5,.5,.5),0,{left=100})==true,'rewinding non-collidable pieces are ignored')
box.collisionMask=0xffffffff;box.collisionLayer=2
check(C.Clear(world,hull,Vector3(.5,.5,.5),0,{left=100})==true,'visual self volumes are ignored')
world.volumes={volume(Vector3(3,0,0),90,Vector3(2,1,1),Vector3(1,1,1),function()return true end)}
check(C.Clear(world,hull,Vector3(3.5,.5,-1),0,{left=100})==false,'rotated nonuniform-scale voxel overlaps')

local spec=require('dragon.DragonSpec')
local pivots={};for _,bone in ipairs(spec.BONES)do pivots[bone[1]]=bone[3]end
local rig={size=1,spec=spec,pivots=pivots,bones={},root={worldPosition=Vector3.ZERO}}
local realHull=C.Hull(rig)
check(#realHull==3,'torso uses three authored overlapping spheres')
for _,variant in ipairs({'small','medium','large'})do
    local authored=require('dragon.DragonVariants').Get(variant)
    local _,bones=authored.Expand()
    local piv={};for _,bone in ipairs(bones)do piv[bone.name]=bone.pivot end
    local balls=C.Hull({spec=authored,pivots=piv,size=authored.size or 1})
    for i=1,#balls do
        local connected=false
        for j=1,#balls do
            if i~=j and (balls[i].offset-balls[j].offset):Length()<balls[i].radius+balls[j].radius then connected=true end
        end
        check(connected,'continuous authored torso hull '..variant..' '..i)
    end
end
local before=realHull[1].offset
rig.bones.chest={worldPosition=Vector3(9,9,9)}
check((C.Hull(rig)[1].offset-before):LengthSquared()==0,'animated bones cannot move the hard hull')
local ctrl={rig=rig,loco={pos=Vector3.ZERO,yaw=0,alt=0,altTarget=0,airborne=false,speed=4,yawRate=0,vy=0},state='IDLE'}
function ctrl:GroundHeight(x,z)return self.queryGround and self.queryGround(x,z) or world.floor or 0 end
local terrain={RING_Y=0,Y_BASE=-20,HasGround=function()return not world.void end}
local host={rig=rig,ctrl=ctrl,ride={mode='mounted'},breath={OnHit=function()end}}
world.planes={};world.volumes={};world.floor=0
local adapter=require('ruins.RuinsDragon').New(host,world,{}, {},terrain)
-- A single spherical core makes the adapter's support/altitude cases unambiguous.
adapter.hull={{offset=Vector3(0,2,0),radius=.5}}
local function reset(p,airborne)
    adapter.motionPos=p;adapter.safeMotion=nil;adapter.nextRecovery=1e9
    ctrl.groundRef=p.y;ctrl.motionY=p.y;ctrl.airFloor=0
    local L=ctrl.loco;L.pos=Vector3(p.x,0,p.z);L.alt=airborne and p.y or 0;L.altTarget=L.alt
    L.airborne=airborne;L.yaw=0;L.speed=4;L.yawRate=10;L.vy=0
    adapter:PrepareMotion(ctrl)
end
reset(Vector3.ZERO,false)
world.planes={{n=Vector3(-1,0,0),d=-1}}
ctrl.loco.pos=Vector3(1,0,1);ctrl.loco.yaw=10
adapter:ResolveMotion(ctrl,Vector3.ZERO,0,0,.1)
check(ctrl.loco.pos.x<.5 and close(ctrl.loco.pos.z,1),'adapter preserves wall tangent')
check(close(ctrl.loco.yaw,10),'translation contact does not cancel a safe turn')
world.planes={};reset(Vector3.ZERO,false)
world.void=true;ctrl.loco.pos=Vector3(1,0,0);ctrl.loco.yaw=15
adapter:ResolveMotion(ctrl,Vector3.ZERO,0,0,.1)
check(close(ctrl.loco.pos.x,0) and close(ctrl.loco.yaw,15),'void rejects movement but allows turning away')
world.void=false;world.floor=0;reset(Vector3(0,5,0),true)
world.floor=2;adapter:PrepareMotion(ctrl)
local oldAlt=ctrl.loco.alt
ctrl.loco.pos=Vector3(1,0,0)
adapter:ResolveMotion(ctrl,Vector3.ZERO,0,oldAlt,.1)
check(close(ctrl.motionY,5) and close(ctrl.loco.alt,3),'rising terrain changes altitude reference, not absolute height')
world.floor=0;reset(Vector3(0,5,0),true)
world.planes={{n=Vector3(0,-1,0),d=-8}}
ctrl.loco.pos=Vector3(1,0,0);ctrl.loco.alt=7;ctrl.loco.vy=4
adapter:ResolveMotion(ctrl,Vector3.ZERO,0,5,.1)
check(ctrl.motionY<5.5 and close(ctrl.loco.pos.x,1) and ctrl.loco.vy==0,'ceiling blocks vertical motion, retains horizontal motion')
world.planes={};reset(Vector3.ZERO,false)
adapter.nextRecovery=0
local safe=adapter:Recover(ctrl,Vector3.ZERO,0,.2)
check(adapter.safeMotion~=nil,'clear supported position is recorded')
world.volumes={volume(Vector3(.4,1.5,-.5),0,Vector3(1,1,1),Vector3(1,1,1),function()return true end)}
local escaped,_,didRecover=adapter:Recover(ctrl,Vector3.ZERO,0,.2)
check(didRecover and escaped.x<0 and C.Clear(world,adapter.hull,escaped,0,{left=100})==true,'shallow overlap pushed to verified clear position without input')
world.volumes={volume(Vector3(-.5,1.5,-.5),0,Vector3(1,1,1),Vector3(1,1,1),function()return true end)}
local unchanged,_,unsafe=adapter:Recover(ctrl,Vector3.ZERO,0,.2)
check(not unsafe and unchanged:LengthSquared()==0,'newly blocked safe point is never used')
world.volumes={};reset(Vector3.ZERO,false);adapter.nextRecovery=0
adapter:Recover(ctrl,Vector3.ZERO,0,.2)
world.volumes={volume(Vector3(2.5,1.5,-.5),0,Vector3(1,1,1),Vector3(1,1,1),function()return true end)}
local restored,_,recovered=adapter:Recover(ctrl,Vector3(3,0,0),0,.2)
check(recovered and restored:LengthSquared()==0,'deep overlap restores revalidated clear safe position')
check(ctrl.canLand(3,0)==false,'landing rejects occupied torso space')
world.volumes={};check(ctrl.canLand(3,0)==true,'open supported landing remains available')
-- The real animation application must not move a collision-resolved root.
package.loaded['dragon.DragonPose']={New=function()return {j={},body={0,0,0,0,0,0}}end,Apply=function()end}
package.loaded['dragon.DragonRig']={}
package.loaded['dragon.DragonIK']={}
package.loaded['dragon.DragonGait']={BodyMotion=function()return 0,0,0 end}
local Controller=require('dragon.DragonAnimationController')
local posed=setmetatable({rig={root={},spec={},UpdateMembranes=function()end},layers={},mask='all',
    loco={pos=Vector3(1,0,2),alt=3,airborne=true,yaw=0,pitch=0,bank=0},
    resolveMotion=function()end,motionY=5,gait={feet={}},ikW=0,S=1,H=1},Controller)
function posed:GroundHeight()error('ApplyPose must not query/change resolved ground height')end
posed:ApplyPose(.1)
check(close(posed.rig.root.position.y,5) and close(posed.loco.alt,3),'ApplyPose preserves swept root height')

world.floor=0;world.volumes={};world.planes={};reset(Vector3(0,.1,0),true)
ctrl.state='LAND';ctrl.touchT=1;ctrl.impactS=0;ctrl.loco.airborne=false;ctrl.loco.alt=0
world.planes={{n=Vector3.UP,d=1.55}}
adapter:ResolveMotion(ctrl,Vector3.ZERO,0,.1,.1)
check(ctrl.loco.airborne and ctrl.touchT==nil and ctrl.motionY>.08,'blocked touchdown remains airborne')

-- The same one-second motion at different frame rates must not cross the wall.
world.planes={{n=Vector3(-1,0,0),d=-2}}
for _,fps in ipairs({20,30,60})do
    local position=Vector3.ZERO
    for _=1,fps do position=C.Slide(world,hull,position,0,Vector3(3/fps,0,2/fps))end
    check(position.x<=1.5 and position.x>1.4 and close(position.z,2),'frame-rate independent sliding '..fps)
end
-- Authoring a decorative voxel volume must exclude it from recovery queries.
local Brush=require('ruins.VoxelBrush')
local decorative={GetGrid=function()return {GetSolidCount=function()return 1 end}end,
    SetCollidable=function(self,v)self.collidable=v end,RebuildGeometry=function()end}
local brushWorld={CreateVolume=function()return decorative end}
local brush=Brush.New(brushWorld,{size=1,min={0,0,0},max={1,1,1}})
brush:Finish({visual=true})
check(decorative.collidable==false and decorative.collisionMask==0,'visual-only brush volumes are not recovery obstacles')
print('dragon collision PASS: '..checks..' assertions (analytic query doubles, not Web runtime)')
