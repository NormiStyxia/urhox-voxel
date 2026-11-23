local M = {}
local material
local profiles = {
    catalyst = {count=40, radius=.285, period=8, y=0, z=0},
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

local function GrainGeometry(node,mask)
    local g=node:CreateComponent('CustomGeometry')
    g.castShadows=false;g.viewMask=mask;g.lightMask=mask;g.zoneMask=mask
    return g
end

-- Each pose is one closed square-section tube. Adjacent spans use the exact
-- same station corners, including the wrap from the last station to the first.
local function BuildLinePose(g,count,radius,pose,index)
    local sections={}
    local halfWidth=.00385
    for i=0,count-1 do
        local sector=i%(count/2)
        local sign=i<count/2 and 1 or -1
        local angle=sector*2*math.pi/count
        local c,s=math.cos(angle),math.sin(angle)
        -- Only short, opposite pairs of arcs change on a tick. The rest of the
        -- line remains fixed, and paired displacements keep the centre still.
        local arc=(sector+3*index)%10
        local shift=0
        if pose==2 and arc<=1 then shift=.008 end
        if pose==3 and arc>=5 and arc<=6 then shift=-.008 end
        local r=radius+shift
        local grid=.005
        local x=sign*grid*math.floor(r*c/grid+.5)
        local y=sign*grid*math.floor(r*s/grid+.5)
        local z=sign*shift*.5
        local dx,dy=sign*c*halfWidth,sign*s*halfWidth
        sections[i+1]={Vector3(x+dx,y+dy,z+halfWidth),Vector3(x-dx,y-dy,z+halfWidth),
            Vector3(x-dx,y-dy,z-halfWidth),Vector3(x+dx,y+dy,z-halfWidth)}
    end
    local white=Color(.96,.96,.96,1)
    local uv=Vector2(.1875,.1875) -- centre of an opaque white texel of the shared material
    g:BeginGeometry(0,TRIANGLE_LIST)
    for i,section in ipairs(sections) do
        local nextSection=sections[i%count+1]
        for j=1,4 do
            local k=j%4+1
            local quad={section[j],nextSection[j],nextSection[k],section[k]}
            for _,corner in ipairs(order) do
                g:DefineVertex(quad[corner]);g:DefineColor(white);g:DefineTexCoord(uv)
            end
        end
    end
    g:Commit()
    assert(g:SetMaterial(0,material)~=false,'line material binding failed')
end

-- Four stars share the existing white pixel material. Each sits on a station
-- outside the jittering arcs. The three short axes keep a glint visible edge-on.
local starStations={{6,21},{13,37}}
local starOffsets={{0,13},{8,20}}
local starEnvelope={.40,.72,1,.72,.40}
local function BuildStars(loop,p,index,mask,rotation)
    local stars={}
    for j,station in ipairs(starStations[index]) do
        local node=loop:CreateChild('catalyst_star_'..j)
        node.temporary=true;node.enabled=false
        local a=station*2*math.pi/p.count
        node.position=Vector3(.005*math.floor(p.radius*math.cos(a)/.005+.5),
            .005*math.floor(p.radius*math.sin(a)/.005+.5),0)
        node.rotation=rotation
        local g=GrainGeometry(node,mask)
        g:BeginGeometry(0,TRIANGLE_LIST)
        local white={1,1,1}
        AddCuboid(g,Vector3.ZERO,.022,.0045,.0045,white)
        AddCuboid(g,Vector3.ZERO,.0045,.024,.0045,white)
        AddCuboid(g,Vector3.ZERO,.0045,.0045,.017,white)
        g:Commit()
        assert(g:SetMaterial(0,material)~=false,'star material binding failed')
        stars[j]={node=node,offset=starOffsets[index][j],size=0}
    end
    return stars
end

local function AnimateStars(ring,tick)
    for _,star in ipairs(ring.stars) do
        local size=starEnvelope[(tick+star.offset)%24+1] or 0
        if size~=star.size then
            star.node.enabled=size>0
            if size>0 then star.node.scale=Vector3(size,size,size) end
            star.size=size
        end
    end
end

local function BuildCircle(loop,p,index,mask)
    local ring={node=loop,poses={},active=1}
    local roll=index==1 and -12 or 32
    local pitch=index==1 and 60 or 52
    loop.rotation=Quaternion(0,0,roll)*Quaternion(pitch,0,0)
    for pose=1,3 do
        local node=loop:CreateChild('catalyst_line_pose_'..pose)
        node.temporary=true;node.enabled=false
        BuildLinePose(GrainGeometry(node,mask),p.count,p.radius,pose,index)
        ring.poses[pose]=node
    end
    ring.stars=BuildStars(loop,p,index,mask,Quaternion(-pitch,0,0)*Quaternion(0,0,-roll))
    return ring
end

local linePoses={1,2,1,3}
local function AnimateLine(ring,phase)
    local active=linePoses[math.floor(phase*32)%4+1]
    if active==ring.active then return end
    ring.poses[ring.active].enabled=false
    ring.poses[active].enabled=true
    ring.active=active
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
        if ring.poses then
            ring.poses[ring.active].enabled=shown
            for _,star in ipairs(ring.stars) do star.node.enabled=shown and star.size>0 end
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
    if fx.rings[1].poses then
        local tick=math.floor(fx.phaseA*96)
        for _,ring in ipairs(fx.rings) do AnimateStars(ring,tick) end
        AnimateLine(fx.rings[1],fx.phaseA)
        AnimateLine(fx.rings[2],(fx.phaseA+.015625)%1)
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
