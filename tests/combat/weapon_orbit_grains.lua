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
local function Key(p)
    return ('%d,%d,%d'):format(math.floor(p.x*1e7+.5),math.floor(p.y*1e7+.5),math.floor(p.z*1e7+.5))
end

-- Weld the submitted triangle list by position, then walk its directed edges.
-- A single torus has one connected component, no boundary and Euler number zero.
local function CheckTube(mesh)
    local edges,adjacent={},{}
    local points=#mesh.vertices
    assert(points==40*4*6)
    for first=1,points,3 do
        local ids={}
        for j=1,3 do
            local v=mesh.vertices[first+j-1]
            assert(v.color.r==v.color.g and v.color.g==v.color.b and v.color.r>.9 and v.color.a==1)
            ids[j]=Key(v.position)
        end
        for j=1,3 do
            local a,b=ids[j],ids[j%3+1];assert(a~=b)
            adjacent[a]=adjacent[a] or {};adjacent[a][b]=true
            local key=a<b and a..'/'..b or b..'/'..a
            local e=edges[key] or {n=0,dir=0};edges[key]=e
            e.n=e.n+1;e.dir=e.dir+(a<b and 1 or -1)
        end
    end
    local n,e=0,0
    for _,edge in pairs(edges) do assert(edge.n==2 and edge.dir==0,'open or flipped seam');e=e+1 end
    for _ in pairs(adjacent) do n=n+1 end
    assert(n-e+points/3==0)
    local stack={(next(adjacent))};local seen={};local reached=0
    while #stack>0 do
        local key=table.remove(stack)
        if not seen[key] then
            seen[key]=true;reached=reached+1
            for neighbor in pairs(adjacent[key]) do stack[#stack+1]=neighbor end
        end
    end
    assert(reached==n,'one connected tube per pose')
end

local localCenters={}
local maxError=0
local function CheckActive(visual,viewMask)
    assert(visual.grains.node.parent==visual.pivots.core)
    local bounds=visual.geometry.core.boundingBox
    local core=WorldPoint(visual.pivots.core,(bounds.min+bounds.max)*.5)
    for _,ring in ipairs(visual.grains.rings) do
        for i,node in ipairs(ring.poses) do
            assert(node.enabled==(i==ring.active),'exactly one complete line visible')
            local mesh=kinds[node];assert(mesh.viewMask==viewMask and mesh.commits==1)
            if not localCenters[mesh] then
                local sum=Vector3.ZERO
                for _,vertex in ipairs(mesh.vertices) do sum=sum+vertex.position end
                localCenters[mesh]=sum*(1/#mesh.vertices)
            end
            maxError=math.max(maxError,(WorldPoint(node,localCenters[mesh])-core):Length())
        end
    end
end
local exhibited=clock.catalyst
-- Recover the centre of each square section from its four submitted corners.
local function Stations(ring)
    local verts=kinds[ring.poses[1]].vertices
    local centers={}
    for j=1,#verts,24 do
        local a,b,c,d=verts[j].position,verts[j+6].position,verts[j+12].position,verts[j+18].position
        local width=(a-b):Length()
        assert(width>=.005 and width<=.006,'raster stroke width at the normal camera')
        centers[#centers+1]=(a+b+c+d)*.25
    end
    return centers
end
local one,two=exhibited.grains.rings[1],exhibited.grains.rings[2]
local first,second=Stations(one),Stations(two)
for i,p in ipairs(first) do
    assert((p-second[i]):Length()<1e-7,'both rest circles have the same radius at every station')
end
-- Positive and negative radii differences along screen-space rays distinguish
-- crossing contours from two nested ellipses, in the actual test camera views.
local function RayHit(ring,stations,yaw,pitch,dx,dy)
    local cy,sy,cp,sp=math.cos(yaw),math.sin(yaw),math.cos(pitch),math.sin(pitch)
    local function Project(p)
        local q=WorldPoint(ring.node,p)
        local depth=4.6+.95*(-sy*cp*q.x-sp*q.y+cy*cp*q.z)
        return (cy*q.x+sy*q.z)*4.6/depth,(-sy*sp*q.x+cp*q.y+cy*sp*q.z)*4.6/depth
    end
    local ax,ay=Project(stations[#stations])
    for _,p in ipairs(stations) do
        local bx,by=Project(p)
        local a,b=dx*ay-dy*ax,dx*by-dy*bx
        if (a<0)~=(b<0) then
            local f=a/(a-b)
            local r=dx*(ax+f*(bx-ax))+dy*(ay+f*(by-ay))
            if r>0 then return r end
        end
        ax,ay=bx,by
    end
    error('projected ring must enclose the central ray')
end
for _,view in ipairs({{0,0},{38,14}}) do
    local lo,hi=math.huge,-math.huge
    for ray=0,35 do
        local dx,dy=math.cos(math.rad(10*ray)),math.sin(math.rad(10*ray))
        local yaw,pitch=math.rad(view[1]),math.rad(view[2])
        local a,b=RayHit(one,first,yaw,pitch,dx,dy),RayHit(two,second,yaw,pitch,dx,dy)
        assert(math.min(a,b)>.09,'blue core stays clear')
        lo,hi=math.min(lo,a-b),math.max(hi,a-b)
    end
    assert(lo<-.020 and hi>.020,'both outlines cross with visible separation')
end
for _,ring in ipairs(exhibited.grains.rings) do
    local rest=kinds[ring.poses[1]].vertices
    for i,node in ipairs(ring.poses) do
        local mesh=kinds[node];CheckTube(mesh)
        local changed=0
        for j,v in ipairs(mesh.vertices) do
            local delta=(v.position-rest[j].position):Length();assert(delta<.015)
            if delta>1e-8 then changed=changed+1 end
        end
        if i>1 then assert(changed>0 and changed<#rest/3,'only short arcs change') end
    end
end
-- The sparkle changes its own geometry coverage, independently of tube visibility.
local peakFrames={}
local darkFrames=0
local transitions,heldFrames=0,0
for frame=1,240 do
    local old=exhibited.grains.rings[1].active
    Orbit.Update(exhibited.grains,1/30);CheckActive(exhibited,mask)
    local lit=0
    for _,ring in ipairs(exhibited.grains.rings) do
        for _,star in ipairs(ring.stars) do
            assert(star.node.enabled==(star.size>0))
            local mesh=kinds[star.node]
            assert(mesh.viewMask==mask and mesh.commits==1 and #mesh.vertices==108)
            if star.node.enabled then
                lit=lit+1
                assert(star.node.scale.x==star.size)
                if star.size==1 then peakFrames[star]=true end
            end
        end
    end
    assert(lit<=2,'sparkles have staggered phases')
    if lit==0 then darkFrames=darkFrames+1 end
    if old==exhibited.grains.rings[1].active then heldFrames=heldFrames+1 else transitions=transitions+1 end
end
local peaks=0;for _ in pairs(peakFrames) do peaks=peaks+1 end
assert(peaks==4 and darkFrames>0)
assert(transitions>0 and heldFrames>transitions and exhibited.grains.rings[1].active==1)
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
    CheckActive(held,0xffffffff)
end
assert(maxError<1e-6,'both orbit centres follow the moving core')
ctx.active=false
for _=1,45 do Clock.Update(held,1/30,ctx) end
local hiddenPhase=held.grains.phase
Clock.Update(held,.1,ctx)
assert(not held.root.enabled and hiddenPhase==held.grains.phase)
for _,ring in ipairs(held.grains.rings) do
    for _,node in ipairs(ring.poses) do assert(not node.enabled) end
    for _,star in ipairs(ring.stars) do assert(not star.node.enabled) end
end
ctx.active=true;Clock.Update(held,.05,ctx);CheckActive(held,0xffffffff)
local heldRoot=held.grains.node
Clock.Dispose(held);assert(heldRoot.removed)
print(('PASS six connected closed poses; max centre error %.3g m; %d stepped changes and %d held frames'):format(maxError,transitions,heldFrames))
local b1,b2=Check(wing.grains,20,6,mask,'showroom wing')
local c1,c2=Check(hand.grains,20,6,0xffffffff,'hand wing')
assert(builds==1,'material shared by all four loop meshes')
Wing.SetVisible(hand,false);assert(not hand.grains.node.enabled and not hand.grains.rings[1].node.enabled)
local a,b,c=clock.catalyst.grains.node,wing.grains.node,hand.grains.node
Clock.Dispose(clock.catalyst);Blades.Dispose(wing);Wing.Dispose(hand)
assert(a.removed and b.removed and c.removed)
print('PASS two opposite tilted loops, continuous pixel meshes, shared material, period, counter-rotation, masks, holster and disposal')
