-- Cells use root-space minimum corners. Only the pivots are expressed in metres.
local TimeWraith = {}
local SIZE = 0.08
local MINT, TEAL, FACE, BRASS, SAND, GLOW = 1, 2, 3, 4, 5, 6

local function put(part, x, y, z, material)
    part.cells[#part.cells + 1] = {x, y, z, material}
end

-- Each hood course sets the outer half-width, depth and width of the face opening.
local hoodCourses = {
    {7, 4.5, 4.5}, {7, 4.5, 4.5}, {7, 4.5, 4.5}, {6.8, 4.5, 4.5},
    {6.6, 4.5, 4.5}, {6.4, 4.5, 4.5}, {6, 4.4, 4}, {5.7, 4, 2.5},
    {5, 3.7, 0}, {4.3, 3, 0}, {3, 2.3, 0},
}

local function buildHood(hood, face)
    for row, course in ipairs(hoodCourses) do
        local y = row + 15
        for x = -7, 6 do
            local side = math.abs(x + 0.5)
            for z = -4, 4 do
                local depth = z - 0.1
                if (side / course[1]) ^ 2.8 + (math.abs(depth) / course[2]) ^ 2.8 <= 1 then
                    if side >= course[3] or z < -1 then
                        local color = MINT
                        if z < -1 and (side > 3 and side < 5 and y < 23 or side < 2 and y < 19) then color = TEAL end
                        if side > 5 and z < 2 and y < 21 then color = TEAL end
                        if (row == 1 and z >= 0) or (z >= 3 and side >= course[3] and side < course[3] + 1.5)
                            or (row >= 10 and z > 0 and x > 0) then color = GLOW end
                        -- An arched binding follows the brow up to the spindle.
                        if z >= 3 and ((side < 2 and y == 24) or (side >= 2 and side < 4 and y == 23)
                            or (side >= 4 and side < 5 and y == 22)) then color = BRASS end
                        put(hood, x, y, z, color)
                    elseif z <= 2 and (y > 16 or side < 3.5) then
                        local eye = side == 2.5 and y >= 19 and y <= 21 and z == 2
                        put(face, x, y, z, eye and SAND or FACE)
                    end
                end
            end
        end
    end
end

-- A swept core and broad folded panels give the hem a different outline on each side.
-- Rows are half-width, half-depth, centre X and centre Z in cell units.
local robeCourses = {
    {1, 1, 1, -2}, {1.5, 1, 0.5, -2}, {2, 1.4, 0, -2},
    {2.5, 1.7, -0.5, -1.5}, {3, 2, -1, -1}, {3.7, 2.5, -0.5, -1},
    {4.5, 3, 0, -0.5}, {5.2, 3.4, 0, 0}, {5.3, 3.5, 0, 0},
    {5.4, 3.6, 0, 0}, {5.4, 3.5, 0, 0}, {5.2, 3.3, 0, 0},
    {5.1, 3.3, 0, 0},
}

local function buildRobe(mantle, tail)
    for row, course in ipairs(robeCourses) do
        local y = row + 2
        for x = -5, 4 do
            for z = -4, 3 do
                local dx = x + 0.5 - course[3]
                local dz = z + 0.5 - course[4]
                local radius = (math.abs(dx) / course[1]) ^ 2.6 + (math.abs(dz) / course[2]) ^ 2.6
                if radius <= 1 then
                    local fold = math.cos(math.atan(dx, dz) * 5 + y * 0.15)
                    local color = MINT
                    if fold < -0.18 and row > 3 then color = TEAL end
                    if (fold > 0.68 and row < 8) or row <= 2 then color = GLOW end
                    put(y < 10 and tail or mantle, x, y, z, color)
                end
            end
        end
    end
end

local function buildSleeve(part, sign)
    -- Shoulder to drooping cuff. The lower edge rolls out and splits at the tip.
    local courses = {{5, 6, 0}, {5, 7, 0}, {5, 7, 0}, {5, 8, 0}, {6, 8, 0},
        {6, 9, 1}, {7, 9, 1}, {7, 9, 1}, {7, 8, 2}}
    for row, c in ipairs(courses) do
        for out = c[1], c[2] do
            for z = c[3] - 2, c[3] + 1 do
                local corner = (out == c[2] and z == c[3] - 2) or (out == c[1] and z == c[3] + 1)
                if not corner then
                    local color = MINT
                    if z < c[3] or (out == c[1] and row < 6) then color = TEAL end
                    if row >= 8 or (out == c[2] and z >= c[3] and row >= 5) then color = GLOW end
                    put(part, sign > 0 and out or -1 - out, 16 - row, z, color)
                end
            end
        end
    end
end

local function buildDial(ring)
    for x = -11, 10 do
        for y = 10, 31 do
            local dx, dy = x + 0.5, y + 0.5 - 21
            local r = math.sqrt(dx * dx + dy * dy)
            local phase = math.atan(dx, dy) * 12 / (2 * math.pi)
            local onTooth = math.abs(phase - math.floor(phase + 0.5)) < 0.24
            local brace = dy > 3 and r >= 5 and r < 7.7 and math.abs(math.abs(dx) - dy * 0.65) < 0.65
            if brace or (r >= 7.7 and (r <= 9.65 or (onTooth and r <= 11.15))) then
                put(ring, x, y, -6, BRASS)
                put(ring, x, y, -5, BRASS)
            end
        end
    end
end

-- A punched cog profile is also readable edge-on thanks to the second brass course.
local cogRows = {'.#.#.', '#####', '##.##', '#####', '.#.#.'}
local function buildCog(part, cx, cy, back)
    for row, mask in ipairs(cogRows) do
        for col = 1, #mask do
            if mask:sub(col, col) == '#' then
                for z = back, back + 1 do put(part, cx + col - 3, cy + 3 - row, z, BRASS) end
            end
        end
    end
end

local function buildHourglass(part)
    for y = 8, 15 do
        local level = y - 8
        for x = -3, 2 do
            local side = math.abs(x + 0.5)
            for z = 4, 6 do
                local cap = level == 0 or level == 7
                local bevel = side > 2 and (z == 4 or z == 6)
                if cap and (not bevel or z == 4) then
                    put(part, x, y, z, BRASS)
                elseif not cap then
                    if side == 2.5 and z == 4 then
                        put(part, x, y, z, BRASS)
                    elseif z == 5 or z == 6 then
                        local bulb = level == 1 or level == 6 or level == 5
                        if (bulb and side <= 1.5) or x == -1 or (x == 0 and (level == 2 or level == 5)) then
                            put(part, x, y, z, SAND)
                        end
                    end
                end
            end
        end
    end
end

local function buildHand(part)
    -- Stamped silhouette, seen from +Z. The negative-X tip surrounds one aperture.
    local rows = {
        {-8, '##'}, {-8, '#.#'}, {-7, '###'}, {-6, '##'}, {-5, '##'},
        {-4, '##'}, {-3, '###'}, {-2, '###'}, {-2, '###'}, {-1, '#'},
    }
    for i, row in ipairs(rows) do
        local y = 32 - i
        for j = 1, #row[2] do
            if row[2]:sub(j, j) == '#' then
                local x = row[1] + j - 1
                put(part, x, y, 5, BRASS)
                if y >= 23 and y <= 25 and x >= -2 and x <= 0 then
                    put(part, x, y, 4, BRASS)
                    if x == -1 and y == 24 then put(part, x, y, 6, SAND) end
                end
            end
        end
    end
end

local function ribbon(part, points)
    for i, p in ipairs(points) do
        put(part, p[1], p[2], p[3], i <= 2 and SAND or MINT)
        put(part, p[1], p[2] + 1, p[3], i <= 2 and SAND or GLOW)
    end
end

function TimeWraith.Build()
    local parts = {}
    local function part(id, x, y, z)
        local p = {id = id, pivot = {x * SIZE, y * SIZE, z * SIZE}, cells = {}}
        parts[#parts + 1] = p
        return p
    end

    buildHood(part('hood', 0, 17, 0), part('face', 0, 21, 1))
    buildRobe(part('mantle', 0, 15, 0), part('tail', 0, 10, -1))
    buildSleeve(part('sleeve_r', 5.5, 16, 0), 1)
    buildSleeve(part('sleeve_l', -5.5, 16, 0), -1)
    buildDial(part('clock_ring', 0, 21, -5))
    local cogs = part('escapement', 1.5, 17.5, -5)
    buildCog(cogs, 1, 17, -7)
    buildCog(cogs, -10, 17, -4)
    -- The rear arbor meets the hood behind the punched face of the wheel.
    for z = -6, -5 do put(cogs, 1, 17, z, BRASS) end
    buildHourglass(part('hourglass', 0, 16, 5.5))
    buildHand(part('clock_hand', -0.5, 24.5, 5))
    ribbon(part('ribbon_r', 10, 15, -2), {{10,15,-3},{11,15,-3},{12,15,-3},{12,15,-2},
        {12,14,-1},{12,14,0},{11,14,0},{11,14,1},{10,14,1},{10,14,2}})
    ribbon(part('ribbon_l', -10, 11, 1), {{-11,10,3},{-12,10,3},{-13,10,3},{-13,10,2},
        {-13,11,1},{-13,11,0},{-12,11,0},{-12,11,-1},{-11,11,-1},{-11,11,-2}})
    ribbon(part('ribbon_back', 0, 11, -4), {{3,9,-4},{2,9,-4},{1,9,-4},{0,9,-4},
        {-1,9,-4},{-2,10,-4},{-3,10,-4},{-4,10,-4},{-5,10,-4},{-5,10,-3}})

    return {size = SIZE, parts = parts, palette = {
        {name = 'Mint veil', rgb = {148, 211, 187}, roughness = 0.75, metallic = 0, emission = 0},
        {name = 'Deep teal fold', rgb = {83, 148, 141}, roughness = 0.85, metallic = 0, emission = 0},
        {name = 'Hood shadow', rgb = {64, 71, 79}, roughness = 0.92, metallic = 0, emission = 0},
        {name = 'Old brass', rgb = {191, 139, 63}, roughness = 0.43, metallic = 0.68, emission = 0},
        {name = 'Luminous sand', rgb = {255, 216, 120}, roughness = 0.50, metallic = 0, emission = 1.2},
        {name = 'Pale wisp', rgb = {205, 246, 220}, roughness = 0.65, metallic = 0, emission = 0.5},
    }}
end

return TimeWraith
