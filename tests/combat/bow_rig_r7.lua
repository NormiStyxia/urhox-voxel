package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('weapon_mock')
local Rig=require('combat.WeaponRig')
local scene=Mock.Node('scene');local world=Mock.World(scene);local nomi=Mock.Nomi(scene)
local rig=Rig.New(scene,world,nomi)
rig:SetActive('bow');rig:SetPose('hand');rig:Update(.3)
local builds,writes,created=world.rebuilds,world.writes,world.created
local source=rig.bowArrow.volume.grid
assert(#rig.flightArrows==12 and #rig.bowStrings==2)
for _,mesh in ipairs(rig.flightArrows) do
 for key,value in pairs(source.materials) do assert(mesh.volume.grid.materials[key]==value,'flight and nocked arrows share all cells/colors') end
 for key in pairs(mesh.volume.grid.materials) do assert(source.materials[key]) end
end
for _,spec in ipairs({{0,0,0},{.5,0,-.18},{.65,1,-.231},{.9,2,-.316},{1,2,-.35}}) do
 rig:SetBowDraw(spec[1]);rig:Update(0)
 assert(rig.bowStage==spec[2]);Mock.Near(rig:GetBowNockLocal().z,spec[3])
 if spec[1]>.05 then
  Mock.Near(rig.bowArrow.node.position.z-rig.bowArrow.minimum.z,spec[3])
  for _,mesh in ipairs(rig.bowStrings) do
   assert(mesh.node.enabled)
   Mock.VectorNear(mesh.node:LocalToWorld(Vector3(.015,.015,0)),rig:GetBowNock())
  end
 end
end
rig:FlashBowFull();assert(rig.flashLeft==.08 and rig.flashes.socket.node.enabled)
rig:ReleaseBow();assert(not rig.bowArrow.node.enabled and rig.bowStrings[1].node.enabled)
rig:Update(.051);assert(not rig.bowStrings[1].node.enabled)
rig:SetBowDraw(.7);rig:Update(0);rig:CancelBow()
assert(not rig.bowArrow.node.enabled and not rig.bowStrings[1].node.enabled)
rig:SetBowDraw(1);rig:Update(0);rig:SetPose('hidden')
assert(not rig.bowArrow.node.enabled and not rig.bowStrings[1].node.enabled)
local p={index=1,vel=Vector3(0,0,60),pos=Vector3(1,2,3),renderPos=Vector3(1,2,3),embedded=true,age=.02}
rig:DrawArrow(p,true)
local mesh=rig.flightArrows[1]
local tip=Vector3(-mesh.minimum.x,-mesh.minimum.y,mesh.tip-mesh.minimum.z)
Mock.VectorNear(mesh.node:LocalToWorld(tip),p.pos)
assert(mesh.node.rotation.x~=0,'local shake rotates around fixed contact tip')
for i=1,120 do p.age=i/120;rig:DrawArrow(p,true) end
assert(world.created==created and world.rebuilds==builds and world.writes==writes,'all hot bow/arrow visuals reuse native volumes')
rig:DrawArrow(p,false);assert(not mesh.root.enabled)
rig:Dispose()
for _,arrow in ipairs(rig.flightArrows) do assert(arrow.root.removed) end
print('PASS R7 shared full-arrow cells,12 pooled arrows,continuous nock/stages/string endpoints,full cue/cancel,tip-pivot shake,zero hot volume/grid work')

-- Actual layered animation solver: opposite hand reads this frame's left arm.
local S=dofile('tests/combat/core_support.lua')
local A=require('combat.CombatAnim')
local bow={}
function bow:GetBowNockLocal(u)return Vector3(0,.06,u<=.5 and -.36*u or -.18-.34*(u-.5)) end
function bow:GetBowNock(u,grip,rotation)return grip+rotation*self:GetBowNockLocal(u) end
for _,pitch in ipairs({-35,0,35}) do
 local character=S.anim.character()
 -- Native vectors support all arithmetic; normalize the old mock's tiny vector type.
 for _,bone in pairs(character.bones) do bone.position=Vector3(bone.position.x,bone.position.y,bone.position.z) end
 local a=A.New(character,nil,{bowRig=bow})
 a:Play('bow_hold',{fadeIn=0,params={p=0,aimPitch=pitch}})
 for _,u in ipairs({0,.65,.9,1,.2,1}) do
  S.anim.reset(character);a:SetParam('p',u);a:Update(.016);a:Apply()
  local ik=a:GetIKDebug('bow_hold')
  local body=character.bones.body.rotation
  local inverse=Quaternion(body.w,-body.x,-body.y,-body.z)
  local expected=bow:GetBowNock(u,ik.arm_left.applied,inverse*Quaternion(pitch,0,0))
  local error=Vector3(ik.arm_right.applied.x-expected.x,ik.arm_right.applied.y-expected.y,ik.arm_right.applied.z-expected.z):Length()
  assert(error<.03,'same-frame right-hand/nock mismatch '..error..' at '..u..' pitch '..pitch)
 end
end
print('PASS R7 actual left-before-right IK nock coverage at u0/.65/.9/1 and pitch +/-35, <3cm')
