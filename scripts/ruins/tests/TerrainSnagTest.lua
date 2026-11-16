-- -validate-test=ruins/tests/TerrainSnagTest.lua 随真实遗迹运行。
-- 用与诺米同参数的独立 VoxelCharacterController 在岛面上真实行走，
-- 统计"想走却走不动"的卡脚点（排除真实墙体：前方抬升 > 步高的不算卡脚）。
local V = _G["V"]
local Terrain = require("ruins.RuinsTerrain")
local function Check(ok, message)
    if V ~= nil then V.assert(ok, message) else assert(ok, message) end
end

---@param volume VoxelVolume
local function SolidAt(volume, p)
    local q = volume:GetNode():WorldToLocal(p) / volume.voxelSize
    local grid = volume:GetGrid()
    local dims = grid:GetDimensions()
    local x, y, z = math.floor(q.x), math.floor(q.y), math.floor(q.z)
    return x >= 0 and y >= 0 and z >= 0 and x < dims.x and y < dims.y and z < dims.z
        and grid:IsSolid(x, y, z)
end
-- 前方真实体素：返回 0.6~1.6m 高度处是否有实体（=真实墙/柱/建筑），以及描述
local function Probe(world, x, y, z, dx, dz)
    local tall, low, names = false, -1, {}
    for _, d in ipairs({ .36, .5, .7 }) do
        for h = .03, 1.6, .0625 do
            local p = Vector3(x + dx * d, y + h, z + dz * d)
            for i = 0, world:GetVolumeCount() - 1 do
                local vol = world:GetVolume(i)
                if vol ~= nil and vol.collisionMask ~= 0 and SolidAt(vol, p) then
                    if h > .6 then tall = true else low = math.max(low, h) end
                    local o = vol:GetNode().worldPosition
                    names[string.format("v%d[%.2f|%.1f,%.1f,%.1f]", i, vol.voxelSize, o.x, o.y, o.z)] = true
                end
            end
        end
    end
    local list = {}
    for k in pairs(names) do list[#list + 1] = k end
    table.sort(list)
    return tall, low, table.concat(list, ",")
end

local function Run(game)
    local world = game.world
    local cc = game.nomiCtl.cc
    local wasEnabled, auto = cc.enabled, world.updateEnabled
    cc.enabled, world.updateEnabled = false, false
    local node = game.scene:CreateChild("SnagWalker")
    local walker = node:CreateComponent("VoxelCharacterController")
    walker.height, walker.radius, walker.supportRadius = cc.height, cc.radius, cc.supportRadius
    walker.stepHeight, walker.maxSlopeAngle = cc.stepHeight, cc.maxSlopeAngle
    walker.enhancedInternalEdgeRemoval = cc.enhancedInternalEdgeRemoval
    walker.collisionLayer, walker.collisionMask = cc.collisionLayer, cc.collisionMask
    local snags, segments, walls, wallList, hitches, pops = {}, 0, 0, {}, {}, {}
    local function Settle(x, z)
        local h = Terrain.Height(x, z)
        walker:Teleport(Vector3(x, h + .15, z))
        walker.linearVelocity, walker.desiredVelocity = Vector3.ZERO, Vector3.ZERO
        for _ = 1, 20 do world:Update(1 / 60, 1) end
    end
    -- 走 A→B；返回是否卡住（排除真实墙）
    local function Walk(ax, az, bx, bz, speed, label)
        Settle(ax, az)
        segments = segments + 1
        local still, last, slow = 0, node.worldPosition, 0
        for _ = 1, 600 do
            local p = node.worldPosition
            local dx, dz = bx - p.x, bz - p.z
            local len = math.sqrt(dx * dx + dz * dz)
            if len < .4 then break end
            dx, dz = dx / len, dz / len
            walker.desiredVelocity = Vector3(dx * speed, 0, dz * speed)
            world:Update(1 / 60, 1)
            local q = node.worldPosition
            if p.y < 2 and Terrain.Height(ax, az) > 4 then break end -- 掉下去了，交给其它测试
            local step = math.sqrt((q.x - p.x) ^ 2 + (q.z - p.z) ^ 2)
            if step < speed / 60 * .5 then slow = slow + 1 else
                if slow >= 3 and slow < 20 then
                    hitches[#hitches + 1] = string.format("%s (%.2f,%.2f,%.2f) frames=%d", label, p.x, p.y, p.z, slow)
                end
                slow = 0
            end
            if q.y - p.y > .12 then pops[#pops + 1] = string.format("%s (%.2f,%.2f,%.2f) dy=%.2f", label, q.x, q.y, q.z, q.y - p.y) end
            local moved = math.sqrt((q.x - last.x) ^ 2 + (q.z - last.z) ^ 2)
            if moved < speed / 60 * .15 then still = still + 1 else still, last = 0, q end
            if still >= 20 then
                local tall, low, names = Probe(world, q.x, q.y, q.z, dx, dz)
                if tall then
                    walls = walls + 1
                    if #wallList < 30 then wallList[#wallList + 1] = string.format("%s (%.2f,%.2f,%.2f) %s", label, q.x, q.y, q.z, names) end
                else
                    snags[#snags + 1] = string.format("%s (%.2f,%.2f,%.2f) low=%.2f %s", label, q.x, q.y, q.z, low, names)
                end
                break
            end
        end
        walker.desiredVelocity = Vector3.ZERO
    end
    local ok, err = pcall(function()
        -- 外环切向圈（含 0.5m 量化区、16m 分块接缝）
        for _, r in ipairs({ 53, 56.5, 60, 63.5, 66.5 }) do
            for i = 0, 47 do
                local a0, a1 = i * math.pi / 24, (i + 1) * math.pi / 24
                local ax, az, bx, bz = math.cos(a0) * r, math.sin(a0) * r, math.cos(a1) * r, math.sin(a1) * r
                if Terrain.HasGround(ax, az, 1) and Terrain.HasGround(bx, bz, 1)
                    and Terrain.HasGround((ax + bx) * .5, (az + bz) * .5, 1) then
                    Walk(ax, az, bx, bz, 5.0, "outer r=" .. r)
                end
            end
        end
        -- 外环径向往返
        for i = 0, 23 do
            local a = (i + .5) * math.pi / 12
            local c, s = math.cos(a), math.sin(a)
            if Terrain.HasGround(c * 53, s * 53, 1) and Terrain.HasGround(c * 64, s * 64, 1) then
                Walk(c * 53, s * 53, c * 64, s * 64, 5.0, "outer radial")
                Walk(c * 64, s * 64, c * 53, s * 53, 5.0, "outer radial back")
            end
        end
        -- 内环（铺石带、柱廊之间、引导砖）径向往返
        for i = 0, 23 do
            local a = (i + .5) * math.pi / 12
            local c, s = math.cos(a), math.sin(a)
            if Terrain.HasGround(c * 37, s * 37, 1) then
                Walk(c * 22.4, s * 22.4, c * 37, s * 37, 5.0, "inner radial")
                Walk(c * 37, s * 37, c * 22.4, s * 22.4, 5.0, "inner radial back")
            end
        end
        -- 南北主路
        Walk(0, -66, 0, -50, 5.0, "south road");Walk(0, -50, 0, -66, 5.0, "south road back")
    end)
    node:Dispose()
    cc.enabled, world.updateEnabled = wasEnabled, auto
    if not ok then error(err) end
    print(string.format("TerrainSnagTest: %d segments, %d real walls, %d snags", segments, walls, #snags))
    for i = 1, math.min(#snags, 60) do print("  SNAG " .. snags[i]) end
    for i = 1, #wallList do print("  WALL " .. wallList[i]) end
    print(string.format("TerrainSnagTest: %d hitches, %d pops", #hitches, #pops))
    for i = 1, math.min(#hitches, 60) do print("  HITCH " .. hitches[i]) end
    for i = 1, math.min(#pops, 60) do print("  POP " .. pops[i]) end
    Check(segments > 100, "覆盖足够多的行走路线")
    Check(#snags == 0, "岛面行走无卡脚点")
end

if V ~= nil then
    V.atFrame(8, function() Run(_G["RUINS"]) end)
end
