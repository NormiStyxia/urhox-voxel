local WHITE,BLUE,GOLD,GEM={1,0,0},{.65,0,.35},{0,1,0},{0,0,1}
local function Face(data,points,weights,shade,glow,outward)
    local a,b,c=points[1],points[2],points[3]
    local ux,uy,uz=b[1]-a[1],b[2]-a[2],b[3]-a[3]
    local vx,vy,vz=c[1]-a[1],c[2]-a[2],c[3]-a[3]
    local nx,ny,nz=uy*vz-uz*vy,uz*vx-ux*vz,ux*vy-uy*vx
    local length=math.sqrt(nx*nx+ny*ny+nz*nz)
    if length<1e-10 then return end
    local flip=nx*outward[1]+ny*outward[2]+nz*outward[3]<0
    if flip then length=-length end
    local normal={nx/length,ny/length,nz/length}
    for i=2,#points-1 do
        local tri=flip and {points[1],points[i+1],points[i]} or {points[1],points[i],points[i+1]}
        for _,p in ipairs(tri) do
            data.vertices[#data.vertices+1]={p=p,n=normal,c=weights,shade=shade or 1,glow=glow or 0}
            for axis=1,3 do
                data.bounds.min[axis]=math.min(data.bounds.min[axis],p[axis])
                data.bounds.max[axis]=math.max(data.bounds.max[axis],p[axis])
            end
        end
    end
end
local function Prism(data,poly,z0,z1,weights,shade,glow)
    local front,back={},{}
    local cx,cy=0,0
    for i,p in ipairs(poly) do
        front[i]={p[1],p[2],z0};back[i]={p[1],p[2],z1}
        cx=cx+p[1]/#poly;cy=cy+p[2]/#poly
    end
    Face(data,front,weights,shade,glow,{0,0,-1})
    Face(data,back,weights,shade,glow,{0,0,1})
    for i=1,#poly do
        local k=i%#poly+1
        Face(data,{front[i],front[k],back[k],back[i]},weights,shade,glow,
            {(poly[i][1]+poly[k][1])*.5-cx,(poly[i][2]+poly[k][2])*.5-cy,0})
    end
end
local function Box(data,x0,y0,z0,x1,y1,z1,weights,shade,glow)
    data.boxes[#data.boxes+1]={from={x0,y0,z0},to={x1,y1,z1},weights=weights,shade=shade or 1,glow=glow or 0}
    Prism(data,{{x0,y0},{x1,y0},{x1,y1},{x0,y1}},z0,z1,weights,shade,glow)
end
local function Faceted(data)
    -- Six broad planes per side, no texture noise. End ring collapses to a point.
    local rings={}
    for _,r in ipairs({{.16,.072,.028},{.30,.12,.034},{1.34,.105,.029},{1.70,0,0}}) do
        local y,w,d=r[1],r[2],r[3]
        rings[#rings+1]={{-w,y,0},{-.64*w,y,-d},{0,y,-d*1.15},{.64*w,y,-d},
            {w,y,0},{.64*w,y,d},{0,y,d*1.15},{-.64*w,y,d}}
    end
    Face(data,rings[1],WHITE,.8,0,{0,-1,0})
    for j=1,#rings-1 do for i=1,8 do
        local k=i%8+1
        local a,b,c,d=rings[j][i],rings[j][k],rings[j+1][k],rings[j+1][i]
        local pts=j==#rings-1 and {a,b,c} or {a,b,c,d}
        Face(data,pts,(i==2 or i==6) and BLUE or WHITE,(i==1 or i==5) and 1 or .93,0,
            {(a[1]+b[1])*.5,0,(a[3]+b[3])*.5})
    end end
    Box(data,-.025,0,-.018,.025,.18,.018,GOLD,.68)
    -- Angular gold root/collar and two restrained rising gold inlays, both sides.
    for _,sign in ipairs({-1,1}) do
        local z0,z1=sign*.015,sign*.045
        if z0>z1 then z0,z1=z1,z0 end
        Prism(data,{{-.07,.16},{.07,.16},{.105,.27},{0,.40},{-.105,.27}},z0,z1,GOLD,1)
        for _,side in ipairs({-1,1}) do
            Prism(data,{{side*.042,.35},{side*.058,.35},{side*.084,.62},{side*.068,.57}},
                z0,z1,GOLD,.9)
        end
        -- Low octahedral sapphire with four planar highlights.
        local rim={{-.042,.27,sign*.045},{0,.20,sign*.045},{.042,.27,sign*.045},{0,.35,sign*.045}}
        local peak={0,.27,sign*.075}
        for i=1,4 do Face(data,{rim[i],rim[i%4+1],peak},GEM,.7+i*.07,1,{0,0,sign}) end
        Prism(data,{{-.010,.40},{.010,.40},{.007,1.25},{0,1.34},{-.007,1.25}},
            math.min(sign*.018,sign*.042),math.max(sign*.018,sign*.042),GEM,.8,.3)
    end
end
local function Cubes(data)
    -- Blockbench-style non-rotated cuboids on a 1cm grid. One unit = 0.01m.
    local function Cube(x,y,z,w,h,d,c,shade,glow)
        Box(data,x*.01,y*.01,z*.01,(x+w)*.01,(y+h)*.01,(z+d)*.01,c,shade,glow)
    end
    Cube(-2,0,-2,4,18,4,GOLD,.68)
    -- Broad long blocks, then five deliberate steps into the tip.
    for _,r in ipairs({{-8,16,16,12},{-12,28,24,88},{-11,116,22,20},{-9,136,18,10},
        {-7,146,14,8},{-5,154,10,6},{-3,160,6,6},{-1,166,2,4}}) do
        Cube(r[1],r[2],-2,r[3],r[4],4,WHITE,1)
    end
    for _,sign in ipairs({-1,1}) do
        local z=sign<0 and -3 or 2
        Cube(-8,28,z,6,88,1,BLUE,.94)
        Cube(2,28,z,6,88,1,WHITE,.91)
        Cube(-2,39,z,4,92,1,GEM,.72,.35)
        -- Two stepped prongs, a small gold bezel, and raised cubic sapphire.
        local goldZ=sign<0 and -4 or 2
        Cube(-6,16,goldZ,12,5,2,GOLD,1)
        Cube(-9,21,goldZ,18,12,2,GOLD,.95)
        Cube(-6,33,goldZ,12,6,2,GOLD,.95)
        for _,x in ipairs({-7,5}) do Cube(x,39,goldZ,2,14,2,GOLD,1) end
        for _,x in ipairs({-9,7}) do Cube(x,53,goldZ,2,8,2,GOLD,.9) end
        Cube(-3,23,sign<0 and -6 or 4,6,9,2,GEM,.9,1)
        Cube(-2,24,sign<0 and -7 or 6,4,6,1,GEM,1,1)
    end
end
local M = {}
function M.Data(route)
    assert(route == 'A' or route == 'B')
    local data={route=route,vertices={},boxes={},displayHeight=1.7,
        bounds={min={math.huge,math.huge,math.huge},max={-math.huge,-math.huge,-math.huge}},
        sockets={root={0,0,0},top={0,1.7,0}},uvBase=0,uvHeight=1.7}
    if route=='A' then Faceted(data) else Cubes(data) end
    data.triangles=#data.vertices/3
    return data
end
return M
