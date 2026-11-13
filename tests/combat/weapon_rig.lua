package.path="scripts/?.lua;tests/combat/?.lua;"..package.path
local Mock=require("weapon_mock")
local Rig=require("combat.WeaponRig")
local Parts=require("combat.WeaponParts")
local scene=Mock.Node("scene") --[[@as any]] -- intentional engine contract doubles
local world=Mock.World(scene) --[[@as any]]
local nomi=Mock.Nomi(scene) --[[@as any]]
local rig=Rig.New(scene,world,nomi)
assert(rig.active=="sword" and rig.pose=="hidden")
assert(#rig.trails==8 and #rig.images==2 and #rig.bowImages==2 and #rig.particles==6)
assert(world.created==2+#rig.trails+#rig.images+#rig.bowImages+#rig.particles+2,"two weapons, two flash meshes and both silhouette pools")
assert(rig:GetAfterimagePose()==nil,'hidden weapons are not hand snapshots')
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
for _,trail in ipairs(rig.trails) do assert(not trail.node.enabled,'movement outside active is not a swing') end
local samplePool={}
for _,sample in ipairs(rig.samples) do samplePool[sample]=true end
for i=1,32 do nomi.node.position=Vector3(i*.03,0,0);rig:SetCombatVisual(true,nil);rig:Update(1/60) end
for _,trail in ipairs(rig.trails) do assert(trail.node.enabled) end
assert(rig.sampleCount==8 and #rig.samples==8)
for _,sample in ipairs(rig.samples) do assert(samplePool[sample]) end
frames(10)
for _,trail in ipairs(rig.trails) do assert(not trail.node.enabled,"stationary trails must expire") end
rig:SetTrail(false)
nomi.node.position=Vector3(2,0,0);frames(2)
assert(rig.sampleCount==0)
rig:SetTrail(true)
nomi.node.position=Vector3(2.03,0,0);rig:SetCombatVisual(true,nil);frames(1)
nomi.node.position=Vector3(2.15,0,0);rig:SetCombatVisual(true,nil);frames(1)
nomi.node.position=Vector3(200,0,0);rig:SetCombatVisual(true,nil);frames(1)
assert(rig.sampleCount==1,"teleports clear distance samples")
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
assert(rig:Apply(c) and world.rebuilds==initialRebuilds+3 and rig:GetStats().range==46,'bow edit rebuilds weapon plus two bow silhouettes')
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
rig:SetAfterimages(snapshots);rig:SetCombatVisual(true,nil);rig:Update(0)
assert(rig.afterimages==snapshots and #snapshots==3 and #rig.images==2 and #rig.particles==6 and #rig.trails==8)
assert(rig.images[1].node.enabled and rig.images[2].node.enabled)
Mock.VectorNear(rig.images[1].node.worldPosition,snapshots[1].position+snapshots[1].rotation*rig.imageMin)
for _=1,12 do rig:SetAfterimages(snapshots);rig:SetCombatVisual(true,nil);rig:Update(1/60) end
assert(rig.images==imagePool and rig.particles==particlePool and rig.trails==bandPool)
assert(world.writes==beforeWrites and world.rebuilds==beforeBuilds,'animated afterimages must reuse native volumes')
snapshots[1].age=.11;snapshots[2].age=.11
rig:SetAfterimages(snapshots);rig:SetCombatVisual(true,nil);rig:Update(0)
for _,image in ipairs(rig.images) do assert(not image.node.enabled) end
for _,band in ipairs(rig.trails) do assert(not band.node.enabled) end
snapshots[1].age=0;snapshots[2].age=0
rig:SetAfterimages(snapshots);rig:SetCombatVisual(true,nil);rig:Update(0);rig:SetTrail(false)
for _,image in ipairs(rig.images) do assert(not image.node.enabled) end
rig:SetTrail(true);rig:SetAfterimages({});rig:SetCombatVisual(false,nil);rig:Update(.1)
assert(rig.sampleCount==0,'empty animation snapshots do not imply active')
rig:SetAfterimages(nil);frames(2);assert(rig.sampleCount==0,'nil snapshots do not imply active')
local sword=Parts.DefaultWeapon('sword');sword.weapon='sword';sword.parts.blade='blade_broad'
assert(rig:Apply(sword) and world.rebuilds==beforeBuilds+12,'weapon, two silhouettes, eight bands and blade flash resize only on part edits')
for _,volume in ipairs(world.volumes) do assert(volume.collisionLayer==0 and volume.collisionMask==0) end
assert(world.palette[174].r==1 and world.palette[174].g==1 and world.palette[174].b==1)
for _,band in ipairs(rig.trails) do
    local white,accent=false,false
    local grid=band.volume.grid --[[@as any]] -- mock voxel writes
    for _,index in pairs(grid.materials) do white=white or index==174;accent=accent or index==175 end
    assert(white and accent,'one band mesh must contain white core plus accent rim')
    local mat=band.material --[[@as any]]
    assert(mat.technique.passes.base.blend==nil and not mat.technique.passes.shadow,'bands do not stack alpha or cast transient shadows')
    Mock.VectorNear(band.node.scale,Vector3(1,1,1))
end
local function Step(active,charge,dt) rig:SetCombatVisual(active,charge);rig:Update(dt or 1/60) end
local allocated,writesAtFx,buildsAtFx=world.created,world.writes,world.rebuilds
local rawColor,rawVariant=Color,Variant
local colorAllocations,variantAllocations=0,0
rawset(_G,'Color',function(...) colorAllocations=colorAllocations+1;return rawColor(...) end)
rawset(_G,'Variant',function(...) variantAllocations=variantAllocations+1;return rawVariant(...) end)
-- Charge approaches the blade root, not the character centre. Full charge does
-- not auto-flash; the event fires once and cannot be sustained by a held button.
Step(false,.2,0)
local radius={}
for i,particle in ipairs(rig.particles) do
    assert(particle.node.enabled)
    radius[i]=(particle.offset-rig.bladeRoot):Length()
end
Step(false,.8,.01)
for i,particle in ipairs(rig.particles) do assert(particle.node.enabled and (particle.offset-rig.bladeRoot):Length()<radius[i]) end
Step(false,1,0)
for _,particle in ipairs(rig.particles) do assert(not particle.node.enabled) end
assert(not rig.flashes.blade.node.enabled and rig:Flash('full_charge'))
assert(rig.flashes.blade.node.enabled and not rig:Flash('full_charge'))
assert(rig.flashes.blade.node.position.x==rig.bladeFlashX and rig.bladeFlashX>0)
Step(false,1,.079);assert(rig.flashes.blade.node.enabled)
Step(false,1,.001);assert(not rig.flashes.blade.node.enabled and not rig:Flash('full_charge'))
Step(false,nil,0);Step(false,.3,0);assert(rig:Flash('full_charge'),'a new charge may flash once')
Step(false,nil,.08)
assert(rig:Flash('draw') and rig.flashes.socket.node.parent==rig.sockets.hand_right)
assert(not rig:Flash('draw'))
Step(false,nil,.08);assert(not rig.flashes.socket.node.enabled)
assert(rig:Flash('sheath') and rig.flashes.socket.node.parent==rig.sockets.back_sword)
Step(false,nil,.08);assert(not rig.flashes.socket.node.enabled and not rig:Flash('invalid'))
-- A single distance step may emit several strips; no frame-history dependency.
Step(true,nil,0)
nomi.node.position=nomi.node.position+Vector3(.7,0,0);rig:SetAfterimages(snapshots);Step(true,nil,1/30)
assert(rig.sampleCount==8 and rig.trails[8].node.enabled)
assert(rig.images[1].node.enabled and not rig.images[2].node.enabled,'band + one silhouette, never three intentional layers')
Step(false,nil,0);Step(false,nil,.059);assert(rig.trails[1].node.enabled)
Step(false,nil,.001)
for _,band in ipairs(rig.trails) do assert(not band.node.enabled) end
for _,image in ipairs(rig.images) do assert(not image.node.enabled) end
assert(rig.sampleCount==0,'active end + .06s is a hard cutoff even with live snapshots')
-- Flashes, particles, bands and silhouettes use pooled materials/alpha Variants.
assert(world.created==allocated and world.writes==writesAtFx and world.rebuilds==buildsAtFx)
assert(colorAllocations==0 and variantAllocations==0,'FX update must reuse alpha buckets')
rawset(_G,'Color',rawColor);rawset(_G,'Variant',rawVariant)
assert(rig:Flash('draw'));rig:SetTrail(false)
assert(not rig.flashes.socket.node.enabled and not rig:Flash('draw'))
rig:SetTrail(true)
rig:SetPose('back');frames(8)
assert(not rig.flashes.socket.node.enabled,'pose changes alone must not flash')
rig:Dispose();rig:Dispose()
assert(world.created==world.removed and not nomi.castSocket.removed)

local function SlideCase(weapon)
    local root=Mock.Node('slide_test') --[[@as any]]
    local w=Mock.World(root) --[[@as any]]
    local controller=Mock.Nomi(root) --[[@as any]]
    local r=Rig.New(root,w,controller)
    r:SetActive(weapon);r:SetPose('hand');for _=1,8 do r:Update(1/60) end
    controller.nomi.bones.body.rotation=Quaternion(8,25,11)
    controller.nomi.bones.arm_left.rotation=Quaternion(-75,15,5)
    controller.nomi.bones.arm_right.rotation=Quaternion(-85,-8,-6)
    local entry=r.entries[weapon]
    local oldLocal=entry.pivot.position
    r:SetSwing(Vector3(.04,.02,-.03),Vector3(10,20,35))
    local position,rotation=r:GetAfterimagePose()
    assert(position and rotation)
    Mock.VectorNear(entry.pivot.position,oldLocal)
    local oldDirection=entry.pivot.rotation*Vector3.UP
    r:GetAfterimagePose();Mock.VectorNear(entry.pivot.rotation*Vector3.UP,oldDirection)
    r:Update(0)
    Mock.VectorNear(position,entry.pivot.worldPosition)
    Mock.VectorNear(rotation*Vector3.UP,entry.pivot.worldRotation*Vector3.UP)
    Mock.VectorNear(rotation*Vector3.FORWARD,entry.pivot.worldRotation*Vector3.FORWARD)
    local savedPosition=Vector3(position.x,position.y,position.z)
    local savedDirection=rotation*Vector3.FORWARD
    controller.node.position=Vector3(.1,0,.15)
    r:SetSwing(Vector3(-.03,.06,0),Vector3(25,5,-10))
    local currentPosition,currentRotation=r:GetAfterimagePose()
    r:Update(0)
    Mock.VectorNear(currentPosition,entry.pivot.worldPosition)
    Mock.VectorNear(currentRotation*Vector3.UP,entry.pivot.worldRotation*Vector3.UP)
    Mock.VectorNear(position,savedPosition);Mock.VectorNear(rotation*Vector3.FORWARD,savedDirection)
    local shots={
        {clip='dodge_slide',time=.08,age=0,alpha=1,life=.08,position=currentPosition,rotation=currentRotation},
        {clip='dodge_slide',time=.04,age=.04,alpha=.5,life=.08,position=position,rotation=rotation},
        {clip='dodge_slide',time=0,age=.06,alpha=.2,life=.08,position=position,rotation=rotation},
    }
    local created,rebuilds,writes=w.created,w.rebuilds,w.writes
    local pool=weapon=='sword' and r.images or r.bowImages
    local other=weapon=='sword' and r.bowImages or r.images
    local minimum=weapon=='sword' and r.imageMin or r.bowImageMin
    if weapon=='sword' then
        r:SetCombatVisual(true,nil);r:Update(0)
        controller.node.position=controller.node.position+Vector3(.7,0,0)
        r:SetCombatVisual(true,nil);r:Update(.016)
        assert(r.trails[1].node.enabled)
        -- W2's accepted-dodge hook clears the prior attack before the first
        -- .04s slide sample. Its normal per-frame quality gate restores effects.
        r:SetTrail(false);r:SetTrail(true)
        r:SetAfterimages({{clip='sword_attack_1',age=0,position=currentPosition,rotation=currentRotation}})
        r:SetCombatVisual(false,nil);r:Update(.02)
        assert(r.tailLeft==0)
        for _,band in ipairs(r.trails) do assert(not band.node.enabled) end
        for _,image in ipairs(r.images) do assert(not image.node.enabled) end
        assert(r:Flash('draw'))
    end
    r:SetAfterimages(shots);r:SetCombatVisual(true,.5);r:Update(0)
    assert(r.afterimages==shots and #shots==3 and pool[1].node.enabled and pool[2].node.enabled)
    for _,image in ipairs(other) do assert(not image.node.enabled) end
    for _,band in ipairs(r.trails) do assert(not band.node.enabled) end
    for _,particle in ipairs(r.particles) do assert(not particle.node.enabled) end
    for _,flash in pairs(r.flashes) do assert(not flash.node.enabled) end
    assert(not r:Flash('draw') and not r:Flash('full_charge'),'slide is silhouettes only, including between Update calls')
    assert(r.tailLeft==0 and r.sampleCount==0,'slide must cancel sword trail/charge/flash, even if owner flags lag')
    Mock.VectorNear(pool[1].node.worldPosition,currentPosition+currentRotation*minimum)
    local voxels=0
    local imageGrid=pool[1].volume.grid --[[@as any]]
    for _,index in pairs(imageGrid.materials) do voxels=voxels+1;assert(index==175) end
    assert(voxels==#entry.mesh.blueprint.geometry.cells,'silhouette must match the actual sword/bow')
    r:Update(.039);assert(pool[1].node.enabled and pool[2].node.enabled)
    r:Update(.001);assert(pool[1].node.enabled and not pool[2].node.enabled)
    r:Update(.04);assert(not pool[1].node.enabled and not pool[2].node.enabled)
    shots[1].age=.08;shots[1].life=1
    r:SetAfterimages(shots);r:Update(0);assert(not pool[1].node.enabled,'slide lifetime caps at .08 even for a longer input life')
    shots[1].age=0;shots[1].life=.08
    r:SetAfterimages(shots);r:Update(0);r:SetTrail(false)
    for _,image in ipairs(pool) do assert(not image.node.enabled) end
    r:SetTrail(true);r:SetAfterimages({});r:Update(.1)
    for _,image in ipairs(pool) do assert(not image.node.enabled) end
    assert(w.created==created and w.rebuilds==rebuilds and w.writes==writes,'slide cannot allocate or rebuild native visuals')
    for _,volume in ipairs(w.volumes) do assert(volume.collisionLayer==0 and volume.collisionMask==0) end
    r:SetPose('back');for _=1,8 do r:Update(1/60) end
    assert(r:GetAfterimagePose()==nil)
    r:Dispose();assert(r:GetAfterimagePose()==nil and w.created==w.removed)
end
SlideCase('sword');SlideCase('bow')

-- Same physical path and duration at 30/60 FPS: exact translational spacing,
-- small chord approximation tolerance for a rotating blade.
local function Track(fps,rotation)
    local root=Mock.Node('fps_test') --[[@as any]]
    local w=Mock.World(root) --[[@as any]]
    local controller=Mock.Nomi(root) --[[@as any]]
    local r=Rig.New(root,w,controller)
    r:SetPose('hand');for _=1,8 do r:Update(1/60) end
    controller.nomi.bones.arm_right.rotation=Quaternion(-90,0,0)
    r:SetCombatVisual(true,nil);r:Update(0)
    local samples={}
    for _,sample in ipairs(r.samples) do samples[sample]=true end
    local created,rebuilds,writes=w.created,w.rebuilds,w.writes
    for i=1,fps do
        local t=i/fps
        if rotation then r:SetSwing(Vector3.ZERO,Vector3(0,0,t*100))
        else controller.node.position=Vector3(t*1.8,0,0) end
        r:SetCombatVisual(true,nil);r:Update(1/fps)
    end
    assert(r.sampleCount==8)
    local result={}
    for i,sample in ipairs(r.samples) do
        assert(samples[sample],'distance sampling must recycle its fixed array')
        result[i]={root=Vector3(sample.root.x,sample.root.y,sample.root.z),tip=Vector3(sample.tip.x,sample.tip.y,sample.tip.z)}
        local axis=r.trails[i].node.worldRotation*Vector3.UP
        local direction=(sample.tip-sample.root) --[[@as Vector3]]
        local length=direction:Length()
        Mock.VectorNear(axis,Vector3(direction.x/length,direction.y/length,direction.z/length))
    end
    assert(w.created==created and w.rebuilds==rebuilds and w.writes==writes)
    r:SetCombatVisual(false,nil);r:Update(.06)
    for _,band in ipairs(r.trails) do assert(not band.node.enabled) end
    r:Dispose();assert(w.created==w.removed)
    return result
end
local slow,fast=Track(30,false),Track(60,false)
for i=1,8 do
    Mock.VectorNear(slow[i].root,fast[i].root);Mock.VectorNear(slow[i].tip,fast[i].tip)
    if i<8 then Mock.Near((slow[i].tip-slow[i+1].tip):Length(),.09) end
end
slow,fast=Track(30,true),Track(60,true)
for i=1,8 do assert((slow[i].root-fast[i].root):Length()<.003 and (slow[i].tip-fast[i].tip):Length()<.003) end
print("weapon_rig: PASS (30/60 FPS distance trail, root/tip following, .06s cutoff, pooled charge/flash, palette, snapshots, cleanup)")
