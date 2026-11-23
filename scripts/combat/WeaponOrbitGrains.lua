-- Two explicit, front-readable pixel loops shared by the catalyst and wing sword.
-- Each loop is an elliptical strip made from short tangent-aligned voxel bars.
-- A separate bright head moves against the loop flow so the long axes remain
-- stable in the final front projection while the crossed planes stay 3D.
local M = {}
local material
local profiles = {
    catalyst = {count=48, period=8, radius=.296, minor=.42, width=.0048,
        depth=.0038, y=0, z=-.145, aSlope=.28, bSlope=-.28,
        aTilt=.32, bTilt=-.32},
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

local function DefineCuboid(g,halfT,halfR,halfD,color)
    g:BeginGeometry(0,TRIANGLE_LIST)
    for k,face in ipairs(faces) do
        local tone=.84+.15*(k%3)/2
        local c=Color(color[1]*tone,color[2]*tone,color[3]*tone,1)
        for _,index in ipairs(order) do
            local q=corners[face[index]]
            g:DefineVertex(Vector3(q[1]*halfT,q[2]*halfR,q[3]*halfD))
            g:DefineColor(c);g:DefineTexCoord(Vector2(.20,.20))
        end
    end
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
            local g=loop:CreateComponent('CustomGeometry')
            g.castShadows=false;g.viewMask=mask;g.lightMask=mask;g.zoneMask=mask
            local ring=BuildLoop(g,p,ringIndex)
            ring.node=loop;ring.index=ringIndex
            local head=loop:CreateChild(kind..'_orbit_head_'..ringIndex)
            head.temporary=true;head.enabled=true
            local hg=head:CreateComponent('CustomGeometry')
            hg.castShadows=false;hg.viewMask=mask;hg.lightMask=mask;hg.zoneMask=mask
            DefineCuboid(hg,ring.tangentHalf*1.12,ring.radialHalf*1.18,ring.depthHalf*1.18,{1.0,.98,.74})
            ring.head=head;ring.headGeometry=hg
            fx.rings[ringIndex]=ring
            UpdateHead(ring,p)
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
    for _,ring in ipairs(fx.rings) do ring.node.enabled=shown end
end

function M.Update(fx,dt)
    if not fx or not fx.node or not fx.node.enabled then return end
    local step=math.max(dt or 0,0)/fx.period
    fx.phaseA=WrapPhase(fx.phaseA+step)
    fx.phaseB=WrapPhase(fx.phaseB-step)
    fx.phase=fx.phaseA
    fx.rings[1].phase=fx.phaseA
    fx.rings[2].phase=fx.phaseB
    UpdateHead(fx.rings[1],fx.rings[1].profile)
    UpdateHead(fx.rings[2],fx.rings[2].profile)
end

function M.Dispose(fx)
    if fx and fx.node then fx.node:Remove();fx.node=nil;fx.rings=nil;fx.rotor=nil end
end
return M
