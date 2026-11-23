local WoodSpirit = {}
local SIZE = 0.08
local BARK, FISSURE, LEAF, MOSS, PETAL, SAP = 1, 2, 3, 4, 5, 6

-- Coordinates passed to the sculpting functions are root-space cell indices.
-- Mirroring the minimum corner about zero needs a one-cell correction.
local function mirror(n, side)
    if side < 0 then return -n - 1 end
    return n
end

local function partWriter(parts, id, px, py, pz)
    local cells, lookup = {}, {}
    parts[#parts + 1] = {id = id, pivot = {px * SIZE, py * SIZE, pz * SIZE}, cells = cells}
    return function(x, y, z, material)
        local key = x .. "," .. y .. "," .. z
        local cell = lookup[key]
        if cell then
            cell[4] = material
        else
            cell = {x, y, z, material}
            lookup[key] = cell
            cells[#cells + 1] = cell
        end
    end
end

local function stump(parts)
    local put = partWriter(parts, "body", 0, 4, 0)
    -- Each course describes a clipped rectangular section of the trunk from below the chin to the brow.
    local sections = {
        {5, 4, 7}, {6, 5, 8}, {7, 5, 9}, {7, 6, 10}, {7, 6, 10},
        {7, 6, 10}, {7, 6, 10}, {7, 6, 10}, {7, 5, 9}, {6, 5, 8},
    }
    for layer, section in ipairs(sections) do
        local y = layer + 3
        for x = -section[1], section[1] - 1 do
            for z = -section[2], section[2] - 1 do
                local ax, az = math.abs(x + 0.5), math.abs(z + 0.5)
                local face = ax <= 3.5 and y >= 8 and y <= 10
                local socket = ax <= 2.5 and y >= 5 and y <= 7
                local front = section[2] - 1
                if face then front = 4 end
                if socket then front = 3 end
                if ax + az <= section[3] and z <= front then
                    local material = BARK
                    -- Three staggered fissures on the back and a narrower one on either cheek.
                    if z < 0 and (x == -4 + math.floor(y / 8) or (x == 2 and y <= 11) or (x == 4 and y >= 10)) then
                        material = FISSURE
                    elseif ax >= 4.5 and (z == -2 + math.floor(y / 9) or (z == 2 and y < 10)) then
                        material = FISSURE
                    elseif z == front and (face or socket) then
                        material = FISSURE
                        if face and ax == 2.5 and y >= 9 then material = SAP end
                    end
                    put(x, y, z, material)
                end
            end
        end
    end

    -- Rear staves descend into the roots, with different widths either side of the heartwood.
    for x = -4, 3 do
        local low = (x == -4 or x == 3) and 6 or 5
        local high = x < 0 and 12 or 11
        if x ~= -2 and x ~= 2 then
            for y = low, high do put(x, y, -6, BARK) end
        end
    end

    -- The grain splits around a knot in the rear stave and closes again below it.
    local knot = {{-2,5},{-2,6},{-2,7},{-3,8},{-3,9},{-2,10},{-1,9},{-1,8}}
    for _, point in ipairs(knot) do put(point[1], point[2], -6, FISSURE) end
    put(1, 11, 5, FISSURE)
    put(1, 12, 4, FISSURE)

    -- Exposed sawn crown with an off-centre pith and an incomplete growth ring.
    for y = 14, 16 do
        for x = -4, 3 do
            for z = -3, 2 do
                local ax, az = math.abs(x + 0.5), math.abs(z + 0.5)
                if ax + az <= 5 then
                    local ring = math.max(math.abs(x + 0.8) / 1.4, math.abs(z + 0.4))
                    local grain = y == 16 and ring > 1 and ring < 2 and (x ~= -2 or z >= 0)
                    local split = y < 16 and (x == 2 and z == 2 or x == -4 and z == -1)
                    put(x, y, z, (grain or split) and FISSURE or BARK)
                end
            end
        end
    end

    -- Moss follows the shoulder around the back. Narrow tongues break the lower edge.
    for _, side in ipairs({1, -1}) do
        local function moss(x, y, z, color) put(mirror(x, side), y, z, color) end
        for x = 0, 6 do
            for z = -5, 4 do
                local edge = x + math.abs(z + 0.5)
                if edge <= 8.5 and (x >= 4 or z < -3 or (x >= 2 and z >= 3)) then
                    moss(x, 13, z, LEAF)
                    local petiole = x == 5 and (z == -1 or z == -2)
                    if edge < 7.5 and x < 6 and not petiole then moss(x, 14, z, MOSS) end
                end
            end
        end
        moss(5, 12, 4, LEAF)
        moss(4, 12, -5, LEAF)
        moss(2, 12, -5, MOSS)
        moss(2, 11, -6, LEAF)
        local vine = {{6,13,1},{7,13,1},{7,12,1},{7,11,1},{8,11,1},
            {8,10,1},{8,10,2},{8,9,2},{8,8,2},{9,8,2},{9,7,2},{9,6,2}}
        for i, point in ipairs(vine) do
            moss(point[1], point[2], point[3], i < 5 and MOSS or LEAF)
        end
        -- A flower turns up and forward, showing petal edges and pollen from both viewpoints.
        local fx = side == 1 and 4 or 3
        local fz = side == 1 and 3 or 4
        moss(fx, 15, fz, SAP)
        moss(fx - 1, 15, fz, PETAL)
        moss(fx + 1, 15, fz, PETAL)
        moss(fx, 16, fz - 1, PETAL)
        moss(fx, 15, fz - 1, PETAL)
        moss(fx, 14, fz + 1, PETAL)
        moss(fx, 14, fz, PETAL)
    end
end

local function leafEar(parts, side, id)
    local put = partWriter(parts, id, side * 5, 14, -1)
    -- Cross sections from petiole to tip. The spine sweeps back in Z and rises across X.
    -- Columns give inner edge, outer edge and midrib, all measured outward from the centre.
    local blade = {{5,6,5},{5,9,6},{5,10,7},{5,11,8},{6,11,9},{7,11,10},{9,11,11}}
    for i, row in ipairs(blade) do
        local y = i + 13
        for x = row[1], row[2] do
            local z = -1 - math.floor((x - 5) / 3) - math.floor((i - 1) / 3)
            if i >= 3 and x < row[3] then z = z + 1 end
            local spine = x == row[3]
            local vein = i == 4 and x == row[3] - 1 or i == 5 and x == row[3] + 1
            put(mirror(x, side), y, z, (spine or vein) and LEAF or MOSS)
            if i < 7 then put(mirror(x, side), y, z - 1, spine and MOSS or LEAF) end
        end
    end
end

local function rootFoot(parts, sx, sz, id)
    local put = partWriter(parts, id, sx * 4, 4, sz * 2.5)
    for y = 0, 3 do
        local offset = y < 2 and 1 or 0
        for x = 2, 5 do
            for z = 1, 4 do
                if (x ~= 5 or z ~= 4) and (y == 0 or x ~= 2 or z ~= 1) then
                    local color = BARK
                    if x == 2 or (z == 3 and y < 2) then color = FISSURE end
                    if y >= 2 and x >= 4 and z == 3 then color = MOSS end
                    put(mirror(x + offset, sx), y, mirror(z + offset, sz), color)
                end
            end
        end
    end
end

function WoodSpirit.Build()
    local parts = {}
    stump(parts)
    leafEar(parts, 1, "leaf_r")
    leafEar(parts, -1, "leaf_l")
    rootFoot(parts, 1, 1, "root_front_r")
    rootFoot(parts, -1, 1, "root_front_l")
    rootFoot(parts, 1, -1, "root_back_r")
    rootFoot(parts, -1, -1, "root_back_l")

    local put = partWriter(parts, "core", 0, 6.5, 4.5)
    for y = 5, 7 do
        local width = y == 6 and 2 or 1
        for x = -width, width - 1 do
            put(x, y, 4, SAP)
            if math.abs(x + 0.5) < 1 then
                put(x, y, 5, SAP)
                if y == 6 then put(x, y, 6, SAP) end
            end
        end
    end
    local palette = {
        {name="Cork bark", rgb={148,100,66}, roughness=0.91, metallic=0, emission=0},
        {name="Bark fissure", rgb={84,55,43}, roughness=0.98, metallic=0, emission=0},
        {name="Leaf underside", rgb={107,131,50}, roughness=0.71, metallic=0, emission=0},
        {name="Spring leaf", rgb={163,181,54}, roughness=0.49, metallic=0, emission=0},
        {name="Ivory petal", rgb={255,236,187}, roughness=0.77, metallic=0, emission=0},
        {name="Honey resin", rgb={255,191,67}, roughness=0.25, metallic=0, emission=0.55},
    }
    return {size = SIZE, palette = palette, parts = parts}
end

return WoodSpirit
