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
local a1,a2=Check(clock.catalyst.grains,48,8,mask,'catalyst')
local b1,b2=Check(wing.grains,20,6,mask,'showroom wing')
local c1,c2=Check(hand.grains,20,6,0xffffffff,'hand wing')
assert(builds==1,'material shared by all four loop meshes')
Wing.SetVisible(hand,false);assert(not hand.grains.node.enabled and not hand.grains.rings[1].node.enabled)
local a,b,c=clock.catalyst.grains.node,wing.grains.node,hand.grains.node
Clock.Dispose(clock.catalyst);Blades.Dispose(wing);Wing.Dispose(hand)
assert(a.removed and b.removed and c.removed)
print('PASS two opposite tilted loops, continuous pixel meshes, shared material, period, counter-rotation, masks, holster and disposal')
