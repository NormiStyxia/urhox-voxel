-- Exact two-loop submissions and opposite 3D transforms with engine API doubles.
package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('weapon_mock')
local Orbit=require('combat.WeaponOrbitGrains')
local Wing=require('combat.WingSwordVisual')
local Blades=require('combat.ForgeShowroomBlades')
local Clock=require('combat.TimeCatalystVisual')
local kinds,builds={},0
local create=Mock.CustomGeometry
Mock.CustomGeometry=function(node,...)
    local geom=create(node,...);kinds[node]=geom;return geom
end
package.loaded['dragon.VoxelFX']={Material=function(kind,glow)
    assert(kind=='square' and not glow);builds=builds+1;return Material:new()
end}
rawset(_G,'WING_MATERIAL_MISSING',false)
local cacheMaterial=cache.GetResource
cache.GetResource=function(self,kind,name)
    if name=='model/forge-blades/ClockCatalyst.xml' then return Material:new() end
    return cacheMaterial(self,kind,name)
end
local root=Mock.Node('scene');local mask=0x40000000
local clock=assert(Clock.BeginShowroom(root,mask));while not clock.step() do end
local wing=assert(Blades.Begin(root,nil,mask,false,.7));while not Blades.Step(wing) do end
local hand=assert(Wing.New(root,1.03,nil));assert(not hand.grains.node.enabled);Wing.SetVisible(hand,true)
local function Check(fx,count,period,viewMask,label)
    assert(fx and fx.node.enabled and #fx.rings==2,label..' has two visible loops')
    local initialA,initialB=fx.rings[1].node.rotation,fx.rings[2].node.rotation
    local geomA,geomB=kinds[fx.rings[1].node],kinds[fx.rings[2].node]
    local headA,headB=kinds[fx.rings[1].head],kinds[fx.rings[2].head]
    assert(geomA.viewMask==viewMask and geomB.viewMask==viewMask,label..' mask')
    assert(#geomA.vertices==count*36 and #geomB.vertices==count*36,label..' continuous pixel counts')
    assert(#headA.vertices==36 and #headB.vertices==36,label..' bright heads are cuboids')
    local function dot(a,b)return a.x*b.x+a.y*b.y+a.z*b.z end
    for _,ring in ipairs(fx.rings) do
        assert(math.abs(dot(ring.u,ring.v))<1e-6 and math.abs(dot(ring.u,ring.n))<1e-6 and math.abs(dot(ring.v,ring.n))<1e-6,label..' explicit orthogonal basis')
    end
    assert(fx.rings[1].u.y>0 and fx.rings[2].u.y<0,label..' opposite projected long-axis slopes')
    local firstA,firstB=fx.phaseA,fx.phaseB
    for _=1,period*60 do Orbit.Update(fx,1/60) end
    -- A full period returns both phases to their starting points. Compare
    -- modulo one so floating-point wraparound near 0/1 is accepted.
    local function phaseDistance(a,b)
        local d=math.abs(a-b)%1
        return math.min(d,1-d)
    end
    assert(phaseDistance(fx.phaseA,firstA)<1e-7 and phaseDistance(fx.phaseB,firstB)<1e-7,label..' period closes')
    assert((fx.rings[1].node.rotation*Vector3(1,0,0)-initialA*Vector3(1,0,0)):Length()<.00001,label..' loop A closes')
    assert((fx.rings[2].node.rotation*Vector3(1,0,0)-initialB*Vector3(1,0,0)):Length()<.00001,label..' loop B closes')
    local beforeA=fx.phaseA;local beforeB=fx.phaseB
    local beforeHeadA, beforeHeadB=fx.rings[1].head.position,fx.rings[2].head.position
    Orbit.Update(fx,.1)
    assert(fx.phaseA>beforeA and fx.phaseB<beforeB,label..' loops counter-rotate')
    assert((fx.rings[1].head.position-beforeHeadA):Length()>1e-5 and (fx.rings[2].head.position-beforeHeadB):Length()>1e-5,label..' bright heads flow')
    return geomA,geomB
end
-- Transform through the whole hierarchy, including the charge/fade scale on
-- the equipped catalyst. The mock's LocalToWorld omits ancestor scale.
local function WorldPoint(node,p)
    while node do
        local s=node.scale
        p=node.position+node.rotation*Vector3(s.x*p.x,s.y*p.y,s.z*p.z)
        node=node.parent
    end
    return p
end
local function SampleStreams(visual,viewMask)
    local bounds=visual.geometry.core.boundingBox
    local center=(bounds.min+bounds.max)*.5
    local expected=WorldPoint(visual.pivots.core,center)
    assert(visual.grains.node.parent==visual.pivots.core,'inherits sapphire transform')
    local samples={}
    for _,ring in ipairs(visual.grains.rings) do
        local points={}
        for _,stream in ipairs(ring.streams) do
            local mesh=assert(kinds[stream])
            assert(stream.enabled and mesh.viewMask==viewMask and mesh.commits==1)
            assert(#mesh.vertices==8*36)
            for first=1,#mesh.vertices,36 do
                local sum=Vector3.ZERO
                for j=first,first+35 do sum=sum+mesh.vertices[j].position end
                points[#points+1]=WorldPoint(stream,sum*(1/36))
            end
        end
        local sum=Vector3.ZERO
        for _,point in ipairs(points) do sum=sum+point end
        samples[#samples+1]={centerError=(sum*(1/#points)-expected):Length(),points=points}
    end
    return samples
end
local exhibited=clock.catalyst
local initial=SampleStreams(exhibited,mask)
local maxError=0
local maxHop,minSpacing=0,math.huge
local excursions={{},{}}
for frame=1,120 do
    Orbit.Update(exhibited.grains,8/120)
    local samples=SampleStreams(exhibited,mask)
    for i,sample in ipairs(samples) do
        maxError=math.max(maxError,sample.centerError)
        local ring=exhibited.grains.rings[i]
        local n=ring.node.worldRotation*Vector3.FORWARD
        for j,point in ipairs(sample.points) do
            local p=point-exhibited.pivots.core.worldPosition
            local height=p.x*n.x+p.y*n.y+p.z*n.z
            maxHop=math.max(maxHop,math.abs(height))
            local range=excursions[i][j] or {lo=math.huge,hi=-math.huge}
            range.lo=math.min(range.lo,height);range.hi=math.max(range.hi,height)
            excursions[i][j]=range
            for k=1,j-1 do minSpacing=math.min(minSpacing,(point-sample.points[k]):Length()) end
            local d=(point-initial[i].points[j]):Length()
            if frame==60 then assert(d>.52,'each grain orbits to the far side') end
            if frame==120 then assert(d<1e-7,'each grain closes its own path') end
        end
    end
end
assert(minSpacing>.095,'visible space between particles of the same ring')
for _,ring in ipairs(excursions) do
    for _,range in ipairs(ring) do assert(range.hi-range.lo>.040,'every grain rises and falls') end
end
assert(maxHop>.020 and maxHop<.024,'individual normal excursion should be visible')
-- Exercise the normal hand update and weapon switch with the native particle
-- emitter calls stubbed. Geometry, core spin, hand spring and scale are real Lua.
local function noop() end
package.loaded['dragon.VoxelFX'].WorldMotes=function()
    return {Spawn=noop,Update=noop,Clear=noop}
end
local held=assert(Clock.New(root,Mock.Node('camera')))
while not Clock.Step(held) do end
local ctx={position=Vector3(1,0,-3),hand=Vector3(1.4,1.2,-2.7),yaw=0,active=true}
for frame=1,150 do
    ctx.yaw=(frame*2)%360;ctx.aiming=frame>40;ctx.charge=frame/150;ctx.casting=frame==100
    Clock.Update(held,1/30,ctx)
    for _,sample in ipairs(SampleStreams(held,0xffffffff)) do
        maxError=math.max(maxError,sample.centerError)
    end
end
assert(maxError<1e-6,'both orbit centres follow the moving core')
ctx.active=false
for _=1,45 do Clock.Update(held,1/30,ctx) end
local hiddenPhase=held.grains.phase
Clock.Update(held,.1,ctx)
assert(not held.root.enabled and hiddenPhase==held.grains.phase)
for _,ring in ipairs(held.grains.rings) do
    for _,stream in ipairs(ring.streams) do assert(not stream.enabled) end
end
ctx.active=true;Clock.Update(held,.05,ctx);SampleStreams(held,0xffffffff)
local heldRoot=held.grains.node
Clock.Dispose(held);assert(heldRoot.removed)
print(('PASS catalyst centre max %.3g m; normal excursion %.5f m; minimum spacing %.5f m; 120 showroom + 150 held frames'):format(maxError,maxHop,minSpacing))
local b1,b2=Check(wing.grains,20,6,mask,'showroom wing')
local c1,c2=Check(hand.grains,20,6,0xffffffff,'hand wing')
assert(builds==1,'material shared by all four loop meshes')
Wing.SetVisible(hand,false);assert(not hand.grains.node.enabled and not hand.grains.rings[1].node.enabled)
local a,b,c=clock.catalyst.grains.node,wing.grains.node,hand.grains.node
Clock.Dispose(clock.catalyst);Blades.Dispose(wing);Wing.Dispose(hand)
assert(a.removed and b.removed and c.removed)
print('PASS two opposite tilted loops, continuous pixel meshes, shared material, period, counter-rotation, masks, holster and disposal')
