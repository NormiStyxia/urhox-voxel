package.path="scripts/?.lua;tests/combat/?.lua;"..package.path
local Mock=require("weapon_mock")
local Rig=require("combat.WeaponRig")
local Parts=require("combat.WeaponParts")
local scene=Mock.Node("scene") --[[@as any]] -- intentional engine contract doubles
local world=Mock.World(scene) --[[@as any]]
local nomi=Mock.Nomi(scene) --[[@as any]]
local rig=Rig.New(scene,world,nomi)
assert(rig.active=="sword" and rig.pose=="hidden" and world.created==20)
for _,volume in ipairs(world.volumes) do assert(volume.collisionLayer==0 and volume.collisionMask==0) end
assert(rig.sockets.hand_right==nomi.castSocket)
Mock.Near(rig.sockets.hand_left.position.x,-nomi.castSocket.position.x)
Mock.Near(rig.sockets.hand_left.position.y,nomi.castSocket.position.y)
assert(rig.sockets.back_sword.parent==nomi.nomi.bones.body and rig.sockets.back_bow.parent==nomi.nomi.bones.body)
local initialWrites,initialRebuilds=world.writes,world.rebuilds
local function frames(n) for _=1,n do rig:Update(1/60) end end
rig:SetPose("back")
for i=1,8 do rig:Update(1/60);Mock.Near(rig.entries.sword.mesh.alpha,i/8) end
assert(rig.entries.sword.pivot.parent==rig.sockets.back_sword)
rig:SetPose("hand")
for i=1,4 do rig:Update(1/60);Mock.Near(rig.entries.sword.mesh.alpha,1-i/4) end
frames(4)
assert(rig.entries.sword.pivot.parent==nomi.castSocket and rig.entries.sword.mesh.alpha==1)
nomi.nomi.bones.arm_right.rotation=Quaternion(-90,0,0)
rig:SetSwing(Vector3(.03,0,.06),Vector3(0,0,0))
rig:Update(1/60)
local hit=rig:GetHit()
Mock.VectorNear(hit.origin,nomi.castSocket:LocalToWorld(Vector3(.03,0,.06)))
Mock.VectorNear(hit.dir,Vector3(0,1,0))
assert(hit.length>0 and hit.radius==.12 and rig:GetStats().attack==10)
for i=1,12 do nomi.node.position=Vector3(i*.03,0,0);rig:Update(1/60) end
for _,trail in ipairs(rig.trails) do assert(trail.node.enabled) end
assert(rig.historyCount==9 and #rig.history==9)
frames(10)
for _,trail in ipairs(rig.trails) do assert(not trail.node.enabled,"stationary trails must expire") end
rig:SetTrail(false)
nomi.node.position=Vector3(2,0,0);frames(2)
assert(rig.historyCount==0)
rig:SetTrail(true)
nomi.node.position=Vector3(2.03,0,0);frames(1)
nomi.node.position=Vector3(2.06,0,0);frames(1)
nomi.node.position=Vector3(200,0,0);frames(1)
assert(rig.historyCount==1,"teleports clear trails")
rig:SetPose("hidden");frames(3)
local fadingAlpha=rig.entries.sword.mesh.alpha
rig:SetPose("hand");frames(1)
assert(rig.entries.sword.mesh.alpha>fadingAlpha and rig.entries.sword.mesh.alpha<1,"fade reversal")
frames(7)
rig:SetActive("bow")
assert(not rig.entries.sword.mesh.node.enabled and rig.pose=="back")
frames(8);rig:SetPose("hand");frames(8)
assert(rig.entries.bow.pivot.parent==rig.sockets.hand_left)
local bowHit=rig:GetHit()
assert(bowHit.radius==nil and bowHit.length==nil and rig:GetStats().draw==.7)
rig:SetPose("back");frames(8)
nomi.nomi.bones.body.rotation=Quaternion(25,0,20);frames(1)
assert(math.abs(rig.lag.x)<=2 and math.abs(rig.lag.z)<=2)
frames(100)
assert(math.abs(rig.lag.x)<1e-5 and math.abs(rig.lag.z)<1e-5)
assert(world.writes==initialWrites and world.rebuilds==initialRebuilds,"combat must never rebuild or edit grids")
local c=Parts.DefaultWeapon("bow");c.weapon="bow";c.colors.accent=6
assert(rig:Apply(c) and world.rebuilds==initialRebuilds)
assert(world.palette[175].r==Parts.ColorPresets[6].rgb[1]/255)
c.parts.limbs="limbs_long"
assert(rig:Apply(c) and world.rebuilds==initialRebuilds+1 and rig:GetStats().range==46)
assert(not rig:SetActive("axe") and not rig:SetPose("fly") and not rig:Apply({}))
rig:SetPose("hidden");frames(8)
assert(not rig.entries.bow.mesh.node.enabled)
rig:SetActive('sword');rig:SetPose('hand');frames(8)
local pivot=rig.entries.sword.pivot
local snapshots={
    {clip='sword_attack_1',handle=1,time=1,age=.02,alpha=.8,position=pivot.worldPosition+Vector3(.1,0,0),rotation=pivot.worldRotation},
    {clip='sword_attack_1',handle=1,time=.96,age=.06,alpha=.4,position=pivot.worldPosition+Vector3(.2,0,0),rotation=pivot.worldRotation},
    {clip='sword_attack_1',handle=1,time=.92,age=.08,alpha=.2,position=pivot.worldPosition,rotation=pivot.worldRotation},
}
local imagePool,particlePool,bandPool=rig.images,rig.particles,rig.trails
local beforeWrites,beforeBuilds=world.writes,world.rebuilds
rig:SetAfterimages(snapshots);rig:Update(0)
assert(rig.afterimages==snapshots and #snapshots==3 and #rig.images==2 and #rig.particles==8 and #rig.trails==8)
assert(rig.images[1].node.enabled and rig.images[2].node.enabled)
Mock.VectorNear(rig.images[1].node.worldPosition,snapshots[1].position+snapshots[1].rotation*rig.imageMin)
for _=1,12 do rig:SetAfterimages(snapshots);rig:Update(1/60) end
assert(rig.images==imagePool and rig.particles==particlePool and rig.trails==bandPool)
assert(world.writes==beforeWrites and world.rebuilds==beforeBuilds,'animated afterimages must reuse native volumes')
snapshots[1].age=.11;snapshots[2].age=.11
rig:SetAfterimages(snapshots);rig:Update(0)
for _,image in ipairs(rig.images) do assert(not image.node.enabled) end
for _,band in ipairs(rig.trails) do assert(not band.node.enabled) end
snapshots[1].age=0;snapshots[2].age=0
rig:SetAfterimages(snapshots);rig:Update(0);rig:SetTrail(false)
for _,image in ipairs(rig.images) do assert(not image.node.enabled) end
rig:SetTrail(true);rig:SetAfterimages({});rig:Update(1/60)
assert(rig.historyCount==0,'empty animation snapshots must not activate fallback')
rig:SetAfterimages(nil);frames(2);assert(rig.historyCount==2)
local sword=Parts.DefaultWeapon('sword');sword.weapon='sword';sword.parts.blade='blade_broad'
assert(rig:Apply(sword) and world.rebuilds==beforeBuilds+3,'one weapon plus two pooled sword silhouettes')
for _,volume in ipairs(world.volumes) do assert(volume.collisionLayer==0 and volume.collisionMask==0) end
rig:Dispose();rig:Dispose()
assert(world.created==world.removed and not nomi.castSocket.removed)
print("weapon_rig: PASS (sockets, 8-frame fades, reversal, swing/world hits, trail lifetime/teleports, sway, no frame rebuilds, cleanup)")
