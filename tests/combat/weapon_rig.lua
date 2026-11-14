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
assert(world.created==2+#rig.trails+#rig.images+#rig.bowImages+#rig.particles+2+12+4,"weapons/FX plus twelve reveal slices, three bow shapes and arrow")
assert(rig:GetAfterimagePose()==nil,'hidden weapons are not hand snapshots')
for _,volume in ipairs(world.volumes) do assert(volume.collisionLayer==0 and volume.collisionMask==0) end
assert(rig.sockets.hand_right==nomi.castSocket)
assert(rig.sockets.hand_right==nomi.nomi:HandSocket('right') and rig.sockets.hand_left==nomi.nomi:HandSocket('left'))
Mock.Near(rig.sockets.hand_left.position.x,-nomi.castSocket.position.x)
Mock.Near(rig.sockets.hand_left.position.y,nomi.castSocket.position.y)
assert(rig.sockets.back_sword.parent==nomi.nomi.bones.body and rig.sockets.back_bow.parent==nomi.nomi.bones.body)
local initialWrites,initialRebuilds=world.writes,world.rebuilds
local function frames(n) for _=1,n do rig:Update(1/60) end end
rig:SetPose("back")
for i=1,18 do rig:Update(1/60);Mock.Near(rig.entries.sword.mesh.alpha,math.floor(i/3)/6) end
assert(rig.visualState=='hang')
assert(rig.entries.sword.pivot.parent==rig.sockets.back_sword)
rig:SetPose("hand")
frames(8)
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
rig:SetPose("hand");frames(8)
assert(rig.entries.sword.mesh.alpha==1 and rig.visualState=='hand',"interrupted dissolve flies back to hand")
rig:SetActive("bow")
assert(not rig.entries.sword.mesh.node.enabled and rig.pose=="back")
frames(18);rig:SetPose("hand");frames(8)
assert(rig.entries.bow.pivot.parent==rig.sockets.hand_left)
local bowHit=rig:GetHit()
assert(bowHit.radius==nil and bowHit.length==nil and rig:GetStats().draw==.7)
rig:SetPose("back");frames(11)
nomi.nomi.bones.body.rotation=Quaternion(25,0,20);frames(1)
assert((rig.hangPosition-rig.hangTarget):Length()<=.1200001)
frames(100)
assert((rig.hangPosition-rig.hangTarget):Length()<.03)
assert(world.writes==initialWrites and world.rebuilds==initialRebuilds,"combat must never rebuild or edit grids")
local c=Parts.DefaultWeapon("bow");c.weapon="bow";c.colors.accent=6
assert(rig:Apply(c) and world.rebuilds==initialRebuilds)
assert(world.palette[175].r==Parts.ColorPresets[6].rgb[1]/255)
c.parts.limbs="limbs_long"
assert(rig:Apply(c) and world.rebuilds==initialRebuilds+13 and rig:GetStats().range==46,'bow edit refreshes fixed visual pools')
assert(not rig:SetActive("axe") and not rig:SetPose("fly") and not rig:Apply({}))
rig:SetPose("hidden");frames(18)
assert(not rig.entries.bow.mesh.node.enabled)
rig:SetActive('sword');rig:SetPose('hand');frames(36)
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
assert(rig:Apply(sword) and world.rebuilds==beforeBuilds+18,'weapon, silhouettes, bands, blade flash and six reveal slices resize on edits')
for _,volume in ipairs(world.volumes) do assert(volume.collisionLayer==0 and volume.collisionMask==0) end
assert(world.palette[174].r==1 and world.palette[174].g==1 and world.palette[174].b==1)
for _,band in ipairs(rig.trails) do
    local white,accent=false,false
    local grid=band.volume.grid --[[@as any]] -- mock voxel writes
    for _,index in pairs(grid.materials) do white=white or index==174;accent=accent or index==175 end
    assert(white and accent,'one band mesh must contain white core plus accent rim')
    local mat=band.material --[[@as any]]
    assert(mat.technique.passes.base.blend==nil and not mat.technique.passes.shadow,'bands do not stack alpha or cast transient shadows')
    Mock.VectorNear(band.node.scale,Vector3(1,1.25,1))
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
rig:SetPose('back');frames(11)
assert(rig.flashes.socket.node.enabled,'stow arrival flashes once')
frames(6);assert(not rig.flashes.socket.node.enabled)
rig:Dispose();rig:Dispose()
assert(world.created==world.removed and not nomi.castSocket.removed and not rig.sockets.hand_left.removed)

local function SlideCase(weapon)
    local root=Mock.Node('slide_test') --[[@as any]]
    local w=Mock.World(root) --[[@as any]]
    local controller=Mock.Nomi(root) --[[@as any]]
    local r=Rig.New(root,w,controller)
    r:SetActive(weapon);r:SetPose('hand');for _=1,30 do r:Update(1/60) end
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
    r:SetPose('hand');for _=1,30 do r:Update(1/60) end
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
-- §20: timed reveal/flight/stow/dissolve, shared FX budget, world-space bow
-- orientation, fixed visual sword scaling with unchanged gameplay capsule.
local function LivelyCase(fps,weapon)
    local root=Mock.Node('lively') --[[@as any]]
    local w=Mock.World(root) --[[@as any]]
    local controller=Mock.Nomi(root) --[[@as any]]
    local r=Rig.New(root,w,controller)
    r:SetActive(weapon)
    local entry=r.entries[weapon]
    local writes,rebuilds,created=w.writes,w.rebuilds,w.created
    local makeColor,makeVariant=Color,Variant
    local colors,variants=0,0
    rawset(_G,'Color',function(...) colors=colors+1;return makeColor(...) end)
    rawset(_G,'Variant',function(...) variants=variants+1;return makeVariant(...) end)
    local function advance(seconds) for _=1,math.ceil(seconds*fps) do r:Update(1/fps) end end
    local function count(pool) local n=0;for _,v in ipairs(pool) do if v.node.enabled then n=n+1 end end;return n end
    r:SetPose('back')
    assert(r.visualState=='materialize' and r:PopEvents()[1]=='materialize')
    assert(#r:PopEvents()==0,'event queue drains once')
    local previous=0
    for frame=1,math.ceil(.30*fps) do
        r:Update(1/fps)
        if r.visualState=='materialize' then
            local visible=count(r.layers[weapon])
            assert(visible>=previous and visible<=6 and count(r.particles)<=8)
            for i,layer in ipairs(r.layers[weapon]) do assert(layer.node.enabled==(i<=visible),'reveal must fill bottom first') end
            previous=visible
        end
    end
    assert(r.visualState=='hang' and entry.mesh.node.enabled and r:PopEvents()[1]=='materialized')
    assert(r.flashes.socket.node.enabled and r.flashLeft==.08)
    local socket=r.sockets['back_'..weapon]
    Mock.Near(socket.worldPosition.y,1.05);Mock.Near(socket.worldPosition.z,-.30)
    if weapon=='sword' then
        local up=socket.worldRotation*Vector3.UP;assert(up.x<0 and up.y>0,'sword tip up-left')
    else
        local up=socket.worldRotation*Vector3.UP
        local outward=socket.worldRotation*Vector3.FORWARD
        assert(math.abs(up.x)>.99 and outward.z<-.99,'back bow horizontal, convex away from body')
    end
    local minY,maxY=math.huge,-math.huge
    for _=1,fps*3 do
        r:Update(1/fps)
        minY=math.min(minY,r.hangTarget.y);maxY=math.max(maxY,r.hangTarget.y)
        assert((r.hangPosition-r.hangTarget):Length()<=.1200001)
    end
    assert(maxY-minY>.039 and maxY-minY<=.040001,'0.6Hz target float +/-2cm')
    controller.node.position=Vector3(.6,0,.2);controller.nomi.bones.body.rotation=Quaternion(0,80,0)
    r:Update(1/fps)
    assert((r.hangPosition-r.hangTarget):Length()<=.1200001 and (r.hangPosition-r.hangTarget):Length()>.001,'spring lags but clamps at12cm')
    advance(.5)
    controller.nomi.bones.body.rotation=Quaternion()
    controller.nomi.bones.arm_left.rotation=Quaternion(-90,0,0)
    controller.nomi.bones.arm_right.rotation=Quaternion(-90,0,0)
    r:SetPose('hand');assert(r.visualState=='fly_to_hand' and r:GetAfterimagePose()==nil)
    local from=entry.pivot.worldPosition
    r:Update(.06)
    assert(r.visualState=='fly_to_hand' and (entry.pivot.worldPosition-from):Length()>.02)
    assert(count(r.trails)<=4 and count(r.images)==0 and count(r.bowImages)==0)
    r:Update(.06)
    assert(r.visualState=='hand' and r:PopEvents()[1]=='blade_draw')
    assert(r.flashes.socket.node.enabled and r.flashLeft==.08)
    advance(.1)
    local beforeHit=r:GetHit()
    if weapon=='bow' then
        Mock.VectorNear(entry.pivot.worldRotation*Vector3.UP,Vector3.UP)
        Mock.VectorNear(beforeHit.dir,Vector3.FORWARD)
        local zero=entry.pivot:LocalToWorld(Vector3.ZERO)
        local string=entry.pivot:LocalToWorld(Vector3(0,0,-.06))
        local convex=entry.pivot:LocalToWorld(Vector3(0,.15,.06))
        assert(string.z<zero.z and convex.z>zero.z,'hand basis must preserve -Z string / +Z convex')
        for _,p in ipairs({0,.05,.1,.5,1,.5,0}) do
            r:SetBowDraw(p);r:Update(0)
            assert(r.bowArrow.node.enabled==(p>.05))
            assert(count(r.bowDrawMeshes)==(p>.05 and 1 or 0))
            assert(entry.mesh.node.enabled==(p<=.05))
            if p>.05 then
                local pose=r.bowDrawMeshes[r.bowStage+1]
                assert(pose.node.enabled and r.bowArrow.node.position.x>0)
                Mock.Near(r.bowArrow.node.position.z-r.bowArrow.minimum.z,pose.stringZ)
            end
        end
        r:SetBowDraw(0/0);assert(r.bowDraw==0)
    else
        Mock.VectorNear(entry.pivot.scale,Vector3(1,1,1))
        Mock.VectorNear(entry.mesh.node.scale,Vector3(1.3,1.25,1))
        Mock.Near(beforeHit.length,entry.mesh.blueprint.hit.length)
        Mock.Near(r.bladeTip.y,beforeHit.length*1.25)
        for _,band in ipairs(r.trails) do
            local min,max=math.huge,-math.huge
            local grid=band.volume.grid --[[@as any]] -- inspect offline voxel writes
            for key in pairs(grid.solid) do
                local x=tonumber(key:match('^(%d+):'));min=math.min(min,x);max=math.max(max,x)
            end
            Mock.Near((max-min+1)*.03,.15)
        end
    end
    r:SetPose('back');assert(r.visualState=='stow')
    r:Update(.18)
    assert(r.visualState=='hang' and r.recoil==.12 and r:PopEvents()[1]=='blade_sheath')
    r:Update(.06)
    Mock.Near((entry.pivot.worldPosition-r.hangPosition):Length(),.02)
    advance(.10)
    r:SetPose('hidden');assert(r.visualState=='dissolve')
    r:Update(.10)
    assert(count(r.layers[weapon])==4)
    local radius=(r.particles[1].node.worldPosition-entry.pivot.worldPosition):Length()
    r:Update(.10)
    assert(count(r.layers[weapon])==2 and (r.particles[1].node.worldPosition-entry.pivot.worldPosition):Length()>radius)
    r:Update(.10)
    assert(r.visualState=='hidden' and count(r.layers[weapon])==0 and not entry.mesh.node.enabled and count(r.particles)==0)
    assert(r:PopEvents()[1]=='dissolved')
    -- Interrupt a flight without teleporting to the back socket.
    r:SetPose('hand');assert(r.motion.duration==.08);r:Update(.04)
    local mid=entry.pivot.worldPosition
    r:SetAfterimages({{clip='dodge_slide',age=0,life=.08,position=mid,rotation=entry.pivot.worldRotation}})
    r:Update(0)
    assert(count(r.trails)==0 and count(r.particles)==0,'flight interrupted by slide cannot make knife light or grains')
    r:SetAfterimages(nil)
    r:SetPose('hidden');r:Update(0)
    Mock.VectorNear(entry.pivot.worldPosition,mid)
    r:SetPose('hand');r:Update(.12);assert(r.visualState=='hand')
    -- Even an earlier hit_on (shortened combo / low FPS event catch-up) cannot
    -- run AfterPose against a flying grip. It settles before the owner's sweep.
    r:SetPose('back');r:Update(.18);r:SetPose('hand');r:Update(.02)
    assert(r.visualState=='fly_to_hand')
    r:SetCombatVisual(true,nil);r:Update(0)
    assert(r.visualState=='hand' and r:GetAfterimagePose()~=nil)
    r:SetCombatVisual(false,nil)
    r:SetPose('hidden');r:Update(.30)
    r:SetPose('back');r:Update(.10);assert(count(r.layers[weapon])==2)
    r:SetPose('hidden');r:Update(0);assert(count(r.layers[weapon])==2,'reversing partial reveal must not pop all six layers')
    r:SetPose('back');r:Update(0);assert(count(r.layers[weapon])==2,'reversing dissolve preserves visible layers')
    assert(w.created==created and w.rebuilds==rebuilds and w.writes==writes,'all motion/draw states reuse their pools')
    assert(colors==0 and variants==0,'new motion/draw path must reuse color/alpha buckets')
    rawset(_G,'Color',makeColor);rawset(_G,'Variant',makeVariant)
    for _,volume in ipairs(w.volumes) do assert(volume.collisionLayer==0 and volume.collisionMask==0) end
    r:Dispose();r:Dispose();assert(w.created==w.removed)
end
for _,fps in ipairs({30,60}) do LivelyCase(fps,'sword');LivelyCase(fps,'bow') end

-- Shared palm migration: compare against the pre-migration arm-local formula
-- at varied root/body/arm poses. Zero-elbow chain must give the same values.
local function SharedPalmCase(elbows)
    local root=Mock.Node('shared_palms') --[[@as any]]
    local w=Mock.World(root) --[[@as any]]
    local controller=Mock.Nomi(root,elbows) --[[@as any]]
    local character=controller.nomi
    local right,left=character:HandSocket('right'),character:HandSocket('left')
    assert(character:HandSocket('right')==right and character:HandSocket('left')==left)
    local rightParent,leftParent=right.parent,left.parent
    local rightPosition=Vector3(right.position.x,right.position.y,right.position.z)
    local leftPosition=Vector3(left.position.x,left.position.y,left.position.z)
    local rightRotation,leftRotation=right.rotation,left.rotation
    local foreignRight,foreignLeft=right:CreateChild('other_owner'),left:CreateChild('other_owner')
    local legacyRight=controller.castSocket
    local legacyLeft=character.bones.arm_left:CreateChild('legacy_left_reference')
    legacyLeft.position=Vector3(-legacyRight.position.x,legacyRight.position.y,legacyRight.position.z)
    local accessor=character.HandSocket
    local calls={}
    character.HandSocket=function(self,side) calls[#calls+1]=side;return accessor(self,side) end
    local r=Rig.New(root,w,controller)
    assert(#calls==2 and calls[1]=='right' and calls[2]=='left')
    assert(r.sockets.hand_right==right and r.sockets.hand_left==left)
    if elbows then
        assert(right.parent==character.bones.forearm_right and left.parent==character.bones.forearm_left)
        assert(right~=controller.castSocket,'Rig must not keep a stale controller shoulder socket')
    else assert(right.parent==character.bones.arm_right and left.parent==character.bones.arm_left) end
    local offset,euler=Vector3(.03,-.02,.04),Vector3(11,-17,28)
    local function Compare(weapon,source)
        r:SetSwing(offset,euler)
        local position,rotation=r:GetAfterimagePose()
        local expectedPosition=source:LocalToWorld(offset)
        local expectedRotation=source.worldRotation*Quaternion(90,0,0)*Quaternion(euler.x,euler.y,euler.z)
        Mock.VectorNear(position,expectedPosition)
        Mock.VectorNear(rotation*Vector3.UP,expectedRotation*Vector3.UP)
        Mock.VectorNear(rotation*Vector3.FORWARD,expectedRotation*Vector3.FORWARD)
        r:Update(0)
        local hit=r:GetHit();local bp=r.entries[weapon].mesh.blueprint
        local h=bp.hit
        Mock.VectorNear(hit.origin,expectedPosition+expectedRotation*Vector3(h.origin[1],h.origin[2],h.origin[3]))
        Mock.VectorNear(hit.dir,expectedRotation*Vector3(h.dir[1],h.dir[2],h.dir[3]))
        assert(hit.length==h.length and hit.radius==h.radius)
    end
    for _,weapon in ipairs({'sword','bow'}) do
        r:SetActive(weapon);r:SetPose('hand');r:Update(.12)
        for i=1,5 do
            controller.node.position=Vector3(i*.3,-i*.04,i*.1)
            controller.node.rotation=Quaternion(0,i*37,0)
            character.bones.body.rotation=Quaternion(i*3,-i*7,i*2)
            character.bones.arm_right.rotation=Quaternion(-90+i*6,i*5,-i*4)
            character.bones.arm_left.rotation=Quaternion(-90-i*5,-i*3,i*2)
            Compare(weapon,weapon=='sword' and legacyRight or legacyLeft)
        end
    end
    if elbows then
        character.bones.forearm_right.rotation=Quaternion(-65,9,3)
        character.bones.forearm_left.rotation=Quaternion(-90,-7,4)
        for _,weapon in ipairs({'sword','bow'}) do
            r:SetActive(weapon);r:SetPose('hand');r:Update(.12)
            Compare(weapon,weapon=='sword' and right or left)
        end
    end
    assert(#calls==2,'shared socket references are stable; no repeated creation in Update')
    local function Preserved()
        assert(not right.removed and not left.removed and right.parent==rightParent and left.parent==leftParent)
        Mock.VectorNear(right.position,rightPosition);Mock.VectorNear(left.position,leftPosition)
        Mock.VectorNear(right.rotation*Vector3.UP,rightRotation*Vector3.UP)
        Mock.VectorNear(left.rotation*Vector3.UP,leftRotation*Vector3.UP)
        assert(not foreignRight.removed and not foreignLeft.removed)
    end
    Preserved();r:Dispose();r:Dispose();Preserved()
    assert(w.created==w.removed)
    for _,entry in pairs(r.entries) do assert(entry.pivot.removed) end
    for _,socket in ipairs({right,left}) do
        for _,child in ipairs(socket.children) do assert(child.removed or child.name=='other_owner','weapon child leaked on shared palm') end
    end
    local recreated=Rig.New(root,w,controller)
    assert(recreated.sockets.hand_right==right and recreated.sockets.hand_left==left)
    recreated:SetPose('hand');recreated:Update(.12);recreated:Dispose();Preserved()
    assert(w.created==w.removed and require('game.BlockCharacter').USE_ELBOW_DATA==false)
    legacyLeft:Remove()
end
SharedPalmCase(false);SharedPalmCase(true)
print('weapon_rig shared palms: PASS (legacy and zero-elbow hit/snapshot equality, bent forearm routing, owned-child-only idempotent cleanup)')
print("weapon_rig: PASS (bow axes/draw/nock, timed reveal/flight/stow/dissolve, event drain, spring/float, visual-only sword scale, pooled FX)")
