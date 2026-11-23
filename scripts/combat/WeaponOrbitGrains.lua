local M = {}
local material
local profiles = {
    catalyst = {count=16, period=8, y=0, z=0},
    wing = {count=20, period=6, radius=.083, minor=.44, width=.0042,
        depth=.0032, y=.198, z=-.125, aSlope=.32, bSlope=-.32,
        aTilt=.28, bTilt=-.28},
}
local corners = {{-1,-1,-1},{1,-1,-1},{1,1,-1},{-1,1,-1},
                 {-1,-1,1},{1,-1,1},{1,1,1},{-1,1,1}}
local faces = {{1,4,3,2},{5,6,7,8},{1,5,8,4},{2,3,7,6},{4,8,7,3},{1,2,6,5}}
local order = {1,2,3,1,3,4}

local function Cross(a,b)
    return Vector3(a.y*b.z-a.z*b.y,
        a.z*b.x-a.x*b.z,
        a.x*b.y-a.y*b.x)
end

local function Unit(v)
    return v:Normalized()
end

local function Basis(p,ring)
    local slope=ring==1 and p.aSlope or p.bSlope
    local tilt=ring==1 and p.aTilt or p.bTilt
    local c,s=math.cos(slope),math.sin(slope)
    local u=Vector3(c,s,0)
    local w=Vector3(-s,c,0)
    local n=Unit(w*tilt+Vector3(0,0,1))
    local v=Unit(Cross(n,u))
    return u,v,n
end

local function AddCuboid(g,center,halfT,halfR,halfD,color)
    local uv=Vector2(.20,.20)
    for k,face in ipairs(faces) do
        local tone=.84+.15*(k%3)/2
        local c=Color(color[1]*tone,color[2]*tone,color[3]*tone,1)
        for _,index in ipairs(order) do
            local q=corners[face[index]]
            g:DefineVertex(center+Vector3(q[1]*halfT,q[2]*halfR,q[3]*halfD))
            g:DefineColor(c);g:DefineTexCoord(uv)
        end
    end
end

local function DefineCuboid(g,halfT,halfR,halfD,color)
    g:BeginGeometry(0,TRIANGLE_LIST)
    AddCuboid(g,Vector3.ZERO,halfT,halfR,halfD,color)
    g:Commit()
    assert(g:SetMaterial(0,material)~=false,'grain material binding failed')
end

local function BuildLoop(g,p,ring)
    local u,v,n=Basis(p,ring)
    local phase=ring==1 and 0 or .5
    local tangentHalf=p.radius*math.pi/p.count*.70
    local radialHalf=p.width
    local depthHalf=p.depth
    g:BeginGeometry(0,TRIANGLE_LIST)
    for i=0,p.count-1 do
        local a=2*math.pi*(i+.17*math.sin(i*2.3))/p.count
        local ca,sa=math.cos(a),math.sin(a)
        local radial=u*(ca*p.radius)+v*(sa*p.radius*p.minor)
        local center=radial+n*(p.depth*math.sin(2*a+ring*.9))
        local tangent=Unit(u*(-sa)+v*(ca*p.minor))
        local side=Unit(Cross(n,tangent))
        local tint
        if (i+ring*3)%13==0 then
            tint={.86,.95,1.0}
        else
            tint={.53+.09*math.cos(i+ring),.74,.93}
        end
        for k,face in ipairs(faces) do
            local tone=.84+.15*(k%3)/2
            local c=Color(tint[1]*tone,tint[2]*tone,tint[3]*tone,1)
            for _,index in ipairs(order) do
                local q=corners[face[index]]
                local point=center+tangent*(q[1]*tangentHalf)+side*(q[2]*radialHalf)+n*(q[3]*depthHalf)
                g:DefineVertex(point);g:DefineColor(c);g:DefineTexCoord(Vector2(.20,.20))
            end
        end
    end
    g:Commit()
    assert(g:SetMaterial(0,material)~=false,'grain material binding failed')
    return {u=u,v=v,n=n,phase=phase,tangentHalf=tangentHalf,
        radialHalf=radialHalf,depthHalf=depthHalf,body=g.node,profile=p}
end

local function WrapPhase(value)
    local wrapped=value%1
    return wrapped>=.999999999 and 0 or wrapped
end

local function UpdateHead(ring,p)
    local a=2*math.pi*(ring.phase+.17*math.sin(2.3*ring.phase*p.count))
    local ca,sa=math.cos(a),math.sin(a)
    local radial=ring.u*(ca*p.radius)+ring.v*(sa*p.radius*p.minor)
    local center=radial+ring.n*(p.depth*math.sin(2*a+ring.index*.9))
    local tangent=Unit(ring.u*(-sa)+ring.v*(ca*p.minor))
    local side=Unit(Cross(ring.n,tangent))
    ring.head.position=center
    ring.head.rotation:FromAxes(tangent,side,ring.n)
end

-- In a circle's own XY plane, a grain at angle theta rises by
-- radius * sin(tilt) * sin(theta + 6 * orbitAngle). Adjacent batches have
-- opposite tilt, so neighbours hop out of phase. Antipodal pairs balance.
local function AnimateCircle(ring,phase)
    local wave=2160*phase
    local travel=Quaternion(0,0,360*phase-wave)
    local cycle=Quaternion(0,0,wave)
    for i,node in ipairs(ring.streams) do
        node.rotation=travel*ring.tilts[i]*cycle
    end
end

local function GrainGeometry(node,mask)
    local g=node:CreateComponent('CustomGeometry')
    g.castShadows=false;g.viewMask=mask;g.lightMask=mask;g.zoneMask=mask
    return g
end

local function BuildCircle(loop,p,index,mask)
    local ring={node=loop,streams={},tilts={Quaternion(4.5,0,0),Quaternion(-4.5,0,0)}}
    local radius=index==1 and .264 or .290
    local pitch=index==1 and 74 or -69
    local roll=index==1 and 12 or -17
    loop.rotation=Quaternion(0,0,roll)*Quaternion(pitch,0,0)
    for parity=0,1 do
        local stream=loop:CreateChild('catalyst_grain_stream_'..parity)
        stream.temporary=true;stream.enabled=false
        local g=GrainGeometry(stream,mask)
        g:BeginGeometry(0,TRIANGLE_LIST)
        for i=parity,p.count-1,2 do
            local angle=2*math.pi*i/p.count
            local point=Vector3(radius*math.cos(angle),radius*math.sin(angle),0)
            local h=.0086+.0009*math.cos(angle*3)
            local tint=i==index*3 and {.98,.86,.58} or {.65+.08*math.cos(angle*3),.84,.98}
            AddCuboid(g,point,h,h,h,tint)
        end
        g:Commit()
        assert(g:SetMaterial(0,material)~=false,'grain material binding failed')
        ring.streams[parity+1]=stream
    end
    AnimateCircle(ring,index==1 and 0 or .5)
    return ring
end

function M.New(parent,kind,mask)
    local p=profiles[kind]
    if not p then return nil,'unknown orbit kind '..tostring(kind) end
    local fx={phase=0,phaseA=0,phaseB=.5,period=p.period,rings={},count=p.count}
    local ok,err=pcall(function()
        material=material or require('dragon.VoxelFX').Material('square',false)
        fx.node=parent:CreateChild(kind..'_orbit_grains')
        fx.node.temporary=true
        fx.node.position=Vector3(0,p.y,p.z)
        fx.node.enabled=false
        for ringIndex=1,2 do
            local loop=fx.node:CreateChild(kind..'_orbit_'..ringIndex)
            loop.temporary=true;loop.enabled=false
            if kind=='catalyst' then
                fx.rings[ringIndex]=BuildCircle(loop,p,ringIndex,mask)
            else
                local g=GrainGeometry(loop,mask)
                local ring=BuildLoop(g,p,ringIndex)
                ring.node=loop;ring.index=ringIndex
                local head=loop:CreateChild(kind..'_orbit_head_'..ringIndex)
                head.temporary=true;head.enabled=true
                local hg=GrainGeometry(head,mask)
                DefineCuboid(hg,ring.tangentHalf*1.12,ring.radialHalf*1.18,ring.depthHalf*1.18,{1.0,.98,.74})
                ring.head=head;ring.headGeometry=hg
                fx.rings[ringIndex]=ring
                UpdateHead(ring,p)
            end
        end
        fx.rotor=fx.rings[1]
    end)
    if not ok then
        M.Dispose(fx)
        print('WeaponOrbitGrains: '..kind..' unavailable: '..tostring(err))
        return nil
    end
    return fx
end

function M.Visible(fx,shown)
    if not fx or not fx.node then return end
    fx.node.enabled=shown
    for _,ring in ipairs(fx.rings) do
        ring.node.enabled=shown
        if ring.streams then
            for _,stream in ipairs(ring.streams) do stream.enabled=shown end
        else
            ring.head.enabled=shown
        end
    end
end

function M.Update(fx,dt)
    if not fx or not fx.node or not fx.node.enabled then return end
    local step=math.max(dt or 0,0)/fx.period
    fx.phaseA=WrapPhase(fx.phaseA+step)
    fx.phaseB=WrapPhase(fx.phaseB-step)
    fx.phase=fx.phaseA
    if fx.rings[1].streams then
        AnimateCircle(fx.rings[1],fx.phaseA)
        AnimateCircle(fx.rings[2],fx.phaseB)
        return
    end
    fx.rings[1].phase=fx.phaseA
    fx.rings[2].phase=fx.phaseB
    UpdateHead(fx.rings[1],fx.rings[1].profile)
    UpdateHead(fx.rings[2],fx.rings[2].profile)
end

function M.Dispose(fx)
    if fx and fx.node then fx.node:Remove();fx.node=nil;fx.rings=nil;fx.rotor=nil end
end
return M
