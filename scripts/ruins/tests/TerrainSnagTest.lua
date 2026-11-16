-- -validate-test=ruins/tests/TerrainSnagTest.lua 随真实遗迹运行。
-- 用与诺米同参数的独立 VoxelCharacterController 在岛面上真实行走，
-- 统计"想走却走不动"的卡脚点（排除真实墙体：前方抬升 > 步高的不算卡脚）。
local V = _G["V"]
local Terrain = require("ruins.RuinsTerrain")
local function Check(ok, message)
    if V ~= nil then V.assert(ok, message) else assert(ok, message) end
end

-- 前方 0.6m 内静态地形抬升（解析碰撞高度）；> 步高视为真实墙
local function Rise(x, z, dx, dz, y)
    local top = -1e9
    for _, d in ipairs({ .25, .45, .65 }) do
        local h = Terrain.CollideHeight(x + dx * d, z + dz * d)
        if h > top then top = h end
    end
    return top - y
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
    local snags, segments, walls = {}, 0, 0
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
        local still, last = 0, node.worldPosition
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
            local moved = math.sqrt((q.x - last.x) ^ 2 + (q.z - last.z) ^ 2)
            if moved < speed / 60 * .15 then still = still + 1 else still, last = 0, q end
            if still >= 20 then
                local rise = Rise(q.x, q.z, dx, dz, q.y)
                if rise > cc.stepHeight + .05 then
                    walls = walls + 1
                else
                    snags[#snags + 1] = string.format("%s (%.2f,%.2f,%.2f) rise=%.2f", label, q.x, q.y, q.z, rise)
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
    for i = 1, math.min(#snags, 40) do print("  SNAG " .. snags[i]) end
    Check(segments > 100, "覆盖足够多的行走路线")
    Check(#snags == 0, "岛面行走无卡脚点")
end

if V ~= nil then
    V.atFrame(8, function() Run(_G["RUINS"]) end)
end
