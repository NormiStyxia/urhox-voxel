-- Offline actor-root motion, shared hang targets and hand/back transition contract.
package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('weapon_mock')
local Rig=require('combat.WeaponRig')
local function New(imported)
 local scene=Mock.Node('scene');local c=Mock.Nomi(scene)
 if imported~=false then
  local back=c.nomi.bones.body:CreateChild('BackpackLocator');back.position=Vector3(0,.25,-.10)
  c.nomi.bones.BackpackLocator=back
 end
 local r=Rig.New(scene,Mock.World(scene),c)
 r:SetPose('back');r:Update(.2)
 return r,c
end
local function step(r,c,dt,speed)
 local p=c.node.worldPosition;c.node.worldPosition=p+Vector3(0,0,speed*dt)
 r:Update(dt)
end
local function depth(r)
 local f=(r.backAnchor or r.body).worldRotation*Vector3.FORWARD
 local p=r.hangTarget-r.sockets['back_'..r.active].worldPosition
 return -(p.x*f.x+p.y*f.y+p.z*f.z)
end
for _,weapon in ipairs({'sword','bow'}) do
local settled
for _,hz in ipairs({20,30,60,120,240}) do
 local r,c=New();r:SetActive(weapon);local dt=1/hz
 for _=1,hz do step(r,c,dt,7.2) end
 assert(r.hangClearance>0 and r.hangClearance<.30)
 Mock.Near(depth(r),r.hangClearance)
 if settled then Mock.Near(r.hangClearance,settled,1e-7) else settled=r.hangClearance end
 local before=r.hangClearance
 for _=1,hz/2 do step(r,c,dt,0) end
 Mock.Near(r.hangClearance,before*math.exp(-.5/.30),1e-7)
 for _=1,hz*4 do step(r,c,dt,0) end
 assert(r.hangClearance<1e-6,'rest returns to the existing static hang socket')
 r:Dispose()
end
end
print('PASS hang clearance: 20/30/60/120/240Hz opening and delayed closing agree')
for _,imported in ipairs({true,false}) do
 local r,c=New(imported)
 -- Desired speed/intent and camera motion cannot pretend a blocked actor moved.
 c.actualSpeed,c.speed,c.vel,c.camYaw=10,10,Vector3(0,0,10),180
 for i=1,60 do
  c.node.rotation=Quaternion(0,i*6,0);c.node.position=Vector3(0,i*.02,0);c.camYaw=i*13
  r:Update(1/60)
 end
 Mock.Near(r.hangClearance,0)
 for _=1,60 do step(r,c,1/60,7.2) end
 local before=r.hangClearance;assert(before>0)
 r:Update(0);Mock.Near(r.hangClearance,before)
 c.node.position=Vector3(80,0,-100);r:Update(1/60)
 assert(r.hangClearance==0,'teleport cannot become running speed or keep old spacing')
 Mock.VectorNear(r.hangPosition,r.hangTarget)
 r:Dispose()
end
print('PASS hang input isolation: blocked intent, pure turn, camera, vertical jump, pause, teleport; imported and legacy rigs')
local r,c=New()
for _=1,90 do step(r,c,1/60,7.2) end
local before=r.hangClearance
r:SetActive('bow');step(r,c,1/60,7.2)
assert(r.hangClearance>=before-1e-7,'weapon swap retains the shared motion history')
for _=1,60 do step(r,c,1/60,7.2) end
Mock.VectorNear(r.entries.bow.pivot.worldPosition,r.hangPosition)
r:SetPose('hand')
for _=1,60 do step(r,c,1/60,7.2) end
assert(r.visualState=='hand')
Mock.VectorNear(r.entries.bow.pivot.position,r.swingOffset)
local hand=r.sockets.hand_left
Mock.VectorNear(r.entries.bow.pivot.worldPosition,hand:LocalToWorld(r.swingOffset))
r:SetPose('back');step(r,c,.18,7.2)
assert(r.visualState=='hang')
Mock.VectorNear(r.entries.bow.pivot.worldPosition,r.hangPosition)
-- Holo reform/arrival also consumes the shared adjusted back target.
r.visualState='stow';r.transition={holo=true,split=0,arrived=false}
r:AdvanceHolo(r.entries.bow,r.transition,1)
Mock.VectorNear(r.entries.bow.pivot.worldPosition,r.hangPosition)
for i=1,60 do
 c.node.rotation=Quaternion(0,i*3,0);step(r,c,1/60,7.2)
 assert((r.hangPosition-r.hangTarget):Length()<=.0120001,'turn sway stays within 12mm')
 Mock.Near(depth(r),r.hangClearance)
end
r:Dispose()
print('PASS hang target ownership: swap, hand held position, stow arrival, holo reform and moving turn')
-- Native Vector3 table fields are returned by value. Reads must not mutate the
-- persistent sampler/target/spring unless the helper result is assigned back.
do
 local rig,controller=New()
 local storage={};for k,v in pairs(rig)do storage[k]=v end
 for k in pairs(storage)do rawset(rig,k,nil)end
 local vectors={hangPreviousRoot=true,hangPosition=true,hangTarget=true,hangVelocity=true,hangForward=true}
 setmetatable(rig,{__index=function(_,key)
  local value=storage[key]
  if vectors[key]and value then return Vector3(value.x,value.y,value.z)end
  if value~=nil then return value end
  return Rig[key]
 end,__newindex=function(_,key,value)
  storage[key]=vectors[key]and Vector3(value.x,value.y,value.z)or value
 end})
 for i=1,60 do controller.node.position=Vector3(0,0,i*.12);rig:Update(1/60)end
 assert(rig.hangPreviousRoot.z>7 and rig.hangClearance>.19)
 Mock.Near(depth(rig),rig.hangClearance)
 local before=rig.hangClearance
 for _=1,30 do rig:Update(1/60)end
 Mock.Near(rig.hangClearance,before*math.exp(-.5/.30),1e-7)
 rig:Dispose()
end
print('PASS native Vector3 value semantics: root sampling, target offset and decay write back correctly')
