-- Positions below are in island-local metres, looking north from the waterfall.
local Brush = require('ruins.VoxelBrush')
local Noise = require('ruins.Noise')
local P = require('ruins.RuinsPalette').P
local H = { x = 720, z = 0, base = 6 }
local abs, floor, sin, cos, sqrt = math.abs, math.floor, math.sin, math.cos, math.sqrt
local oak, amber, cedar, slate, ember, flame = 150,151,152,153,154,155
local window = 156
-- Axial grain survives greedy meshing because the palette ID stays on each face.
local cedarPost, oakPlankZ, cedarBeamZ = 157,158,159
local WATER_LEVEL = -.375
local WATER_VIEW = 0x10000000
local mirror
local mirrorTiers={high={640,24},medium={448,16},low={288,10}}
local function pattern(x,z)
    return sin(x*.49 + z*.17) + .65*cos(z*.81-x*.23)
end
local function edge(x,z)
    local a = math.atan(z/19,x/26)
    return 19*(1 + .045*cos(5*a)+.032*sin(9*a) - sqrt((x/26)^2+(z/19)^2))
end
local function pool(x,z)
    return ((x+7.5)/10)^2 + ((z+5.25)/6.25)^2
end
local function channel(x,z) return abs(x+11.75)<1.65 and z < -6 end
local function pad(x,z) return sqrt((x-12)^2+(z-3)^2) end
local function top(x,z)
    -- The water mesh occupies half-metre cells. Keep the submerged columns on that footprint.
    local wx,wz=(floor(x*2)+.5)*.5,(floor(z*2)+.5)*.5
    if channel(wx,wz) then return -1.5 end
    local basin=pool(wx,wz)
    if basin<1 then return -.75-.25*floor(4*(1-basin)) end
    x,z=(floor(x*4)+.5)*.25,(floor(z*4)+.5)*.25
    if pad(x,z)<8.8 then return 1.5 end
    if x>9 and x<15 and z<0 then return math.max(0,math.min(1.5,floor((z+10)*1.3)*.25)) end
    local north=2*(1-((x+6)/18)^2-((z-19+.55*sin(x*.31))/5.7)^2)
    local bench=math.max(0,math.min(1,2-math.max(abs(x+13),abs(z-15))))
    north=north+(.875-north)*bench -- a level tread around the mature golden tree's spreading roots
    local west=1.25*(1-((x+24+.4*sin(z*.42))/5.7)^2-((z-1)/11)^2)
    local south=1-((x+2)/10)^2-((z+18+.45*sin(x*.52))/4.2)^2
    local east=.85*(1-((x-17)/8)^2-((z+13)/5)^2)
    return .25*floor(4*math.max(0,north,west,south,east))
end
function H.Contains(x,z) return abs(x-H.x)<35 and abs(z-H.z)<28 end
function H.Ground(x,z,margin) return edge(x-H.x,z-H.z)>=(margin or 0) end
function H.Height(x,z) return H.base+top(x-H.x,z-H.z) end
function H.Safe(x,y,z)
    local lx,lz=x-H.x,z-H.z
    return edge(lx,lz)>1.6 and pool(lx,lz)>1.06 and not channel(lx,lz) and abs(y-H.Height(x,z))<.46
end
function H.NearForge(p) return (p.x-H.x-1.25)^2+(p.z-H.z-6.0)^2<15 and abs(p.y-H.base)<2 end
local activeJob
local ripples,nextSlot,wet,lastX,lastZ={},1,false,nil,nil
local stepTime,travel=0,0
local WAVE_LIFE, STEP_TIME, STEP_DISTANCE = 1.4,.35,.82

-- The pool mesh samples the centre of each half-metre cell. Use the same
-- sample for contact, including the last cells at the waterfall lip.
local function waterBed(x,z)
    local cx,cz=floor(x*2)*.5+.25,floor(z*2)*.5+.25
    if edge(cx,cz)>0 then
        local bed=top(cx,cz)
        if bed<0 then return bed end
    end
end

function H.ClearRipples()
    for slot in pairs(ripples) do
        H.spring:SetShaderParameter('foot_wave'..slot,Variant(Vector4(0,0,0,0)))
        ripples[slot]=nil
    end
    nextSlot,wet,lastX,lastZ,stepTime,travel=1,false,nil,nil,0,0
end

function H.ReleaseReflection()
    if not mirror then return end
    if mirror.surface then mirror.surface:SetNumViewports(0) end
    if H.spring then
        H.spring:SetShaderParameter('mirror_ready',Variant(0.0))
        if mirror.bindingAttempted then H.spring:SetSurfaceTexture('mirror_color',nil) end
    end
    if mirror.node then mirror.node:Remove() end
    if mirror.texture then mirror.texture:Dispose() end
    mirror=nil
end

local function createReflection(r,scene,w,h)
    r.texture=Texture2D:new()
    r.texture:SetNumLevels(1)
    if not r.texture:SetSize(w,h,Graphics:GetRGBAFormat(),TEXTURE_RENDERTARGET) then return false end
    r.texture:SetFilterMode(FILTER_BILINEAR)
    r.texture:SetAddressMode(COORD_U,ADDRESS_CLAMP)
    r.texture:SetAddressMode(COORD_V,ADDRESS_CLAMP)
    r.surface=r.texture:GetRenderSurface()
    if not r.surface then return false end
    r.node=scene:CreateChild('HomeSpringMirror')
    local camera=r.node:CreateComponent('Camera')
    r.camera=camera
    camera.useReflection=true
    camera.reflectionPlane=Plane(Vector3.UP,Vector3(H.x,H.base+WATER_LEVEL,H.z))
    camera.useClipping=true
    camera.clipPlane=Plane(Vector3.UP,Vector3(H.x,H.base+WATER_LEVEL-.06,H.z))
    camera.autoAspectRatio=false
    camera.viewOverrideFlags=VO_DISABLE_SHADOWS
    r.view=Viewport:new(scene,camera)
    r.view.drawDebug=false
    local forward=cache:GetResource('XMLFile','RenderPaths/Forward.xml')
    if not forward then return false end
    r.view:SetRenderPath(forward)
    -- Opaque and alpha-tested voxel/leaf geometry plus actual local lights.
    -- Exclude transparent passes (including their scene-colour copies) and post FX.
    local path=r.view:GetRenderPath()
    local hasBase=false
    for i=path:GetNumCommands()-1,0,-1 do
        local cmd=path:GetCommand(i)
        if cmd.type==CMD_SCENEPASS and cmd.pass=='base' then
            hasBase=true
        elseif cmd.type~=CMD_CLEAR and cmd.type~=CMD_FORWARDLIGHTS then
            path:RemoveCommand(i)
        end
    end
    if not hasBase then return false end
    r.surface:SetUpdateMode(SURFACE_MANUALUPDATE)
    r.surface:SetViewport(0,r.view)
    r.bindingAttempted=true
    return H.spring:SetSurfaceTexture('mirror_color',r.texture)
end

-- Run after the final gameplay-camera pose. The shader reprojects to the saved
-- capture pose between updates, so a 10 Hz reflection does not swim with the HUD.
function H.UpdateReflection(dt,scene,source,tier)
    if not H.spring then return end
    if not H.poolBounds then
        H.poolBounds=BoundingBox(Vector3(H.x-18.5,H.base+WATER_LEVEL-.08,H.z-21),
            Vector3(H.x+5,H.base+WATER_LEVEL+.08,H.z+2.5))
    end
    local node=source.node
    local pos=node.worldPosition
    if pos.y<=H.base+WATER_LEVEL or (pos.x-H.x)^2+(pos.z-H.z)^2>110^2
        or source.frustum:IsInsideFast(H.poolBounds)==OUTSIDE then return end
    local profile=mirrorTiers[tier] or mirrorTiers.medium
    local sw,sh=graphics:GetWidth(),graphics:GetHeight()
    if sw<=0 or sh<=0 then return end
    local scale=math.min(.5,profile[1]/math.max(sw,sh))
    local w,h=math.max(1,floor(sw*scale+.5)),math.max(1,floor(sh*scale+.5))
    if not mirror or mirror.w~=w or mirror.h~=h then
        H.ReleaseReflection()
        mirror={w=w,h=h,elapsed=1}
        local ok,ready=pcall(createReflection,mirror,scene,w,h)
        if not ok or not ready then
            H.ReleaseReflection()
            mirror={w=w,h=h,failed=true}
            print('HomeSpring: planar reflection unavailable; using screen-space reflection ('..tostring(ready)..')')
        end
    end
    local r=mirror
    if r.failed then return end
    if r.queued and not r.ready then
        H.spring:SetShaderParameter('mirror_ready',Variant(1.0))
        r.ready=true
    end
    r.elapsed=r.elapsed+dt
    local interval=1/profile[2]
    if r.elapsed<interval then return end
    r.elapsed=r.elapsed%interval
    local c=r.camera
    r.node:SetWorldTransform(pos,node.worldRotation)
    c.viewMask=source.viewMask & ~WATER_VIEW
    c.fov,c.zoom,c.aspectRatio=source.fov,source.zoom/1.22,sw/sh
    c.nearClip,c.farClip=source.nearClip,math.min(145,source.farClip)
    c.lodBias=.8
    local sy=.5*c.zoom/math.tan(math.rad(c.fov)*.5)
    H.spring:SetShaderParameter('mirror_eye',Variant(Vector4(pos.x,pos.y,pos.z,H.base+WATER_LEVEL)))
    H.spring:SetShaderParameter('mirror_right',Variant(node.worldRight*(sy/c.aspectRatio)))
    H.spring:SetShaderParameter('mirror_up',Variant(node.worldUp*(-sy)))
    H.spring:SetShaderParameter('mirror_forward',Variant(node.worldDirection))
    r.surface:QueueUpdate()
    r.queued=true
end

function H.Stop()
    H.ReleaseReflection()
    H.poolBounds=nil
    H.ClearRipples()
    H.spring,H.hearth,H.field,H.housing,H.meadowMaterial=nil,nil,nil,nil,nil
    H.lastDay,H.lastDusk,H.lastNight=nil,nil,nil
end

local function updateWater(dt,feet)
    for slot,wave in pairs(ripples) do
        wave.age=wave.age+dt
        if wave.age>=WAVE_LIFE then wave.strength=0; ripples[slot]=nil end
        H.spring:SetShaderParameter('foot_wave'..slot,Variant(Vector4(wave.x,wave.z,wave.age,wave.strength)))
    end
    local x,z,bed
    if feet and feet.y<=H.base+WATER_LEVEL+(wet and .04 or 0) then
        x,z=feet.x-H.x,feet.z-H.z
        bed=waterBed(x,z)
    end
    -- Permit solver slop on a submerged step and reject positions below the island.
    if not bed or feet.y<H.base+bed-.12 then
        wet=false
        return
    end
    if feet.y>H.base+WATER_LEVEL then
        -- Retain contact across the small surface swell, without counting dry travel.
        lastX,lastZ=x,z
        return
    end
    if wet then
        local distance=sqrt((x-lastX)^2+(z-lastZ)^2)
        if distance>=.035 then
            travel=travel+distance
            lastX,lastZ=x,z
        end
        stepTime=stepTime+dt
    end
    if not wet or (stepTime>=STEP_TIME and travel>=STEP_DISTANCE) then
        local strength=wet and .72 or 1
        ripples[nextSlot]={x=x,z=z,age=0,strength=strength}
        H.spring:SetShaderParameter('foot_wave'..nextSlot,Variant(Vector4(x,z,0,strength)))
        nextSlot=nextSlot%4+1
        stepTime,travel=0,0
        lastX,lastZ=x,z
    end
    wet=true
end

function H.Update(dt,feet,dn)
    if H.spring then updateWater(dt,feet) end
    local day,dusk,night=floor(dn.day*128+.5)/128,floor(dn.dusk*128+.5)/128,floor(dn.nightK*128+.5)/128
    if day==H.lastDay and dusk==H.lastDusk and night==H.lastNight then return end
    H.lastDay,H.lastDusk,H.lastNight=day,dusk,night
    if H.spring then H.spring:SetShaderParameter('sky_phase',Variant(Vector3(day,dusk,night))) end
    if H.meadowMaterial then H.meadowMaterial:SetShaderParameter('meadow_sun',Variant(day*(1-night))) end
    if H.housing then H.housing:SetShaderParameter('window_light',Variant(.035+.42*(1-day)+.28*night)) end
    if H.hearth then H.hearth.brightness=.78+.34*(1-day) end
end

local function brush(world,lo,hi,s)
    if activeJob then coroutine.yield() end
    local b=Brush.New(world,{origin=Vector3(H.x,H.base,H.z),min=lo,max=hi,size=s})
    if activeJob then activeJob.ids[b.volume:GetVolumeId()]=true end
    return b
end
local function lawnMaterial(x,z,h)
    local patch=pattern(x*.65,z*.65)+.36*pattern(x*1.8,z*1.8)
    if h<0 then return patch>0 and P.SAND or P.STONE_MOSS end
    if pad(x,z)<8.85 or (x>9 and x<15 and z>-10 and z<0) then return P.STONE_B end
    if pool(x,z)<1.22 or abs(z-4)<1.35 and x<8 and x>-18 or abs(x-4)<1.3 and abs(z)<10 then
        return patch>0 and P.PATH or P.PATH_B
    end
    if patch>1.45 then return P.GRASS_D end
    if patch>.48 then return P.GRASS_B end
    return patch<-.65 and P.GRASS_C or P.GRASS_A
end

local function rockFloor(x,z,d)
    local rim=1.15+1.05*pattern(x*.51,z*.51)
    return math.max(-18,math.min(-2.5,floor((-3.5-rim-d*1.45)*2)*.5))
end

-- A bank rock may straddle both the fine turf and the coarser cliff below -2 m.
-- Keep only the rock cells outside their respective occupied columns. The union
-- stays identical, but the waterline and cliff no longer have two coplanar skins.
local function clearColumnRange(b,i,k,low,high)
    local j0,j1=b:Range(low,high,2)
    if j0<=j1 then b.grid:FillBox(i,j0,k,i,j1,k,false) end
end
local function trimGround(b)
    for i=0,b.nx-1 do for k=0,b.nz-1 do
        local x,_,z=b:Center(i,0,k)
        if edge(x,z)>0 then clearColumnRange(b,i,k,-2,top(x,z)) end
        if b.lmin[2]<-2 then
            local cx,cz=(floor(x*2)+.5)*.5,(floor(z*2)+.5)*.5
            local d=edge(cx,cz)
            if d>0 then clearColumnRange(b,i,k,rockFloor(cx,cz,d),-2) end
        end
    end end
end

-- Both brushes are aligned to island-local axes. The owning grid is the same
-- size or coarser, so each occupied vertical run can be removed in one box.
local function trimCovered(b,owner)
    local s=owner.s
    local ix0,ix1=owner:Range(b.lmin[1],b.lmin[1]+b.nx*b.s,1)
    local iy0,iy1=owner:Range(b.lmin[2],b.lmin[2]+b.ny*b.s,2)
    local iz0,iz1=owner:Range(b.lmin[3],b.lmin[3]+b.nz*b.s,3)
    for i=ix0,ix1 do
        if activeJob and (i-ix0)%16==0 then coroutine.yield() end
        for k=iz0,iz1 do
            local x,z=owner.lmin[1]+i*s,owner.lmin[3]+k*s
            local start=nil
            for j=iy0,iy1+1 do
                if j<=iy1 and owner.grid:IsSolid(i,j,k) then
                    start=start or j
                elseif start then
                    b:Carve(x,owner.lmin[2]+start*s,z,x+s,owner.lmin[2]+j*s,z+s)
                    start=nil
                end
            end
        end
    end
end

local function terrain(world)
    local rocks={P.DEEP_A,P.CLIFF_C,P.CLIFF_B,P.CLIFF_A}
    for bx=-28,14,14 do for bz=-21,7,14 do
        local b=brush(world,{bx,-18,bz},{bx+14,-2,bz+14},.5)
        for i=0,b.nx-1 do for k=0,b.nz-1 do
            local x,z=bx+(i+.5)*.5,bz+(k+.5)*.5
            local d=edge(x,z)
            if d>0 then
                local low=rockFloor(x,z,d)
                local first=floor((low+18)*2)
                b.grid:FillBox(i,first,k,i,b.ny-1,k,true)
                local tilt=pattern(x*.70,z*.70)
                for j=first,b.ny-1,4 do
                    local band=math.max(1,math.min(4,4+floor((j*.5-18)*.2+tilt*.85)))
                    b.grid:PaintBox(i,j,k,i,math.min(j+3,b.ny-1),k,rocks[band])
                end
            end
        end end
        b:Finish()
        local cap=brush(world,{bx,-2,bz},{bx+14,2,bz+14},.25)
        local g=cap.grid
        for i=0,cap.nx-1 do for k=0,cap.nz-1 do
            local x,z=bx+(i+.5)*.25,bz+(k+.5)*.25
            if edge(x,z)>0 then
                local h=top(x,z)
                local last=floor((h+2)*4)-1
                local skin=lawnMaterial(x,z,h)
                g:FillBox(i,0,k,i,last,k,true)
                if last>0 then
                    local grain=pattern(x*.72,z*.72)
                    g:PaintBox(i,0,k,i,last-1,k,grain>0 and P.CLIFF_A or P.CLIFF_B)
                    if skin>=P.GRASS_A and skin<=P.GRASS_D then
                        g:PaintBox(i,math.max(0,last-(grain>.55 and 2 or 1)),k,i,last-1,k,grain>0 and P.DIRT or P.DIRT_B)
                    end
                end
                g:SetVoxelMaterial(i,last,k,skin)
            end
        end end
        cap:Finish({masonry='meadow'})
    end end
end
local function column(b,x,z,y,h)
    b:Box(x-.75,y,z-.75,x+.75,y+.5,z+.75,P.STONE_C)
    b:Box(x-.5,y+.5,z-.5,x+.5,y+h,z+.5,P.MARBLE_B)
    b:Box(x-.125,y+.9,z-.625,x+.125,y+h-.35,z-.5,P.MARBLE_BLUE)
    b:Box(x-.625,y+h-.5,z-.625,x+.625,y+h-.25,z+.625,P.GOLD_DARK)
    b:Box(x-.75,y+h-.25,z-.75,x+.75,y+h+.25,z+.75,P.MARBLE_A)
end
-- The two surviving columns at the west entrance can be inspected at walking distance.
local function entranceColumn(world,x,z,h)
    local y=1.5
    local b=brush(world,{x-.75,y,z-.75},{x+.75,y+h+.25,z+.75},.125)
    b:Box(x-.75,y,z-.75,x+.75,y+.375,z+.75,P.STONE_C)
    b:Box(x-.625,y+.375,z-.625,x+.625,y+.625,z+.625,P.STONE_B)
    b:Shape(x-.5,y+.625,z-.5,x+.5,y+h-.25,z+.5,function(px,_,pz)
        if abs(px-x)+abs(pz-z)<.82 then return P.MARBLE_B end
    end)
    b:Box(x-.625,y+h-.25,z-.625,x+.625,y+h,z+.625,P.STONE_B)
    b:Box(x-.75,y+h,z-.75,x+.75,y+h+.25,z+.75,P.MARBLE_A)
    b:Finish({masonry='ashlar'})
    -- Narrow mouldings around the plinth leave the shadow recess between the two courses open.
    local trim=brush(world,{x-.8125,y+.3125,z-.8125},{x+.8125,y+.6875,z+.8125},.0625)
    for _,band in ipairs({{.3125,.375,.8125,.75,P.STONE_A},{.50,.5625,.6875,.625,P.MARBLE_B},
        {.625,.6875,.5625,.50,P.STONE_A}}) do
        local lo,hi,outer,inner,mat=table.unpack(band)
        trim:Shape(x-outer,y+lo,z-outer,x+outer,y+hi,z+outer,function(px,_,pz)
            if math.max(abs(px-x),abs(pz-z))>=inner then return mat end
        end)
    end
    trim:Finish({visual=true,masonry='ashlar'})
end
local function courtyard(world)
    local b=brush(world,{2,1, -7},{22,6,13},.25)
    b:Shape(3,1.5,-6,21,1.75,12,function(x,_,z)
        local r=pad(x,z);local diamond=abs(x-12)+abs(z-3)
        if r>8.55 then return end
        if abs(r-7.6)<.21 or abs(r-4.65)<.17 then return P.GOLD_DARK end
        if abs(diamond-3.5)<.32 or abs(diamond-1.45)<.34 then return P.MARBLE_BLUE end
        if abs(diamond-3)<.22 then return P.MARBLE_DARK end
        return (floor(x/1.5)+floor(z/1.5))%4==0 and P.TILE_B or P.TILE_A
    end)
    for i=0,11 do
        local a=i*math.pi/6
        if i~=9 and i~=6 and i~=5 and i~=7 then column(b,12+8.3*cos(a),3+8.3*sin(a),1.5,i%4==1 and 2.75 or 1.25) end
    end
    b:Finish({masonry='floor'})
    entranceColumn(world,4.875,7.125,2.75)
    entranceColumn(world,4.875,-1.125,1.25)
end
local function arch(b,x,z,w,spring,rise)
    for _,side in ipairs({-1,1}) do column(b,x+side*w,z,0,spring) end
    b:Shape(x-w-1,spring-.5,z-.625,x+w+1,spring+rise+1.25,z+.625,function(px,y,pz)
        local dx,dy=(px-x)/w,(y-spring)/rise
        local r=sqrt(dx*dx+dy*dy)
        if dy>=0 and r>=.88 and r<=1.13 then
            local wedge=floor(math.atan(dy,dx)*14)
            return wedge%7==1 and P.STONE_MOSS or (wedge%3==0 and P.STONE_C or P.MARBLE_A)
        end
    end)
end
local function roof(b,cx,cz,w,d,eave,rise)
    -- Shingle courses overlap towards the eaves. Gable ends sit behind the fascia.
    local rows=floor(d/.375)
    for n=0,rows-1 do
        local z=n*.375; local y=eave+floor((1-z/d)*rise*8)/8
        for _,side in ipairs({-1,1}) do
            local line=cz+side*z
            b:Box(cx-w,y-.25,line-.25,cx+w,y,line+.25,cedar)
            for j=0,math.ceil(2*w/1.125) do
                local start=cx-w+j*1.125-(n%2)*.5
                local lo,hi=math.max(cx-w,start),math.min(cx+w,start+1)
                if hi>lo then b:Box(lo,y,line-.25,hi,y+.125,line+.25,(j+n)%5==1 and amber or oak) end
            end
        end
    end
    b:Box(cx-w-.125,eave+rise,cz-.25,cx+w+.125,eave+rise+.25,cz+.25,cedar)
    for _,sign in ipairs({-1,1}) do
        local endX=cx+sign*(w-.55)
        b:Shape(endX-.15,eave-.5,cz-d+.5,endX+.15,eave+rise,cz+d-.5,function(_,y,z)
            if y<eave+rise*(1-abs(z-cz)/d) then return oak end
        end)
    end
end
local function porchJoint(world,x)
    -- The post cap starts at z=4.125. A shouldered beam enters it from the pond side.
    local join=brush(world,{x-.4375,2.6875,3.75},{x+.4375,3.25,4.25},.0625)
    join:Box(x-.3125,2.875,3.875,x+.3125,3.1875,4.125,oak)
    join:Box(x-.1875,2.9375,3.75,x+.1875,3.125,3.875,oakPlankZ)
    join:Box(x-.3125,2.9375,3.9375,x-.375,3.0625,4.0625,cedar)
    join:Box(x+.3125,2.9375,3.9375,x+.375,3.0625,4.0625,cedar)
    join:Box(x-.1875,2.75,4.0625,x+.1875,2.875,4.25,cedar)
    local volume=join:Finish({visual=true})
    if volume and volume.material then
        -- Only these two near-view joints own a local timber frame. Never write
        -- its centre onto the shared size:masonry material used by other volumes.
        local material=volume.material:Clone()
        material:SetShaderParameter('wood_center',Variant(Vector4(H.x+x,H.base+3.03125,H.z+4,1)))
        volume.material=material
    end
end
local function house(world)
    local old=brush(world,{-22,0,6},{5,12,17},.25)
    arch(old,-9.5,13.5,6,5,5.25); arch(old,-18,9,2.8,3.25,3.1)
    for _,p in ipairs({{-20,6,5.25},{2.5,11.5,6},{-1,15,4.5}}) do column(old,p[1],p[2],0,p[3]) end
    trimGround(old)
    old:Finish({masonry='ashlar'})
    local b=brush(world,{-18,0,3},{4,9,14},.125)
    b:Box(-16.25,0,4,-1,.375,12,P.STONE_C)
    b:Box(-16,.375,7,-1.5,4.25,12,P.STONE_B)
    b:Box(-15.75,.5,7.375,-1.875,4,11.625,false)
    b:Carve(-10,.375,6.875,-8,3.25,7.5)
    for i=0,39 do b:Box(-16+i*.375,.375,4,-15.6375+i*.375,.5,7.375,i%7==2 and cedarBeamZ or oakPlankZ) end
    for _,x in ipairs({-15.5,-12.25,-7,-2}) do
        b:Box(x-.1875,.5,4.25,x+.1875,3.25,4.625,cedarPost)
        b:Box(x-.375,2.875,4.125,x+.375,3.375,4.75,oak)
        b:Box(x-.125,2.5,4.75,x+.125,3,5,P.GOLD_DARK)
        b:Box(x-.25,2.125,4.75,x+.25,2.5,5.25,window)
    end
    for _,x in ipairs({-14,-5.5,-3}) do
        b:Box(x-1,1.25,6.75,x+1,3.25,7,cedar)
        b:Box(x-.75,1.5,6.625,x+.75,3,6.75,window)
        b:Box(x-.125,1.5,6.5,x+.125,3,6.625,cedarPost)
        b:Box(x-.75,2.125,6.5,x+.75,2.25,6.625,oak)
    end
    roof(b,-14.5,9.5,2.875,3.375,4.15,2.5)
    roof(b,-3.5,9.75,3.25,3.25,4.0,1.75)
    roof(b,-9,5.75,7.75,2,3.2,1)
    -- A cross-gable dormer faces the pond. Its lit window breaks the long roof slope.
    b:Box(-9.75,4.5,6.65,-6.75,6.25,9.5,cedar)
    b:Box(-9.25,4.875,6.5,-7.25,6,6.75,window)
    b:Box(-8.375,4.875,6.375,-8.125,6,6.5,cedarPost)
    for row=0,14 do
        local x=row*.125;local y=7.5-row*.10
        for _,sign in ipairs({-1,1}) do
            local at=-8.25+x*sign
            b:Box(at-.125,y-.25,6.125,at+.125,y,9.875,row%4==2 and cedarBeamZ or oakPlankZ)
            b:Box(at-.125,y-.375,6,at+.125,y-.125,6.25,cedar)
        end
    end
    b:Box(-13,4,10,-12,7.75,11,P.STONE_D); b:Box(-13.25,7.5,9.75,-11.75,8,11.25,P.MARBLE_B)
    -- Stone oven with a recessed vaulted mouth, coals and an iron anvil.
    b:Box(-.5,0,7.125,2.875,2.875,10,P.STONE_C)
    b:Shape(-.125,.5,7,2.5,2.75,9.375,function(x,y) if y<1.4+1.05*sqrt(math.max(0,1-((x-1.2)/1.25)^2)) then return false end end)
    b:Box(0,.5,7.375,2.375,.75,9.375,ember)
    for j=0,6 do local x=.125+j*.3125; b:Box(x,.75,8.375,x+.25,1+(j*3%5)*.125,9,flame) end
    b:Box(-.625,2.875,7,3,3.25,10.125,P.STONE_A); b:Box(.5,3.25,8.5,1.75,5.25,9.75,P.STONE_D)
    b:Box(.625,0,4.625,1.625,.75,5.625,P.WOOD); b:Box(.375,.75,4.5,1.875,1,5.75,slate)
    b:Box(.875,1,4.875,1.375,1.375,5.5,slate); b:Box(.125,1.375,4.75,2.125,1.625,5.625,slate)
    porchJoint(world,-12.25)
    porchJoint(world,-7)
    -- Upper rooms step back from the forge and the low pond-facing porch.
    local loft=brush(world,{-14,4,5.5},{-4,14,13.75},.125)
    local sideBands={}
    local function storey(x0,z0,x1,z1,y,h)
        loft:Box(x0,y,z0,x1,y+h,z1,P.MARBLE_B)
        loft:Carve(x0+.25,y+.25,z0+.25,x1-.25,y+h,z1-.25)
        for _,level in ipairs({y,y+h-.25}) do
            loft:Box(x0-.125,level,z0-.125,x1+.125,level+.25,z1+.125,cedar)
            sideBands[#sideBands+1]={x0,z0,x1,z1,level}
        end
        for _,x in ipairs({x0,(x0+x1)/2,x1-.25}) do
            loft:Box(x,y,z0-.125,x+.25,y+h,z0+.125,cedarPost)
        end
        for _,x in ipairs({x0+.875,x1-1.75}) do
            loft:Box(x-.125,y+.625,z0-.25,x+.875,y+2,z0,oak)
            loft:Box(x,y+.875,z0-.375,x+.75,y+1.875,z0-.25,window)
            loft:Box(x+.25,y+.875,z0-.5,x+.375,y+1.875,z0-.375,cedarPost)
        end
    end
    storey(-12.75,7,-5.25,12,4,3)
    roof(loft,-9,9.5,4.375,3.375,7,2)
    storey(-11.875,8.125,-6.375,11.875,8.125,2.625)
    roof(loft,-9.125,10,3.375,2.75,10.75,2.625)
    -- Roof infill and vertical posts overlap the floor edges. Repaint all four
    -- horizontal beams last within the already solid grid: front/back/corners X,
    -- left/right Z. No collision cells are added.
    for _,band in ipairs(sideBands) do
        local x0,z0,x1,z1,level=table.unpack(band)
        loft:Box(x0-.125,level,z0-.125,x1+.125,level+.25,z0+.125,cedar)
        loft:Box(x0-.125,level,z1-.125,x1+.125,level+.25,z1+.125,cedar)
        loft:Box(x0-.125,level,z0+.125,x0+.125,level+.25,z1-.125,cedarBeamZ)
        loft:Box(x1-.125,level,z0+.125,x1+.125,level+.25,z1-.125,cedarBeamZ)
    end
    trimCovered(loft,old)
    trimCovered(b,old)
    trimCovered(b,loft)
    b:Finish({masonry='homeWindows'})
    loft:Finish({masonry='homeWindows'})
end
local function banks(world)
    local b=brush(world,{-21,-1.5,-19},{5,5,4},.25)
    local rng=Noise.Rng(8305)
    for i=0,71 do
        local a=i*math.pi/36;local x,z=-7.5+10.25*cos(a),-5.25+6.5*sin(a)
        if not channel(x,z) and not(abs(x+4)<1.75 and z>0) and not(x>0 and z>=-6.5 and z<=-3.75) then
            local rx,rz=rng:Range(.47,.95),rng:Range(.38,.78)
            local crest=rng:Int(0,2)*.25
            b:Ellipsoid(x,-.5,z,rx,crest+.55,rz,rng:Next()<.35 and P.STONE_MOSS or P.STONE_C)
        end
    end
    for i=0,16 do local z=2-i*.5
        b:Box(-5.5,.25,z-.375,-2.75,.5,z+.0625,i%4==1 and amber or oak)
    end
    for _,z in ipairs({1.5,-2.5,-5.75}) do for _,x in ipairs({-5.25,-3}) do
        b:Box(x-.25,-1.5,z-.25,x+.25,.875,z+.25,cedarPost)
    end end
    for _,p in ipairs({{-18,-7,2.75},{-14,-13,1.5},{2,-8,2.0},{4,2,3}}) do column(b,p[1],p[2],0,p[3]) end
    -- Terraced front parapet follows the pond lip, with an open spillway and stair entrance.
    for i=0,31 do
        local a=math.pi+i*math.pi/31
        local x,z=-7.5+11*cos(a),-5.25+7.5*sin(a)
        if not channel(x,z) then
            local broken=sin(a*5+.3)+.5*sin(a*9)<-.55
            local h=broken and .25 or (i%8==0 and 1.25 or .5)
            local wide=broken and .45 or .75
            b:Box(x-wide+.125,0,z-.375,x+wide-.125,h,z+.375,P.STONE_C)
            b:Box(x-wide,h,z-.5,x+wide,h+.25,z+.5,broken and P.STONE_MOSS or P.MARBLE_B)
        end
    end
    trimGround(b)
    -- The western edge of the launch paving crosses one surviving pond pillar.
    b:Shape(3,1.5,-6,21,1.75,12,function(x,_,z) if pad(x,z)<=8.55 then return false end end)
    b:Finish()
end
local function trees(world,scene)
    local foliage=require('ruins.RuinsTrees')
    local hidden=require('ruins.RuinsTerrain').HiddenMaterial()
    for i,p in ipairs({{-19.5,8,5.6,2.3},{-13,15,7.2,3},{-22.5,1,4,2},{3,13.25,5,2.4},{9,15,3,1.6},{20,-5,3.9,2.1},{-18,-10,3.2,1.7},{-2,-13.25,2.8,1.6}}) do
        local x,z,h,r=table.unpack(p)
        local y=H.Height(H.x+x,H.z+z)-H.base
        local trunk=brush(world,{x-.375,y,z-.375},{x+.375,y+h*.65,z+.375},.25)
        trunk:Box(x-.25,y,z-.25,x+.25,y+h*.65,z+.25,P.BARK)
        local collider=trunk:Finish()
        if hidden then collider.material=hidden end
        foliage.Tree(scene,nil,H.x+x,H.base+y,H.z+z,{h=h,r=r,trunk=.24+h*.022,gold=i==2,lean=.35+i%3*.18,leanA=i*2.4})
    end
end
local function water(scene)
    local node=scene:CreateChild('HomeSpring')
    node.position=Vector3(H.x,H.base,H.z)
    local g=node:CreateComponent('CustomGeometry')
    -- Both the pool and the waterfall are excluded from their own render target.
    g.viewMask=WATER_VIEW
    g:BeginGeometry(0,TRIANGLE_LIST)
    local function quad(a,b,c,d,fall)
        for _,v in ipairs({a,b,c,a,c,d}) do
            g:DefineVertex(v); g:DefineNormal(fall and Vector3(0,0,-1) or Vector3.UP)
            g:DefineTexCoord(Vector2(v.x,fall and v.y or v.z)); g:DefineColor(Color(fall and 1 or 0,0,0,1))
        end
    end
    for i=-37,9 do for k=-42,4 do
        local x,z=i*.5,k*.5
        if waterBed(x+.25,z+.25) then
            local h=WATER_LEVEL
            quad(Vector3(x,h,z),Vector3(x,h,z+.5),Vector3(x+.5,h,z+.5),Vector3(x+.5,h,z),false)
            if channel(x+.25,z+.25) and edge(x+.25,z-.25)<=0 then
                local low=-9.5-2*cos(x*3)
                quad(Vector3(x,h,z),Vector3(x+.5,h,z),Vector3(x+.5,low,z-.7),Vector3(x,low,z-.7),true)
            end
        end
    end end
    g:Commit()
    local mat=Material:new()
    if mat:SetSurfaceShader('Shaders/BLGL/HomeSpring.shader') then
        H.spring=mat
    else
        mat:SetTechnique(0,cache:GetResource('Technique','Techniques/PBR/PBRNoTextureAlpha.xml'))
        mat:SetShaderParameter('MatDiffColor',Variant(Color(.19,.62,.60,.76)))
    end
    g:SetMaterial(mat);g.castShadows=false
end
local function shoreDetails(world)
    local rng=Noise.Rng(9423)
    for sector=0,7 do
        local rocks={}
        local xmin,xmax,zmin,zmax=math.huge,-math.huge,math.huge,-math.huge
        local ymin,ymax=math.huge,-math.huge
        -- Short runs of adjacent slabs are separated by stretches of bare cliff.
        for _=1,rng:Int(2,4) do
            local center=(sector+rng:Range(.12,.88))*math.pi/4
            for j=0,rng:Int(1,3) do
                local a=center+j*.036
                local radius=1+.045*cos(5*a)+.032*sin(9*a)
                local x,z=26*radius*cos(a),19*radius*sin(a)
                if not (z< -6 and abs(x+11.75)<3.4) then
                    local y=top(x*.98,z*.98)
                    local low=rockFloor(x,z,0)
                    local rx,rz=rng:Range(.60,1.55),rng:Range(.55,1.35)
                    rocks[#rocks+1]={x=x,z=z,y=y,low=low,rx=rx,rz=rz}
                    xmin,xmax=math.min(xmin,x-rx),math.max(xmax,x+rx)
                    zmin,zmax=math.min(zmin,z-rz),math.max(zmax,z+rz)
                    ymin,ymax=math.min(ymin,low-.65,y-2),math.max(ymax,y+.30)
                end
            end
        end
        if #rocks>0 then
            local b=brush(world,{xmin,ymin,zmin},{xmax,ymax,zmax},.25)
            for _,r in ipairs(rocks) do
                local x,z=r.x,r.z
                local y=rng:Range(r.low+.4,r.y-.75)
                b:Ellipsoid(x,y,z,r.rx,rng:Range(.45,1.05),r.rz,rng:Next()<.32 and P.CLIFF_D or P.CLIFF_B)
                if rng:Next()<.42 then
                    local length=rng:Int(2,7)
                    for j=0,length do
                        local drift=j*.055
                        local w=.15+.22*(1-j/(length+1))
                        b:Box(x-w+drift,r.y-(j+1)*.25,z-w,x+w+drift,r.y-j*.25,z+w,j==length and P.LEAF_C or P.LEAF_A)
                    end
                end
            end
            trimGround(b)
            b:Finish({visual=true})
        end
    end
    -- Submerged steps at the eastern bank lead onto the lane. Each rise fits the capsule step height.
    local stairs=brush(world,{-1,-1.5,-7},{4,.75,-3},.25)
    for i=0,5 do stairs:Box(-1+i*.65,-1.5,-6.25,-.25+i*.65,-1.25+i*.25,-4,P.STONE_MOSS) end
    trimGround(stairs)
    stairs:Finish()
end
function H.GrassAt(wx,wz)
    local x,z=wx-H.x,wz-H.z
    if edge(x,z)<.65 or pool(x,z)<1.55 or pad(x,z)<9.2 or abs(x+11.75)<2.1 and z< -6 then return 0 end
    if x>-18 and x<3.5 and z>3 and z<13 or abs(x-4)<1.6 and abs(z)<11
        or x>8.5 and x<15.5 and z>-11 and z<2 or abs(z-4)<1.7 and x>-19 and x<9
        or (x-5)^2+(z+12)^2<1.7^2 then return 0 end
    local patch=pattern(x*.55,z*.55)+.3*pattern(x*1.3,z*1.3)
    return math.min(.95,math.max(.08,.55+.24*patch))
end

local function yieldBuild()
    if activeJob then coroutine.yield() end
end

local function meadowMaps(field)
    local cells,spacing=128,.5
    local height,coverage=Image:new(),Image:new()
    height:SetSize(cells+1,cells+1,3)
    coverage:SetSize(cells,cells,4)
    local previous={}
    for row=0,cells do
        if row%16==0 then yieldBuild() end
        -- Terrain vertices span [-32,32]. Each mask texel owns the quad between four vertices.
        local z=32-row*spacing
        local current={}
        for col=0,cells do
            local x=col*spacing-32
            local h=top(x,z)
            current[col]=h
            height:SetPixelInt(col,row,floor((h+2)*32))
            if row>0 and col>0 then
                local cx,cz=x-.25,z+.25
                local w=H.GrassAt(H.x+cx,H.z+cz)
                if w>0 and (h~=current[col-1] or h~=previous[col] or h~=previous[col-1]
                    or h~=top(cx-.125,cz-.125) or h~=top(cx+.125,cz-.125)
                    or h~=top(cx-.125,cz+.125) or h~=top(cx+.125,cz+.125)) then w=0 end
                coverage:SetPixelInt(col-1,row-1,floor(w*255+.5)<<24)
            end
        end
        previous=current
    end
    yieldBuild()
    local t=field.terrain
    t.patchSize=16
    t.spacing=Vector3(spacing,1/32,spacing)
    t.smoothing=false;t.heightMap=height
    -- The generated patches coincide with flat turf. Keep the height data for the
    -- sibling GrassFields, but omit the sampler mesh from all colour and shadow passes.
    t.visible=false;t.castShadows=false;t.viewMask=0;t.occluder=false
    local mask=Texture2D:new();mask:SetNumLevels(1);mask:SetData(coverage,true)
    mask:SetFilterMode(FILTER_NEAREST)
    mask:SetAddressMode(COORD_U,ADDRESS_CLAMP);mask:SetAddressMode(COORD_V,ADDRESS_CLAMP)
    field.splat=mask
end

local function meadow(scene)
    yieldBuild()
    local node=scene:CreateChild('HomeGrassHeight')
    node.position=Vector3(H.x,H.base-2,H.z)
    local field={x=H.x,z=H.z,grassExtent=30,terrainNode=node,GrassAt=H.GrassAt,Height=H.Height,HasGround=H.Ground}
    field.terrain=node:CreateComponent('Terrain')
    field.terrain.viewMask=0
    require('ruins.RuinsTerrain').BuildGrass(scene,field,meadowMaps,yieldBuild)
    if not field.grass then
        node:Remove()
        field.terrain,field.terrainNode,field.splat=nil,nil,nil
    end
    require('ruins.SceneQuality').ApplyGrass(field,require('ruins.GameSettings').GetProfile())
    H.field=field
end
function H.Build(world,scene,dayNight)
    for _,entry in ipairs({{oak,.54,.35,.19},{amber,.68,.46,.25},{cedar,.37,.24,.16},
        {slate,.24,.28,.30},{ember,.93,.32,.09},{flame,1,.73,.30},{window,.53,.36,.22},
        {cedarPost,.37,.24,.16},{oakPlankZ,.54,.35,.19},{cedarBeamZ,.37,.24,.16}}) do
        local id,r,g,b=table.unpack(entry)
        world:SetPaletteEntry(id,Color(r,g,b),50)
        local glow=Color(0,0,0,0)
        if id==ember or id==flame then glow=Color(r,g,b,id==flame and 1.6 or 1) end
        if id==window then glow=Color(1,.65,.30,1) end
        world:SetPaletteEntryPBR(id,id==window and .42 or .86,id==slate and .65 or 0,.4,glow)
    end
    terrain(world); courtyard(world); house(world); banks(world); trees(world,scene); meadow(scene); shoreDetails(world); water(scene)
    local fire=scene:CreateChild('HomeForgeFire'); fire.position=Vector3(H.x+1.15,H.base+1.65,H.z+7.5)
    local light=fire:CreateComponent('Light'); light.lightType=LIGHT_POINT
    light.color=Color(1,.53,.21); light.range=5; light.brightness=.78
    H.hearth=light
    if dayNight then H.Update(0,nil,dayNight) end
    world:OptimizeBroadPhase()
end
-- Build one bounded brush per update. Record only our volumes for interruption/retry.
function H.BeginBuild(world,scene,dayNight)
    local job={ids={},root=scene:CreateChild('HomeIslandScenery')}
    local thread=coroutine.create(function() H.Build(world,job.root,dayNight) end)
    function job:Cancel()
        if self.cancelled then return end
        self.cancelled=true
        thread=nil
        for i=world:GetVolumeCount()-1,0,-1 do
            local v=world:GetVolume(i)
            if v and self.ids[v:GetVolumeId()] then
                local node=v:GetNode()
                world:RemoveVolume(v)
                v:Dispose()
                if node then node:Dispose() end
            end
        end
        H.Stop()
        self.root:Remove()
    end
    function job:Step()
        if self.cancelled then return false,'home island build cancelled' end
        if not thread then return true end
        activeJob=self
        local ok,err=coroutine.resume(thread)
        activeJob=nil
        if not ok then self:Cancel();return false,err end
        if coroutine.status(thread)=='dead' then thread=nil;return true end
        return false
    end
    return job
end
return H
