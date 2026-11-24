local NestWeaver = {}
local SIZE = 0.08
local CUTICLE, PLUM, BAST, FLAX, AMBER, SILK = 1, 2, 3, 4, 5, 6

-- Sections run from the pointed tail to the shoulders. Each row gives the
-- cross-section's z, half-span, ridge height and free outer edge height.
local wingSections = {
    {-10, 1.4, 4.8, 4.6}, {-9, 4.5, 6.4, 4.5}, {-7, 7.5, 9.1, 4.8},
    {-4, 10.1, 11.4, 5.2}, {0, 11.7, 12.1, 5.8}, {3, 11.2, 12.8, 6.4},
    {5, 9.2, 12.4, 7.5}, {6, 6.3, 11.7, 8.9},
}

-- Points in the appendage paths are cell-space positions with a radius.
local legs = {
    {"front", {{3.0,5.2,4.6,1.35}, {4.2,5.4,7.3,1.55}, {3.2,3.5,9.4,1.25},
        {2.1,1.3,10.0,0.82}, {1.8,0.7,9.2,0.75}}},
    {"middle", {{3.3,5.4,1.3,1.15}, {6.2,4.4,2.6,1.15}, {7.4,2.0,4.0,1.02},
        {7.8,0.7,4.4,0.88}}},
    {"rear", {{3.1,4.8,-2.5,1.2}, {5.3,4.3,-3.5,1.21}, {5.8,2.7,-5.2,1.05},
        {6.4,0.7,-7.2,0.95}}},
}
local feeler = {{1.5,11.4,6.5,0.83}, {2.0,14.4,6.7,0.71}, {3.8,16.0,6.2,0.87},
    {5.0,15.4,6.0,0.95}}

function NestWeaver.Build()
    local palette = {
        {name="Cuticle", rgb={71,48,47}, roughness=0.70, metallic=0, emission=0},
        {name="Plum elytron", rgb={120,78,91}, roughness=0.28, metallic=0.04, emission=0},
        {name="Raw bast", rgb={177,151,78}, roughness=0.97, metallic=0, emission=0},
        {name="Combed flax", rgb={234,211,147}, roughness=0.93, metallic=0, emission=0},
        {name="Amber", rgb={252,169,43}, roughness=0.37, metallic=0, emission=0.14},
        {name="Silk membrane", rgb={241,225,184}, roughness=0.52, metallic=0, emission=0},
    }
    local parts, occupied = {}, {}
    local function part(id, x, y, z)
        local p = {id=id, pivot={x*SIZE,y*SIZE,z*SIZE}, cells={}}
        parts[#parts+1] = p
        return p
    end
    -- Scan cell centres. First surface owns a shared joint cell. The packed
    -- key spans 256 cells per axis, comfortably beyond this model's bounds.
    local function stamp(p, xmin, xmax, ymin, ymax, zmin, zmax, sample)
        for z=math.floor(zmin),math.ceil(zmax)-1 do
            for y=math.max(0,math.floor(ymin)),math.ceil(ymax)-1 do
                for x=math.floor(xmin),math.ceil(xmax)-1 do
                    local key = (z*256 + y)*256 + x
                    if not occupied[key] then
                        local mat = sample(x+0.5,y+0.5,z+0.5)
                        if mat then
                            p.cells[#p.cells+1] = {x,y,z,mat}
                            occupied[key] = true
                        end
                    end
                end
            end
        end
    end
    local function stroke(p, side, path, colors)
        for i=1,#path-1 do
            local a,b = path[i],path[i+1]
            local ax,bx = side*a[1],side*b[1]
            local dx,dy,dz = bx-ax,b[2]-a[2],b[3]-a[3]
            local len2 = dx*dx+dy*dy+dz*dz
            local r = math.max(a[4],b[4])
            stamp(p,math.min(ax,bx)-r,math.max(ax,bx)+r,math.min(a[2],b[2])-r,math.max(a[2],b[2])+r,
                math.min(a[3],b[3])-r,math.max(a[3],b[3])+r,function(x,y,z)
                    local u,v,w = x-ax,y-a[2],z-a[3]
                    local t = math.max(0,math.min(1,(u*dx+v*dy+w*dz)/len2))
                    local radius = a[4] + t*(b[4]-a[4])
                    if (u-t*dx)^2+(v-t*dy)^2+(w-t*dz)^2 <= radius^2 then return colors[i] end
                end)
        end
    end

    for _,side in ipairs({-1,1}) do
        local suffix = side==1 and "_r" or "_l"
        -- One continuous flight membrane. The stiff leading spar sweeps back to
        -- a tapered tip; three darker veins branch into the scalloped fan.
        local wing = part("wing"..suffix,side*3.5,9.5,1.5)
        stamp(wing,-26,26,9,10,-16,3,function(x,_,z)
            local span=side*x-3.5
            if span<0 or span>22 then return end
            local t=span/22
            local leading=2.8-3.9*t-6.6*t*t
            local chord=1.8+8.5*math.sin(math.pi*t)^.80-1.1*t
            local depth=leading-z
            if depth<0 or depth>chord then return end
            if depth<1.05 then return BAST end
            if math.abs(depth-(span-2)*.61)<.45 or math.abs(depth-(span-8)*.49)<.44 then return FLAX end
            return SILK
        end)
        local shell = part("shell"..suffix,side*2.5,11.2,4.0)
        for i=1,#wingSections-1 do
            local a,b = wingSections[i],wingSections[i+1]
            stamp(shell,-12,12,3,14,a[1],b[1],function(x,y,z)
                local s = side*x
                if s <= 0 then return end
                local t = (z-a[1])/(b[1]-a[1])
                local span = a[2]+t*(b[2]-a[2])
                if s>span then return end
                local crown = a[3]+t*(b[3]-a[3])
                local edge = a[4]+t*(b[4]-a[4])
                local across = s/span
                local top = crown+(edge-crown)*across^1.8
                -- A real step down at the suture leaves a recessed dorsal line.
                if s<1 then top=top-1.15 end
                if y>top or y<top-2.15 then return end
                -- Paired arms of a Y wrap down the rear slope to a short stem.
                if z< -3 and math.abs(s-math.max(0.5,(z+7.3)*0.95))<0.91 then return AMBER end
                if s<1 then return CUTICLE end
                if across>0.61 and across<0.88 and math.abs(z-1.2)<1.6-math.abs(across-0.75)*7 then return AMBER end
                if across>0.80 and y<top-1.55 then return CUTICLE end
                return PLUM
            end)
        end
        local antenna = part("antenna"..suffix,side*1.5,11.4,6.5)
        stroke(antenna,side,feeler,{CUTICLE,CUTICLE,AMBER})
    end

    local head = part("head",0,9.4,5.8)
    stamp(head,-4,4,7,13,4,10,function(x,y,z)
        local shape=(math.abs(x)/3.85)^3+(math.abs(y-9.95)/2.4)^3+(math.abs(z-7.0)/2.35)^3
        if shape<=1 then
            if math.abs(x)>1.2 and math.abs(x)<2.9 and y>=9 and y<11 and z>8 then return AMBER end
            return CUTICLE
        end
    end)
    for _,side in ipairs({-1,1}) do
        local suffix=side==1 and "_r" or "_l"
        for _,leg in ipairs(legs) do
            local root = leg[2][1]
            local limb = part("leg_"..leg[1]..suffix,side*root[1],root[2],root[3])
            stroke(limb,side,leg[2],leg[1]=="front" and {CUTICLE,PLUM,PLUM,CUTICLE} or {CUTICLE,CUTICLE,CUTICLE})
        end
    end
    local collar = part("fiber_collar",0,9.2,4.5)
    -- A flared wreath of flattened, overlapping flax locks. Each lock follows
    -- the neck ellipse and points outwards, giving the fringe a broken hem.
    for i=0,9 do
        local angle = 2*math.pi*i/18
        local cx,cy = math.sin(angle),math.cos(angle)
        local reach = 0.75 + (i%3)*0.27
        stamp(collar,-8,8,4,14,3,9,function(x,y,z)
            local u,v=math.abs(x)/5.4,(y-9.4)/3.25
            local along = u*cx+v*cy
            local tangent = (u*cy-v*cx)*4.8
            local taper = (along-0.65)/(reach+0.05)
            if taper<0 or taper>1 or math.abs(tangent+0.40*taper)>1.40-0.78*taper then return end
            local front = 7.5-0.85*taper + ((i%2)==0 and 0.65 or 0)
            -- Shorten the locks beside the cheeks so the elytron shoulder shows.
            if math.abs(x)>4.5 and y>8 then
                if math.abs(x)>7 and y<12 then return end
                if z>front-1.5 then return end
            end
            if z>front or z<front-3.3 then return end
            if (math.abs(tangent)>0.56 and taper<0.78) or z<front-2.45 then return BAST end
            return FLAX
        end)
    end

    for _,side in ipairs({-1,1}) do
        local suffix=side==1 and "_r" or "_l"
        local nest = part("nest"..suffix,side*7.8,6.2,0)
        -- Three pendulous cocoons per wing, offset in depth and height.
        for _,pod in ipairs({{8.5,4.5,3.5,1.7,2.0,7.7},{9.1,3.3,0.0,1.85,1.9,6.0},{7.6,4.0,-3.6,1.6,1.7,7.0}}) do
            local cx,cy,cz,rx,ry=pod[1],pod[2],pod[3],pod[4],pod[5]
            stamp(nest,-12,12,1,10,cz-2.2,cz+2.2,function(x,y,z)
                local dx,dy,dz=(side*x-cx)/rx,(y-cy)/ry,(z-cz)/1.85
                if math.abs(dy)<1 and dx*dx+dy*dy+dz*dz <= 1.14 then
                    -- A single diagonal silk wrap and a small glint leave each
                    -- sac a continuous golden shape even under the shell rim.
                    if dx>0.28 and math.abs(dy+0.48+dz*0.48)<0.17 then return SILK end
                    if dy>0.35 and dz>0.40 and dx>0 then return SILK end
                    return AMBER
                end
                if y>cy and math.abs(dx+0.16*(y-cy))<0.5 and math.abs(dz)<0.58 and y<pod[6] then return BAST end
            end)
        end
    end
    local abdomen = part("body",0,6.6,0)
    stamp(abdomen,-7,7,2,12,-9,7,function(x,y,z)
        local shape=(x/6.65)^2+((y-6.9)/4.25)^2+((z+0.5)/8.5)^2
        if shape<1 and y<8.7 and z > -6.0 and z < 4.0 then return CUTICLE end
    end)
    return {size=SIZE,palette=palette,parts=parts}
end

return NestWeaver
