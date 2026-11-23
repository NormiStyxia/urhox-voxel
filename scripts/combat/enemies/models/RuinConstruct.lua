-- Row four of the enemy concept sheet. Coordinates denote the minimum corner
-- of a root-space cell. Pivots are in metres and do not offset the cell data.
local Model = {}
local SIZE = 0.08
local SHALE, ASHLAR, BRONZE, GOLD, CYAN, FACET = 1, 2, 3, 4, 5, 6
local abs = math.abs

local function palette()
    return {
        {name='cut sandstone', rgb={158,132,112}, roughness=0.88, metallic=0, emission=0},
        {name='limestone face', rgb={211,185,155}, roughness=0.77, metallic=0, emission=0},
        {name='aged bronze', rgb={108,80,51}, roughness=0.58, metallic=0.71, emission=0},
        {name='worn gilt', rgb={221,165,76}, roughness=0.32, metallic=0.82, emission=0},
        {name='turquoise crystal', rgb={30,203,208}, roughness=0.27, metallic=0.03, emission=0.50},
        {name='cleaved crystal', rgb={147,250,237}, roughness=0.18, metallic=0.03, emission=0.84},
    }
end

-- Each classifier owns one part. A cell gets exactly one surface, including
-- inlaid lines and worn lips, so overlays never create coincident geometry.
local function sample(parts, name, pivot, bounds, shape)
    local cells = {}
    for y=bounds[3],bounds[4] do
        for z=bounds[5],bounds[6] do
            for x=bounds[1],bounds[2] do
                local color = shape(x,y,z)
                if color then cells[#cells+1] = {x,y,z,color} end
            end
        end
    end
    parts[#parts+1] = {id=name, pivot=pivot, cells=cells}
end

-- Horizontal mortised crown. The front clasp bridges the two front stones.
local function crown(x,y,z)
    local u, v = abs(x+0.5), abs(z)
    local edge = y==27
    local outer = (u/(edge and 6.7 or 7.1))^2 + (v/(edge and 4.1 or 4.5))^2
    if outer>1 or (u/4.5)^2+(v/2.5)^2<1 then return end
    if z>=2 and u<2 then
        if u<1 then return CYAN end
        return y==27 and BRONZE or GOLD
    end
    -- Short radial joints separate ashlar courses without a noise texture.
    if (u==5.5 and z>=1 and y<29) or (x==-3 and z<0 and y>=28) then return SHALE end
    return y>=28 and ASHLAR or SHALE
end

local function chest(x,y,z)
    local u, v = abs(x+0.5), abs(z+0.5)
    -- The rear slab terminates at -Z. Engrave a square-headed key on it.
    if z<=-3 and u<=4.5 and y>=14 and y<=21 then
        if u==4.5 and (y==14 or y==21) then return end
        if z==-5 then
            if (y==19 or y==18) and u<2 then return (u<1 and y==18) and SHALE or CYAN end
            if y>=15 and y<=17 and u<1 then return CYAN end
        end
        return y>=20 and ASHLAR or SHALE
    end
    -- Top and bottom gold seats clasp the window; set the outer lip proud.
    if (y<=13 or y>=22) and u<=4.5 and v<=3.5 then
        if u+v>7 or ((y==12 or y==23) and u>3.5) then return end
        if z>=2 or (y==23 and u<3) then return GOLD end
        return BRONZE
    end
    -- Side voussoirs: broad faces, clipped outer corners and a recessed bed
    -- joint on the lower course. The center remains open toward the viewer.
    if y>=13 and y<=22 and u>=3.5 and u<=7.5 and v<=3.5 then
        if u+v>10 or (u>5.5 and y<=19) or (u>6.5 and y>=21) then return end
        if y==16 and (u==5.5 or z==3) then return end
        if u==3.5 and z>=1 then return y>=20 and ASHLAR or SHALE end
        if y>=20 or (y==15 and z>=0) or (u>=6.5 and z>=1 and y>=18) then return ASHLAR end
        return SHALE
    end
end

-- Convex octahedron with one lighter cleavage plane. Its front apex projects
-- past the chest bezel, so it also reads as a crystal in profile.
local function core(x,y,z)
    local dx,dy,dz = x+0.5, y-17.5, z-1.5
    if abs(dx)/3.8+abs(dy)/5.2+abs(dz)/3.4>1 then return end
    if dx>=0 and dy>=0 and dz>=0 then return FACET end
    if dy>=3 and dz<0 then return FACET end
    return CYAN
end

local function neck(x,y,z)
    local u,v=abs(x+0.5),abs(z+0.5)
    if y==24 and u+v<=3 then return GOLD end
    if u<1 and v<1 then return x==0 and FACET or CYAN end
end

local function base(x,y,z)
    local u,v=abs(x+0.5),abs(z+0.5)
    if y==3 and u<1 and v<1 then return BRONZE end
    if y==4 and u+v<=2 then return CYAN end
    if y==5 and u<2 and v<2 then return FACET end
    if y>=6 and y<=9 then
        local width = (y==6 and 3) or (y==7 and 4) or 6
        if u>=width or v>=3 or u+v>width+1 then return end
        if u<2 and z>=1 then return y==6 and BRONZE or GOLD end
        return y==9 and ASHLAR or SHALE
    end
    if y>=10 and y<=11 and u<2 and v<2 then return y==11 and BRONZE or GOLD end
end

-- Nine courses from toe to cuff. The hammer steps outward and forward.
local armRows = {
    -- centre X, half-width, centre Z, half-depth, course, rune X
    {11,2,1,2,GOLD,11.5},   {10.5,2.5,0.5,2.5,SHALE,11.5},
    {10,3,0,3,SHALE,11.5},  {10,3,0,3,ASHLAR,10.5},
    {10,3,0,3,ASHLAR,9.5},  {9.5,2.5,-0.5,2.5,SHALE,9.5},
    {9,2,-1,2,ASHLAR,9.5},  {9.5,2.5,-0.5,2.5,BRONZE},
    {9.5,2.5,-0.5,2.5,GOLD},
}

local function arm(u,y,z)
    local row = armRows[y-9]
    local dx,dz = u-row[1], z+0.5-row[3]
    local width,depth,color = row[2],row[4],row[5]
    if abs(dx)>=width or abs(dz)>=depth or abs(dx)+abs(dz)>width+depth-2 then return end
    -- The stepped rune is cut into both visible faces. Its lower return
    -- runs round the chamfer, which carries the stroke into the side view.
    local isRune = u==row[6] or (y==13 and u==11.5) or (y==14 and u==10.5)
    if isRune and abs(dz)==depth-0.5 then return CYAN end
    if y==12 and dx>=1.5 and dx+dz>=width+depth-2 then return CYAN end
    if color==GOLD and dx<0 and dz<0 then return BRONZE end
    return color
end

local function satellite(u,y,z)
    local dx,dz=abs(u-11),abs(z+0.5)
    if y==22 then
        if dx<1 and dz<1 then return CYAN end
    elseif dx<2 and dz<2 and dx+dz<3 then
        return y==23 and SHALE or ASHLAR
    end
end

function Model.Build()
    local parts = {}
    sample(parts,'torso',{0,1.44,0},{-8,7,12,23,-5,3},chest)
    sample(parts,'core',{0,1.44,0.16},{-4,3,13,22,-1,4},core)
    sample(parts,'neck',{0,2.0,0},{-3,2,24,26,-3,2},neck)
    sample(parts,'crown',{0,2.28,0.04},{-7,6,27,29,-4,4},crown)
    sample(parts,'lower_body',{0,0.84,0},{-6,5,3,11,-3,2},base)
    for _,side in ipairs({{1,'r'},{-1,'l'}}) do
        local sign,suffix=side[1],side[2]
        local x0,x1 = sign==1 and 7 or -13, sign==1 and 12 or -8
        sample(parts,'arm_'..suffix,{sign*0.80,1.44,0},{x0,x1,10,18,-3,2},function(x,y,z)
            return arm(sign*(x+0.5),y,z)
        end)
        sample(parts,'satellite_'..suffix,{sign*0.88,1.96,0},{x0,x1,22,25,-2,1},function(x,y,z)
            return satellite(sign*(x+0.5),y,z)
        end)
    end
    return {size=SIZE,palette=palette(),parts=parts}
end

return Model
