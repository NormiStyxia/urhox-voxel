-- -validate-test=ruins/tests/StairGeometryTest.lua 随真实遗迹运行；
-- 也可直接用本文件作入口，只执行高度/网格数学断言（不冒充物理验收）。
local V = _G["V"]
local Terrain = require("ruins.RuinsTerrain")
local Build = require("ruins.RuinsBuild")
local function Check(ok, message)
    if V ~= nil then V.assert(ok, message) else assert(ok, message) end
end

local function Structure()
    Check(Terrain.STAIR_JOIN == 33.5, "阶梯回接覆盖完整地形三角面")
    Check(Terrain.StairY(0) == 0 and Terrain.StairY(100) == 6, "台面两端夹紧")
    for _, sign in ipairs({ -1, 1 }) do
        for step = 0, 11 do
            local d = Terrain.COURT_R + step
            local before, after = Terrain.StairY(sign * (d - .001)), Terrain.StairY(sign * (d + .001))
            Check(math.abs(after - before - .5) < .00001, "每级恰为0.5米，不靠扩大步高")
            for _, x in ipairs({ -3.125, .125, 3.125 }) do
                Check(Terrain.CollideHeight(x, sign * (d + .25)) == -1,
                    "粗网格不叠在可见台阶上")
                Check(Terrain.Height(x, sign * (d + .125)) == after,
                    "通道边缘和中央的台面高度相同")
            end
        end
        Check(Terrain.StairY(sign * Terrain.STAIR_START) == 0, "底踏步与龙庭齐平")
        Check(Terrain.StairY(sign * Terrain.STAIR_JOIN) == Terrain.RING_Y, "末踏面与内环齐平")
        Check(Terrain.VisualHeight(0, sign * (Terrain.STAIR_JOIN - .5)) < -1,
            "回接前最后一个Terrain顶点在石阶下")
        Check(Terrain.VisualHeight(0, sign * Terrain.STAIR_JOIN) == 6, "Terrain在体积末端才回接到6米")
        -- maxLodLevels=3：0.5/1/2m 的尾端高度图线性边（及同高横向顶点组成的三角面）
        -- 都在最后的 y=6 平踏面下面；不通过关LOD或增加细分来掩盖衔接。
        for _, stride in ipairs({.5, 1, 2}) do
            for d = 31.75, Terrain.STAIR_JOIN - .001, .125 do
                local a = math.floor(d / stride) * stride
                local t = (d - a) / stride
                local h = Terrain.VisualHeight(0, sign * a) * (1 - t)
                    + Terrain.VisualHeight(0, sign * (a + stride)) * t
                Check(h < Terrain.StairY(sign * d) - .001,
                    "LOD末端三角过渡不穿出平踏面")
            end
        end
        Check(Terrain.CollideHeight(4.25, sign * 23.25) == -1,
            "扶墙外缘半格不留下侵入通道的粗网格")
    end
    Check(Terrain.VisualHeight(20.5, 0) < -1, "龙庭地砖边缘没有同高Terrain")
    Check(Terrain.Height(22, 0) == 6 and Terrain.VisualHeight(22, 0) == 6,
        "r22平台未扩建或抬高")
    Check(Build.DETAIL.ornament < .55 and Build.DETAIL.ornament * .5 < Build.DETAIL.ornament,
        "引导砖及台缘离面高度低于步高且彼此不同高")
    print("StairGeometryTest: height/quantization assertions completed (not physical evidence)")
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

local function Actual(game)
    local world = game.world
    ---@type VoxelVolume[]
    local stairs = Build.stairVolumes
    Check(#stairs == 2, "踏面和扶墙只有南北两个Volume")
    local cc = game.nomiCtl.cc
    Check(math.abs(cc.stepHeight - .55) < .00001 and cc.enhancedInternalEdgeRemoval,
        "保留0.55步高并启用内部边接触剔除")
    for _, sign in ipairs({ -1, 1 }) do
        for _, d in ipairs({20.375, 20.875, 21.875, 31.875, 32.875, 33.375}) do
            for _, x in ipairs({-3.125, .125, 3.125}) do
                local y = Terrain.StairY(sign * d)
                local p = Vector3(x, y - .125, sign * d)
                local occupants = 0
                for i = 0, world:GetVolumeCount() - 1 do
                    local vol = world:GetVolume(i)
                    if vol ~= nil and SolidAt(vol, p) then occupants = occupants + 1 end
                end
                Check(occupants == 1, "踏面内部只有一份实体，含首末级/侧缘")
                local own = sign < 0 and stairs[1] or stairs[2]
                Check(SolidAt(own, p) and not SolidAt(own, p + Vector3(0, .25, 0)),
                    "真实Grid踏面高度与解析台面相符")
            end
        end
    end

    -- 在独立角色上真实步进，原诺米停用；不改相机、谜题时钟、破坏/回溯数据。
    -- 每次从平地/平台起步，不跳跃；墙负回归绝不能用传送越过障碍来算通过。
    local wasEnabled, auto = cc.enabled, world.updateEnabled
    cc.enabled, world.updateEnabled = false, false
    local node = game.scene:CreateChild("StairRegressionWalker")
    local walker = node:CreateComponent("VoxelCharacterController")
    walker.height, walker.radius, walker.supportRadius = cc.height, cc.radius, cc.supportRadius
    walker.stepHeight, walker.maxSlopeAngle = cc.stepHeight, cc.maxSlopeAngle
    walker.enhancedInternalEdgeRemoval = cc.enhancedInternalEdgeRemoval
    walker.collisionLayer, walker.collisionMask = cc.collisionLayer, cc.collisionMask
    local function Settle(p)
        walker:Teleport(p)
        walker.linearVelocity, walker.desiredVelocity = Vector3.ZERO, Vector3.ZERO
        for i = 1, 30 do world:Update(1 / 60, 1) end
    end
    local function Walk(sign, ascending, x)
        local start, finish = ascending and 19.5 or 34.25, ascending and 34.25 or 19.5
        Settle(Vector3(x, ascending and .1 or 6.1, sign * start))
        local direction = sign * (ascending and 1 or -1)
        walker.desiredVelocity = Vector3(0, 0, direction * 4.2)
        local reached, exceeded = false, false
        for i = 1, 360 do
            world:Update(1 / 60, 1)
            exceeded = exceeded or walker.maxHitsExceeded
            local d = sign * node.worldPosition.z
            if (ascending and d >= finish) or (not ascending and d <= finish) then reached = true; break end
        end
        walker.desiredVelocity = Vector3.ZERO
        for i = 1, 15 do world:Update(1 / 60, 1) end
        print(string.format("StairGeometryTest: %s sign=%d lane=%.2f feet=%s grounded=%s hitsExceeded=%s",
            ascending and "up" or "down", sign, x, tostring(node.worldPosition), tostring(walker.onGround), tostring(exceeded)))
        Check(reached, "真实角色不跳跃走完南北阶梯及起终点/侧缘")
        Check(not exceeded, "台阶接触查询未超预算")
        Check(math.abs(node.worldPosition.y - (ascending and 6 or 0)) < .15,
            "上下楼终点不悬空或陷脚")
    end
    local ok, err = pcall(function()
        for _, sign in ipairs({-1, 1}) do
            for _, x in ipairs({-2.9, 0, 2.9}) do Walk(sign, true, x); Walk(sign, false, x) end
        end
        -- 扶墙1米高，自动跨步不得爬上。
        Settle(Vector3(2.9, 2.1, 24.25))
        walker.desiredVelocity = Vector3(4.2, 0, 0)
        for i = 1, 90 do world:Update(1 / 60, 1) end
        Check(node.worldPosition.x < 3.5 and node.worldPosition.y < 2.4, "不能自动爬过扶墙")
        -- 西塔高4.25米保持谜题跳台，不给全局爬墙能力。
        Settle(Vector3(-32.5, 6.1, -6))
        walker.desiredVelocity = Vector3(-4.2, 0, 0)
        for i = 1, 90 do world:Update(1 / 60, 1) end
        Check(node.worldPosition.x > -33.75 and node.worldPosition.y < 7,
            "西塔壁仍需悬石谜题，不能靠自动步高爬上")
    end)
    node:Dispose()
    cc.enabled, world.updateEnabled = wasEnabled, auto
    if not ok then error(err) end
    print("StairGeometryTest: real Grid and VoxelCharacterController regressions completed")
end

if V ~= nil then
    V.atFrame(8, function() Structure(); Actual(_G["RUINS"]) end)
else
    function Start() Structure(); engine:Exit() end
end
