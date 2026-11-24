-- Quarry stone, built in horizontal courses. +X is the colossus's right hand.
local RockColossus = {}
local SIZE = 0.10
local STONE, CUT, JOINT, MOSS, GOLD, CRYSTAL = 1, 2, 3, 4, 5, 6

-- Coordinates are small signed integers. The offset keeps all three fields positive.
local function key(x, y, z)
    return (y * 128 + x + 64) * 128 + z + 64
end

local function part(id, x, y, z)
    return { id = id, pivot = { x * SIZE, y * SIZE, z * SIZE }, cells = {}, grid = {} }
end

-- Cut off the four vertical arrises. Successive courses step out to form an overhang.
local function course(p, y0, y1, x0, x1, z0, z1, bevel, material)
    for y = y0, y1 do
        for x = x0, x1 do
            for z = z0, z1 do
                local edgeX = math.min(x - x0, x1 - x)
                local edgeZ = math.min(z - z0, z1 - z)
                if edgeX + edgeZ >= bevel then
                    p.grid[key(x, y, z)] = { x, y, z, material }
                end
            end
        end
    end
end

-- A chisel cuts one voxel into the exposed stone along Z. The floor of the cut
-- uses the fissure stone. Both the depth and the mark survive a three-quarter view.
local function engrave(p, x0, yTop, facing, rows)
    for row, line in ipairs(rows) do
        for col = 1, #line do
            if line:sub(col, col) == '#' then
                local x, y = x0 + col - 1, yTop - row + 1
                for depth = 12, -12, -1 do
                    local z = depth * facing
                    local outer = key(x, y, z)
                    local floor = p.grid[key(x, y, z - facing)]
                    if p.grid[outer] and floor then
                        p.grid[outer] = nil
                        floor[4] = JOINT
                        break
                    end
                end
            end
        end
    end
end

local function torso()
    local p = part('torso', 0, 12, 0)
    course(p, 9, 10, -7, 6, -3, 3, 1, JOINT)
    course(p, 11, 12, -8, 7, -4, 3, 2, STONE)
    course(p, 11, 12, -5, 4, -5, -3, 1, GOLD)
    course(p, 10, 10, -3, 2, -5, -2, 1, GOLD)
    course(p, 13, 14, -6, 5, -3, 3, 2, JOINT)
    course(p, 14, 15, -7, 6, -4, 4, 2, STONE)
    course(p, 16, 17, -8, 7, -5, 4, 2, STONE)
    course(p, 18, 22, -9, 8, -5, 5, 2, STONE)
    course(p, 23, 24, -8, 7, -4, 4, 1, CUT)
    course(p, 23, 24, -8, -6, 3, 4, 1, MOSS)
    course(p, 23, 24, 5, 7, 3, 4, 1, MOSS)
    course(p, 25, 25, -7, 6, -3, 3, 1, JOINT)
    -- Keystone and dorsal seal, raised proud of the side plates.
    course(p, 15, 15, -4, 3, 3, 5, 1, STONE)
    course(p, 16, 21, -5, 4, 3, 6, 1, CUT)
    course(p, 22, 22, -4, 3, 3, 6, 1, CUT)
    course(p, 16, 23, -6, 5, -6, -3, 1, STONE)
    course(p, 24, 24, -5, 4, -5, -3, 1, CUT)
    -- Raised dorsal buttresses flank the carved central shield.
    for _, x in ipairs({-7,5}) do
        course(p, 19,22,x,x+1,-7,-4,1,CUT)
        course(p, 23,25,x,x+1,-8,-4,1,STONE)
        course(p, 26,27,x,x+1,-7,-5,1,CUT)
    end
    engrave(p, -3, 20, 1, {'######','#....#','#..#.#','...#..'})
    engrave(p, -4, 22, -1, {'#######','#......','#.####.','#....#.','######.'})
    return p
end

local function head()
    local p = part('head', 0, 25, 0)
    course(p, 25, 25, -4, 3, -2, 4, 1, STONE)
    course(p, 26, 28, -5, 4, -3, 4, 2, JOINT)
    course(p, 26, 28, -5, 4, -3, 0, 2, STONE)
    course(p, 26, 27, -3, -3, 4, 4, 0, CRYSTAL)
    course(p, 26, 27, 2, 2, 4, 4, 0, CRYSTAL)
    course(p, 29, 30, -6, 5, -4, 5, 1, CUT)
    course(p, 31, 31, -5, 4, -3, 3, 2, STONE)
    course(p, 32, 32, -3, 2, -2, 2, 1, STONE)
    return p
end

local function leg(right)
    local mid = right and 6 or -7
    local p = part(right and 'leg_r' or 'leg_l', mid + 0.5, 13, 0)
    course(p, 0, 1, mid-3, mid+3, -2, 5, 1, STONE)
    course(p, 2, 2, mid-3, mid+3, -2, 5, 1, CUT)
    course(p, 3, 3, mid-2, mid+2, -2, 2, 1, JOINT)
    course(p, 4, 5, mid-3, mid+3, -2, 4, 2, CUT)
    course(p, 6, 6, mid-3, mid+3, -2, 3, 2, STONE)
    course(p, 7, 9, mid-2, mid+2, -2, 2, 1, JOINT)
    course(p, 10, 11, mid-3, mid+2, -2, 2, 1, STONE)
    return p
end

local function arm(right)
    local p = part(right and 'upper_arm_r' or 'upper_arm_l', right and 9 or -9, 24, 0)
    -- Distance from the centreline in anatomical space. The -1 mirrors minimum corners.
    local function slab(y0,y1,inner,outer,z0,z1,bevel,material)
        local x0, x1 = inner, outer
        if not right then x0, x1 = -outer-1, -inner-1 end
        course(p,y0,y1,x0,x1,z0,z1,bevel,material)
    end
    slab(23,24,8,10,-2,2,0,JOINT)
    slab(15,16,14,18,-2,2,1,JOINT)
    slab(17,18,13,18,-3,2,1,JOINT)
    slab(19,20,12,17,-3,2,1,JOINT)
    slab(21,22,11,18,-4,3,2,STONE)
    slab(23,25,9,18,-5,4,2,STONE)
    slab(26,27,8,17,-4,4,2,CUT)
    slab(28,28,9,16,-3,3,2,STONE)
    -- Back-swept shoulder lames with a raised upper blade.
    slab(24,25,13,19,-6,-2,2,STONE)
    slab(26,27,12,19,-7,-2,2,CUT)
    slab(28,29,12,18,-7,-3,2,STONE)
    slab(30,30,13,17,-6,-4,1,CUT)
    -- Turf follows the ledge around the back and hangs in unequal tongues.
    slab(28,29,9,15,-3,2,2,MOSS)
    slab(27,28,14,17,-3,0,1,MOSS)
    slab(27,28,11,14,-4,-2,1,MOSS)
    slab(26,27,10,13,-4,-2,1,MOSS)
    if not right then
        slab(27,28,10,14,1,4,1,MOSS)
        slab(25,26,11,12,3,4,0,MOSS)
        slab(26,27,15,17,1,3,1,MOSS)
    end
    return p
end

local function crystal()
    local p = part('crystal', 13, 28, 2)
    -- A mineral blade leaning out of a split in the pauldron, widening before the tip.
    course(p, 28,29,12,15,2,5,1,CRYSTAL)
    course(p, 30,31,12,16,2,5,1,CRYSTAL)
    course(p, 32,32,13,16,2,4,1,CRYSTAL)
    course(p, 33,33,14,16,2,4,1,CRYSTAL)
    course(p, 34,34,15,15,3,3,0,CRYSTAL)
    return p
end

local function heavyFist()
    local p = part('fist_r', 16.5, 15, 1)
    -- The knuckles move forward as the arm descends. The gold cuff wraps in Z.
    course(p, 13,14,13,20,-2,4,2,CUT)
    course(p, 11,12,13,21,-2,5,2,GOLD)
    course(p, 9,10,14,22,-2,6,2,STONE)
    course(p, 7,8,14,23,-1,7,2,STONE)
    course(p, 4,6,15,24,0,8,2,STONE)
    course(p, 2,3,16,24,1,8,2,STONE)
    course(p, 1,1,17,23,2,7,1,JOINT)
    course(p, 4,9,16,22,4,8,1,CUT)
    course(p, 4,7,20,25,3,8,2,STONE)
    course(p, 3,5,17,19,6,9,1,CUT)
    course(p, 5,7,20,23,6,9,1,CUT)
    -- A second cut plane catches side light across the outside knuckles.
    course(p, 4,6,22,24,1,7,1,CUT)
    course(p, 7,8,21,23,0,6,1,CUT)
    course(p, 9,9,20,22,0,5,1,CUT)
    -- Two connected chisel strokes continue around the outside of the fist.
    for y = 4, 8 do
        local rim = y < 7 and 24 or 23
        local z = y < 6 and 3 or 4
        p.grid[key(rim,y,z)] = nil
        p.grid[key(rim-1,y,z)][4] = JOINT
    end
    engrave(p, 17, 8, 1, {'#####','#....','#.###','#...#','#####'})
    return p
end

local function smallFist()
    local p = part('fist_l', -16.5, 15, 1)
    course(p, 13,14,-21,-14,-3,3,2,CUT)
    course(p, 11,12,-22,-14,-3,4,2,STONE)
    course(p, 7,10,-22,-17,-2,4,1,JOINT)
    course(p, 7,10,-21,-18,3,4,1,STONE)
    course(p, 6,6,-21,-18,-1,3,1,JOINT)
    course(p, 8,10,-16,-15,2,4,1,CUT)
    return p
end

-- Internal ties join the stair-stepped skins through voxel faces at the bevels.
local ties = {
    torso={{-7,22,-2}, {-6,16,3}, {-4,13,0}, {-4,13,2}, {1,18,5}, {2,16,5},
        {3,14,-1}, {3,22,-3}, {4,14,2}, {5,12,1}, {5,14,0}, {5,18,4},
        {6,16,2}, {6,24,2}, {7,22,-1}},
    head={{2,29,-1}, {2,31,0}, {4,29,2}, {4,30,1}},
    leg_r={{5,6,2}, {7,4,2}, {7,6,2}},
    leg_l={{-8,6,2}, {-6,4,2}, {-6,6,2}},
    upper_arm_r={{11,28,2}, {12,21,1}, {13,19,1}, {13,21,-1}, {13,29,-3}, {16,21,2},
        {17,18,0}, {17,23,-1}, {17,23,2}, {17,29,-3}, {18,27,-3}},
    upper_arm_l={{-18,21,1}, {-18,23,-1}, {-18,27,-4}, {-18,29,-3}, {-17,23,3}, {-14,19,0},
        {-14,21,-1}, {-14,21,2}, {-14,29,-3}, {-13,21,1}, {-10,27,1}},
    fist_r={{17,2,3}, {18,3,8}, {20,7,7}, {22,4,1}, {22,4,7}, {23,2,6},
        {23,3,3}, {23,6,3}},
    fist_l={},
    crystal={{14,32,3}, {15,33,3}},
}

function RockColossus.Build()
    local parts = { torso(), head(), leg(true), leg(false), arm(true), arm(false),
        heavyFist(), smallFist(), crystal() }
    -- The socket belongs to the crystal and the neck belongs to the head.
    for k in pairs(parts[2].grid) do parts[1].grid[k] = nil end
    for k in pairs(parts[9].grid) do parts[5].grid[k] = nil end
    -- Each rigid plate keeps its closed skin, including surfaces inside joints.
    -- Sort by coordinate to give callers a stable cell order across builds.
    for _, p in ipairs(parts) do
        local compact={}
        for _,cell in pairs(p.grid) do
            local z=cell[3]
            if z~=-1 and z~=-2 then
                if z< -2 then cell[3]=z+2 end
                compact[key(cell[1],cell[2],cell[3])]=cell
            end
        end
        p.grid=compact
        for k, cell in pairs(p.grid) do
            if not (p.grid[k-1] and p.grid[k+1] and p.grid[k-128] and p.grid[k+128]
                and p.grid[k-16384] and p.grid[k+16384]) then
                p.cells[#p.cells+1] = cell
            end
        end
        for _, tie in ipairs(ties[p.id] or {}) do
            p.cells[#p.cells+1] = p.grid[key(tie[1], tie[2], tie[3])]
        end
        table.sort(p.cells, function(a, b) return key(a[1],a[2],a[3]) < key(b[1],b[2],b[3]) end)
        if p.id~='leg_l' and p.id~='leg_r' then
            p.pivot[2]=p.pivot[2]+3*SIZE
            for _,cell in ipairs(p.cells) do cell[2]=cell[2]+3 end
        end
        p.grid = nil
    end
    return { size = SIZE, parts = parts, palette = {
        {name='quarry_stone', rgb={146,126,117}, roughness=.90, metallic=0, emission=0},
        {name='fresh_cut', rgb={185,163,147}, roughness=.77, metallic=0, emission=0},
        {name='fissure', rgb={72,62,60}, roughness=.96, metallic=0, emission=0},
        {name='ledge_moss', rgb={139,151,57}, roughness=.99, metallic=0, emission=0},
        {name='old_gold', rgb={206,156,75}, roughness=.52, metallic=.70, emission=0},
        {name='aqua_quartz', rgb={81,225,219}, roughness=.22, metallic=0, emission=.48},
    } }
end

return RockColossus
