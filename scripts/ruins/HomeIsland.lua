-- Positions below are in island-local metres, looking north from the waterfall.
local Brush = require('ruins.VoxelBrush')
local P = require('ruins.RuinsPalette').P
local H = { x = 720, z = 0, base = 6 }
local abs, floor, sin, cos, sqrt = math.abs, math.floor, math.sin, math.cos, math.sqrt
local oak, amber, cedar, slate, ember, flame = 150,151,152,153,154,155
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
    if channel(x,z) then return -1.5 end
    local basin=pool(x,z)
    if basin<1 then return -.75-.25*floor(4*(1-basin)) end
    if pad(x,z)<8.8 then return 1.5 end
    if x>9 and x<15 and z<0 then return math.max(0,math.min(1.5,floor((z+10)*1.3)*.25)) end
    local bank=1-((x+6)/15)^2-((z-17)/4)^2
    return .5*floor(4*math.max(0,bank))
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
local function brush(world,lo,hi,s)
    if activeJob then coroutine.yield() end
    local b=Brush.New(world,{origin=Vector3(H.x,H.base,H.z),min=lo,max=hi,size=s})
    if activeJob then activeJob.ids[b.volume:GetVolumeId()]=true end
    return b
end
local function terrain(world)
    local rocks={P.DEEP_A,P.CLIFF_C,P.CLIFF_B,P.CLIFF_A}
    -- Column fills keep broad rock strata continuous across neighbouring voxels.
    for bx=-28,14,14 do for bz=-21,7,14 do
        local b=brush(world,{bx,-18,bz},{bx+14,2,bz+14},.5)
        for i=0,b.nx-1 do for k=0,b.nz-1 do
            local x,z=bx+(i+.5)*.5,bz+(k+.5)*.5
            local d=edge(x,z)
            if d>0 then
                local low=-2-math.min(15,d*1.7)-2.6*pattern(floor(x/2.5),floor(z/2.5))
                local h=top(x,z)
                local y=math.max(-18,math.min(floor(low*2)/2,h-1.0))
                while y<h-.5 do
                    local nextY=math.min(h-.5,y+2)
                    local band=math.max(1,math.min(4,4+floor(y*.20+.9*pattern(floor(x/2)*.6,floor(z/2)*.6))))
                    b:Box(x-.25,y,z-.25,x+.25,nextY,z+.25,rocks[band]); y=nextY
                end
                local shade=pattern(x*.65,z*.65)
                local mat=shade>1 and P.GRASS_B or (shade<-.8 and P.GRASS_C or P.GRASS_A)
                if h<0 then mat=shade>0 and P.SAND or P.STONE_MOSS
                elseif pad(x,z)<8.85 or (x>9 and x<15 and z>-10 and z<0) then mat=P.STONE_B
                elseif pool(x,z)<1.22 or abs(z-4)<1.35 and x<8 and x>-18 or abs(x-4)<1.3 and abs(z)<10 then mat=shade>0 and P.PATH or P.PATH_B end
                b:Box(x-.25,h-.5,z-.25,x+.25,h,z+.25,mat)
            end
        end end
        b:Finish({masonry='meadow'})
    end end
end
local function column(b,x,z,y,h)
    b:Box(x-.75,y,z-.75,x+.75,y+.5,z+.75,P.STONE_C)
    b:Box(x-.5,y+.5,z-.5,x+.5,y+h,z+.5,P.MARBLE_B)
    b:Box(x-.125,y+.9,z-.625,x+.125,y+h-.35,z-.5,P.MARBLE_BLUE)
    b:Box(x-.625,y+h-.5,z-.625,x+.625,y+h-.25,z+.625,P.GOLD_DARK)
    b:Box(x-.75,y+h-.25,z-.75,x+.75,y+h+.25,z+.75,P.MARBLE_A)
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
        if i~=9 and i~=6 then column(b,12+8.3*cos(a),3+8.3*sin(a),1.5,i%4==1 and 2.75 or 1.25) end
    end
    b:Finish({masonry='floor'})
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
local function house(world)
    local old=brush(world,{-22,0,6},{5,12,17},.25)
    arch(old,-9.5,13.5,6,5,5.25); arch(old,-18,9,2.8,3.25,3.1)
    for _,p in ipairs({{-20,6,5.25},{2.5,11.5,6},{-1,15,4.5}}) do column(old,p[1],p[2],0,p[3]) end
    old:Finish({masonry='ashlar'})
    local b=brush(world,{-18,0,3},{4,9,14},.125)
    b:Box(-16.25,0,4,-1,.375,12,P.STONE_C)
    b:Box(-16,.375,7,-1.5,4.25,12,P.STONE_B)
    b:Box(-15.75,.5,7.375,-1.875,4,11.625,false)
    b:Carve(-10,.375,6.875,-8,3.25,7.5)
    for i=0,39 do b:Box(-16+i*.375,.375,4,-15.6375+i*.375,.5,7.375,i%7==2 and oak or P.WOOD) end
    for _,x in ipairs({-15.5,-12.25,-7,-2}) do
        b:Box(x-.1875,.5,4.25,x+.1875,3.25,4.625,cedar)
        b:Box(x-.375,2.875,4.125,x+.375,3.375,4.75,oak)
        b:Box(x-.125,2.5,4.75,x+.125,3,5,P.GOLD_DARK)
        b:Box(x-.25,2.125,4.75,x+.25,2.5,5.25,flame)
    end
    for _,x in ipairs({-14,-5.5,-3}) do
        b:Box(x-1,1.25,6.75,x+1,3.25,7,cedar)
        b:Box(x-.75,1.5,6.625,x+.75,3,6.75,flame)
        b:Box(x-.125,1.5,6.5,x+.125,3,6.625,oak)
        b:Box(x-.75,2.125,6.5,x+.75,2.25,6.625,oak)
    end
    roof(b,-14.5,9.5,2.875,3.375,4.15,2.5)
    roof(b,-3.5,9.75,3.25,3.25,4.0,1.75)
    roof(b,-9,5.75,7.75,2,3.2,1)
    -- A cross-gable dormer faces the pond. Its lit window breaks the long roof slope.
    b:Box(-9.75,4.5,6.65,-6.75,6.25,9.5,cedar)
    b:Box(-9.25,4.875,6.5,-7.25,6,6.75,flame)
    b:Box(-8.375,4.875,6.375,-8.125,6,6.5,P.WOOD)
    for row=0,14 do
        local x=row*.125;local y=7.5-row*.10
        for _,sign in ipairs({-1,1}) do
            local at=-8.25+x*sign
            b:Box(at-.125,y-.25,6.125,at+.125,y,9.875,row%4==2 and amber or oak)
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
    b:Finish()
    -- Upper rooms step back from the forge and the low pond-facing porch.
    local loft=brush(world,{-14,4,5.5},{-4,14,13.75},.125)
    local function storey(x0,z0,x1,z1,y,h)
        loft:Box(x0,y,z0,x1,y+h,z1,P.MARBLE_B)
        loft:Carve(x0+.25,y+.25,z0+.25,x1-.25,y+h,z1-.25)
        for _,level in ipairs({y,y+h-.25}) do
            loft:Box(x0-.125,level,z0-.125,x1+.125,level+.25,z1+.125,cedar)
        end
        for _,x in ipairs({x0,(x0+x1)/2,x1-.25}) do
            loft:Box(x,y,z0-.125,x+.25,y+h,z0+.125,cedar)
        end
        for _,x in ipairs({x0+.875,x1-1.75}) do
            loft:Box(x-.125,y+.625,z0-.25,x+.875,y+2,z0,oak)
            loft:Box(x,y+.875,z0-.375,x+.75,y+1.875,z0-.25,flame)
            loft:Box(x+.25,y+.875,z0-.5,x+.375,y+1.875,z0-.375,cedar)
        end
    end
    storey(-12.75,7,-5.25,12,4,3)
    roof(loft,-9,9.5,4.375,3.375,7,2)
    storey(-11.875,8.125,-6.375,11.875,8.125,2.625)
    roof(loft,-9.125,10,3.375,2.75,10.75,2.625)
    loft:Finish()
end
local function banks(world)
    local b=brush(world,{-21,-1.5,-19},{5,5,4},.25)
    for i=0,71 do
        local a=i*math.pi/36;local x,z=-7.5+10.25*cos(a),-5.25+6.5*sin(a)
        if not channel(x,z) and not(abs(x+4)<1.75 and z>0) and not(x>0 and z>=-6.5 and z<=-3.75) then
            b:Box(x-.65,-1.5,z-.5,x+.65,.25,z+.5,i%5==1 and P.STONE_MOSS or P.STONE_B)
        end
    end
    for i=0,16 do local z=2-i*.5
        b:Box(-5.5,.25,z-.375,-2.75,.5,z+.0625,i%4==1 and amber or oak)
    end
    for _,z in ipairs({1.5,-2.5,-5.75}) do for _,x in ipairs({-5.25,-3}) do
        b:Box(x-.25,-1.5,z-.25,x+.25,.875,z+.25,cedar)
    end end
    for _,p in ipairs({{-18,-7,2.75},{-14,-13,1.5},{2,-8,2.0},{4,2,3}}) do column(b,p[1],p[2],0,p[3]) end
    -- Terraced front parapet follows the pond lip, with an open spillway and stair entrance.
    for i=0,31 do
        local a=math.pi+i*math.pi/31
        local x,z=-7.5+11*cos(a),-5.25+7.5*sin(a)
        if not channel(x,z) then
            local h=i%8==0 and 1.25 or .625
            b:Box(x-.625,0,z-.375,x+.625,h,z+.375,P.STONE_C)
            b:Box(x-.75,h,z-.5,x+.75,h+.25,z+.5,i%6==0 and P.STONE_MOSS or P.MARBLE_B)
        end
    end
    b:Finish()
end
local function trees(world)
    for index,p in ipairs({{-16,10,6},{-11,14,7.5},{-21,4,4.5},{-21,-3,3.75},{2,13,5},{7,14,3.75},{19,-5,3},{-17,-10,2.5},{0,-13,2.25}}) do
        local x,z,h=p[1],p[2],p[3];local b=brush(world,{x-4,0,z-4},{x+4,h+3,z+4},.25)
        b:Box(x-.375,0,z-.375,x+.375,h-.5,z+.375,P.BARK)
        for j=0,6 do
            local a=j*2.4+index;local cx,cz=x+cos(a)*1.85,z+sin(a)*1.85
            local cy=h-1+j*.40;local r=1.8-j*.09
            b:Box(math.min(x,cx)-.25,cy-1.25,math.min(z,cz)-.25,math.max(x,cx)+.25,cy-.75,math.max(z,cz)+.25,P.BARK)
            b:Shape(cx-r,cy-1,cz-r,cx+r,cy+1.15,cz+r,function(px,y,pz)
                local u,v=abs(px-cx)/r,abs(pz-cz)/r
                if u*u+v*v+((y-cy)/1.2)^2<1 then
                    if index==2 then return y>cy and P.LEAF_GOLD or P.LEAF_GOLD_B end
                    return y>cy+.25 and P.LEAF_B or (y<cy-.35 and P.LEAF_C or P.LEAF_A)
                end
            end)
        end
        b:Finish()
    end
end
local function water(scene)
    local node=scene:CreateChild('HomeSpring')
    node.position=Vector3(H.x,H.base,H.z)
    local g=node:CreateComponent('CustomGeometry')
    g:BeginGeometry(0,TRIANGLE_LIST)
    local function quad(a,b,c,d,fall)
        for _,v in ipairs({a,b,c,a,c,d}) do
            g:DefineVertex(v); g:DefineNormal(fall and Vector3(0,0,-1) or Vector3.UP)
            g:DefineTexCoord(Vector2(v.x,fall and v.y or v.z)); g:DefineColor(Color(fall and 1 or 0,0,0,1))
        end
    end
    for i=-37,9 do for k=-42,4 do
        local x,z=i*.5,k*.5
        if top(x+.25,z+.25)<0 and edge(x+.25,z+.25)>0 then
            local h=-.375
            quad(Vector3(x,h,z),Vector3(x,h,z+.5),Vector3(x+.5,h,z+.5),Vector3(x+.5,h,z),false)
            if channel(x+.25,z+.25) and edge(x+.25,z-.25)<=0 then
                local low=-9.5-2*cos(x*3)
                quad(Vector3(x,h,z),Vector3(x+.5,h,z),Vector3(x+.5,low,z-.7),Vector3(x,low,z-.7),true)
            end
        end
    end end
    g:Commit()
    local mat=Material:new()
    if not mat:SetSurfaceShader('Shaders/BLGL/HomeSpring.shader') then
        mat:SetTechnique(0,cache:GetResource('Technique','Techniques/PBR/PBRNoTextureAlpha.xml'))
        mat:SetShaderParameter('MatDiffColor',Variant(Color(.19,.62,.60,.76)))
    end
    g:SetMaterial(mat);g.castShadows=false
end
local function shoreDetails(world)
    local b=brush(world,{-26,-6,-21},{27,2,20},.25)
    -- Exposed masonry, ledges and trailing ivy follow the cliff face rather than the flat turf.
    for i=0,66 do
        local a=i*2*math.pi/67
        local radius=1+.045*cos(5*a)+.032*sin(9*a)
        local x,z=26*radius*cos(a),19*radius*sin(a)
        if not channel(x,z) then
            local y=-.75-(i%4)*.625
            b:Box(x-1,y-.75,z-.75,x+1,y+.25,z+.75,i%3==0 and P.CLIFF_D or P.CLIFF_B)
            if i%3~=0 then
                local ix,iz=x*.958,z*.958
                b:Box(ix-.75,-.5,iz-.75,ix+.75,.25,iz+.75,P.GRASS_C)
                b:Box(x-.5,y-.5,z-.375,x+.5,-.25,z+.375,P.LEAF_A)
                b:Box(x-.25,y-1,z-.25,x+.25,y-.5,z+.25,P.LEAF_C)
            end
        end
    end
    b:Finish({visual=true})
    -- Submerged steps at the eastern bank lead onto the lane. Each rise fits the capsule step height.
    local stairs=brush(world,{-1,-1.5,-7},{4,.75,-3},.25)
    for i=0,5 do stairs:Box(-1+i*.65,-1.5,-6.25,-.25+i*.65,-1.25+i*.25,-4,P.STONE_MOSS) end
    stairs:Finish()
end
local function garden(world)
    -- Groups share a single brush per border patch. The path and launch approach stay clear.
    for _,p in ipairs({{-19,-6},{-15,-12},{-4,-14},{1,-11},{6,-7},{20,4},{6,11},{-17,4}}) do
        local cx,cz=p[1],p[2]
        local b=brush(world,{cx-3,0,cz-2},{cx+3,1.75,cz+2},.125)
        for n=1,28 do
            local x=cx+2.4*sin(n*2.4);local z=cz+1.5*cos(n*1.7)
            if edge(x,z)>0 and top(x,z)==0 and pool(x,z)>1.2 then
                local h=.25+n%4*.125
                b:Box(x-.25,0,z-.25,x+.25,h,z+.25,n%3==0 and P.LEAF_C or P.LEAF_A)
                b:Box(x-.125,h,z-.125,x+.125,h+.125,z+.125,n%7==1 and P.FLOWER_W or P.LEAF_B)
            end
        end
        b:Finish({visual=true})
    end
end
function H.Build(world,scene)
    for _,entry in ipairs({{oak,.54,.35,.19},{amber,.68,.46,.25},{cedar,.37,.24,.16},
        {slate,.24,.28,.30},{ember,.93,.32,.09},{flame,1,.73,.30}}) do
        local id,r,g,b=table.unpack(entry)
        world:SetPaletteEntry(id,Color(r,g,b),50)
        world:SetPaletteEntryPBR(id,.86,id==slate and .65 or 0,.4,
            id>=ember and Color(r,g,b,id==flame and 1.6 or 1) or Color(0,0,0,0))
    end
    terrain(world); courtyard(world); house(world); banks(world); trees(world); garden(world); shoreDetails(world); water(scene)
    local fire=scene:CreateChild('HomeForgeFire'); fire.position=Vector3(H.x+1.15,H.base+1.65,H.z+7.5)
    local light=fire:CreateComponent('Light'); light.lightType=LIGHT_POINT
    light.color=Color(1,.53,.21); light.range=7; light.brightness=1.35
    world:OptimizeBroadPhase()
end
-- Build one bounded brush per update. Record only our volumes for interruption/retry.
function H.BeginBuild(world,scene)
    local job={ids={},root=scene:CreateChild('HomeIslandScenery')}
    local thread=coroutine.create(function() H.Build(world,job.root) end)
    function job:Cancel()
        for i=world:GetVolumeCount()-1,0,-1 do
            local v=world:GetVolume(i)
            if v and self.ids[v:GetVolumeId()] then world:RemoveVolume(v) end
        end
        self.root:Remove()
    end
    function job:Step()
        activeJob=self
        local ok,err=coroutine.resume(thread)
        activeJob=nil
        if not ok then self:Cancel();return false,err end
        return coroutine.status(thread)=='dead'
    end
    return job
end
return H
