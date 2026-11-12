-- 受控真实引擎回归；只由 -validate-test=ruins/tests/TimeLifecycleTest.lua 加载。
-- 使用已经初始化的 RUINS.scene/world，不 mock 体素、solver、Raycast 或 SphereCast。
-- 运行建议：main.lua ... -validate -validate-frames=20 -validate-timeout=100
--            -validate-test=ruins/tests/TimeLifecycleTest.lua -validate-output=<绝对报告路径>
--
-- 碰撞探针（单位 m；测试区 x>=160/y=80，远离遗迹地形与玩家）：
--             ray / sphere(r=.04) +Z → [实心 voxel 中心] →
--                   -3m          center             +3m
-- 原位 WHOLE → 动态碎块沿 +X 移动约 8m → 冻结仍可碰撞 → 回溯 visual 必须无 body。
-- 旧位置和原完整体都用两种查询检查；保留旧 userdata 引用，不靠 GC 掩盖残留。
-- 最大 90 碎块；预算满时必须拒绝细分而非截断 ids。网格计数、ids 唯一性和材质一起验证。

local V = _G["V"]
local TimeObject = require("ruins.TimeObject")
local Puzzles = require("ruins.RuinsPuzzles")

---@type TimeObject[]
local fixtures = {}
---@type VoxelVolume[]
local retired = {}
---@type VoxelPhysicsWorld|nil
local world = nil
local baseVolumes, baseBodies = 0, 0
local checks = 0

local function Check(condition, message)
    checks = checks + 1
    V.assert(condition, message)
    -- V.assert 收集报告；不让失败后的逻辑继续访问已经无效的对象。
    if not condition then error(message) end
end

local function NewFixture(scene, name, origin, shattered)
    local voxels = {}
    for i = 0, 7 do
        for j = 0, 7 do
            for k = 0, 7 do
                voxels[#voxels + 1] = { i, j, k, ((i + j + k) % 2) + 1 }
            end
        end
    end
    local object = TimeObject.New({ id = "lifecycle_" .. name, world = world, scene = scene,
        voxels = voxels, dims = { 8, 8, 8 }, size = 0.25, origin = origin, seed = 911,
        pieceGravity = 0, shattered = shattered, shatterLevel = 1,
        startScatter = shattered and function(self, p, rng)
            return p.restPos + Vector3(8, 0, 0), self.rot
        end or nil })
    fixtures[#fixtures + 1] = object
    return object
end

local function KeepVolumes(object)
    local before = {}
    if object.whole ~= nil then before[#before + 1] = object.whole end
    for _, p in ipairs(object.pieces) do before[#before + 1] = p.vol end
    for _, volume in ipairs(before) do retired[#retired + 1] = volume end
    return before
end

local function CheckRetired(before, message)
    for _, volume in ipairs(before) do
        Check(TimeObject.FindByVolume(volume) == nil and Puzzles.FindByVolume(volume) == nil, message .. "：旧 owner 已注销")
    end
end

local function CheckCounts(volumes, bodies, message)
    local actualVolumes, actualBodies = world:GetVolumeCount(), world:GetBodyCount()
    print(string.format("TimeLifecycleCount: %s volumes=%d expected=%d bodies=%d expected=%d",
        message, actualVolumes, baseVolumes+volumes, actualBodies, baseBodies+bodies))
    Check(actualVolumes == baseVolumes + volumes, message .. "：世界体积数无累积/丢失")
    Check(actualBodies == baseBodies + bodies, message .. "：真实 solver body 数正确")
end

local function CheckVoxels(object, message)
    if object.whole ~= nil then
        Check(object.whole:GetSolidCount() == #object.voxels, message .. "：完整体素守恒")
        Check(Puzzles.FindByVolume(object.whole) == object, message .. "：whole owner")
        return
    end
    Check(#object.pieces > 0 and #object.pieces <= 90, message .. "：最终碎块硬上限90")
    local seen, count = {}, 0
    for _, p in ipairs(object.pieces) do
        Check(p.vol ~= nil and p.node ~= nil, message .. "：无缺失残片")
        Check(p.vol:GetSolidCount() == #p.ids, message .. "：分组体素全部建入网格")
        Check(Puzzles.FindByVolume(p.vol) == object and object:Owns(p.vol), message .. "：piece owner")
        local grid = p.vol:GetGrid()
        local unique, intact = true, true
        for _, id in ipairs(p.ids) do
            if seen[id] then unique = false end
            seen[id] = true
            count = count + 1
            local v = object.voxels[id]
            local x, y, z = math.tointeger(v[1] - p.minI), math.tointeger(v[2] - p.minJ), math.tointeger(v[3] - p.minK)
            if not grid:IsSolid(x, y, z) or grid:GetVoxelMaterial(x, y, z) ~= v[4] then intact = false end
        end
        Check(unique, message .. "：原始 id 不重复")
        Check(intact, message .. "：全部体素位置及材质守恒")
    end
    Check(count == #object.voxels, message .. "：全部原始 ids 守恒")
end

local function Probe(position, rotation, owner, message)
    local direction = rotation * Vector3.FORWARD
    local start = position - direction * 3
    local ray = world:RaycastSingle(Ray(start, direction), 6)
    local sphere = world:SphereCast(Sphere(start, 0.04), direction, 6)
    if owner ~= nil then
        Check(ray.hit and Puzzles.FindByVolume(ray.volume) == owner, message .. "：Raycast 命中真实物件")
        Check(sphere.hit and Puzzles.FindByVolume(sphere.volume) == owner, message .. "：SphereCast 命中真实碰撞")
    else
        Check(not ray.hit, message .. "：Raycast 无旧残留")
        Check(not sphere.hit, message .. "：SphereCast 无旧残留")
    end
end

local function Probes(object)
    local probes = {}
    for _, p in ipairs(object.pieces) do
        local v = object.voxels[p.ids[1]]
        local localCenter = Vector3((v[1] - p.minI + 0.5) * object.size,
            (v[2] - p.minJ + 0.5) * object.size, (v[3] - p.minK + 0.5) * object.size)
        probes[#probes + 1] = { position = p.node.worldPosition + p.node.worldRotation * localCenter,
            rotation = p.node.worldRotation }
    end
    return probes
end

local function CheckProbes(probes, owner, message)
    for _, probe in ipairs(probes) do Probe(probe.position, probe.rotation, owner, message) end
end

local function FinishRewind(object)
    -- 受控时间，既覆盖 noTrack 弧线也覆盖有轨迹倒放/settle；不依赖真实帧时长。
    for i = 1, 100 do
        if object:IsWhole() then break end
        object:Update(0.1)
    end
    Check(object:IsWhole() and #object.pieces == 0, "回溯有限时间内重组完成")
end

-- 真实角色胶囊穿过旧碎块位置，不能只靠射线判断没有隐形占地。
local function WalkThrough(scene, position, rotation)
    local direction = rotation * Vector3.FORWARD
    local node = scene:CreateChild("LifecycleCharacterProbe")
    local cc = node:CreateComponent("VoxelCharacterController")
    cc.height, cc.radius, cc.gravityFactor = 1.65, 0.32, 0
    cc.collisionMask = 0xffffffff & ~2
    local start = position - direction * 1.5 - Vector3(0, 0.8, 0)
    cc:Teleport(start)
    cc.desiredVelocity = direction * 3
    for step = 1, 60 do world:Update(1 / 60) end
    local moved = (node.worldPosition - start):DotProduct(direction)
    cc:Dispose(); node:Dispose()
    Check(moved > 2.8, "回溯时角色胶囊穿过旧碎块位置，没有虚空阻挡")
end

local function Lifecycle(scene)
    local object = NewFixture(scene, "repeat", Vector3(160, 80, 0), false)
    local homeProbe = object.origin + Vector3(0.125, 0.125, 0.125)
    CheckCounts(1, 1, "初始完整体")
    for cycle = 1, 3 do
        Probe(homeProbe, object.rot, object, "完整物件可碰撞")
        local before = KeepVolumes(object)
        Check(object:Shatter({ level = 1, silent = true }), "重复 Shatter 成功")
        CheckRetired(before, "Shatter 释放原 whole")
        CheckCounts(#object.pieces, #object.pieces, "Shatter")
        CheckVoxels(object, "Shatter")
        for _, p in ipairs(object.pieces) do
            p.vol.linearVelocity = Vector3(20, 0, 0)
            p.vol.angularVelocity = Vector3.ZERO
            p.vol.linearDamping = 0
        end
        for step = 1, 24 do
            world:Update(1 / 60)
            object:Update(1 / 60)
        end
        Probe(homeProbe, object.rot, nil, "碎块离开后完整体旧位置")
        local oldPositions = Probes(object)
        before = KeepVolumes(object)
        Check(object:Freeze(8), "重复 Freeze 成功")
        CheckRetired(before, "Freeze 释放动态 body")
        CheckCounts(#object.pieces, #object.pieces, "Freeze")
        CheckProbes(oldPositions, object, "冻结静态残片仍可碰撞")
        local frozenPositions = Probes(object)
        world:Update(1 / 60)
        local after = Probes(object)
        for i, p in ipairs(after) do
            Check((p.position - frozenPositions[i].position):LengthSquared() < 1e-8, "冻结静止不下落")
        end
        before = KeepVolumes(object)
        object:Unfreeze()
        CheckRetired(before, "Unfreeze 释放静态 body")
        Check(object.state == "SHATTERED", "Unfreeze 恢复状态")
        CheckCounts(#object.pieces, #object.pieces, "Unfreeze")
        for _, p in ipairs(object.pieces) do
            Check((p.vol.linearVelocity - p.freezeVel):LengthSquared() < 1e-8 and
                (p.vol.angularVelocity - p.freezeAng):LengthSquared() < 1e-8, "Unfreeze 恢复冻结前线速度及角速度")
        end
        if cycle == 2 then Check(object:Freeze(8), "覆盖 FROZEN 发起回溯") end
        before = KeepVolumes(object)
        Check(object:Rewind(), "重复 Rewind 成功")
        CheckRetired(before, "Rewind 释放原残骸")
        CheckCounts(#object.pieces, 0, "Rewind visual")
        for _, p in ipairs(object.pieces) do
            Check(p.mode == "visual" and p.vol.collisionMask == 0 and not p.vol:IsCollidable(), "回溯仅视觉且mask=0")
        end
        CheckVoxels(object, "Rewind visual")
        CheckProbes(oldPositions, nil, "回溯开始时旧残骸位置")
        if cycle == 1 then WalkThrough(scene, oldPositions[1].position, oldPositions[1].rotation) end
        object:Update(0.1)
        world:Update(1 / 60)
        CheckProbes(oldPositions, nil, "物理步之后仍无旧碰撞")
        before = KeepVolumes(object)
        FinishRewind(object)
        CheckRetired(before, "Reassemble 释放所有 visual")
        CheckCounts(1, 1, "Reassemble")
        CheckVoxels(object, "Reassemble")
        CheckProbes(oldPositions, nil, "重组完成后旧残骸位置")
    end
    local before = KeepVolumes(object)
    object:Dispose()
    object:Dispose() -- 显式释放幂等
    CheckRetired(before, "Dispose whole")
    CheckCounts(0, 0, "对象重复 Dispose")
    Probe(homeProbe, object.rot, nil, "Dispose 后原位置")
end

local function ScatterAndRefine(scene)
    local rubble = NewFixture(scene, "scatter", Vector3(180, 80, 0), true)
    Check(rubble.whole == nil and rubble.state == "FROZEN", "开局散落没有构建 whole")
    CheckCounts(#rubble.pieces, #rubble.pieces, "直接开局散落")
    CheckVoxels(rubble, "开局散落")
    Probe(rubble.origin + Vector3(0.125, 0.125, 0.125), rubble.rot, nil, "开局原 whole 位置无残留")
    local oldPositions, before = Probes(rubble), KeepVolumes(rubble)
    Check(rubble:Rewind() and rubble.noTrack, "开局散落覆盖 noTrack 回溯")
    CheckRetired(before, "开局回溯释放静态残片")
    CheckCounts(#rubble.pieces, 0, "开局 visual")
    CheckProbes(oldPositions, nil, "开局旧残骸位置无碰撞")
    before = KeepVolumes(rubble)
    FinishRewind(rubble)
    CheckRetired(before, "开局重组释放 visual")
    CheckCounts(1, 1, "开局回溯重组")
    rubble:Dispose()
    CheckCounts(0, 0, "开局物件释放")

    local object = NewFixture(scene, "refine", Vector3(200, 80, 0), false)
    Check(object:Shatter({ level = 1, silent = true }), "低级 Shatter 为再次细分准备")
    for attempt = 1, 12 do
        local changed = object:Shatter({ level = 3, point = object.center, radius = 100, silent = true })
        CheckVoxels(object, "再次细分")
        CheckCounts(#object.pieces, #object.pieces, "再次细分")
        if not changed then break end
    end
    Check(#object.pieces == 90, "对抗性细分达到90但不超过90")
    local beforeCap = KeepVolumes(object)
    Check(not object:Refine({ point = object.center, radius = 100 }), "预算满拒绝继续细分")
    for i, p in ipairs(object.pieces) do Check(p.vol == beforeCap[i], "预算满不重建/截断旧残片") end
    Check(object:Freeze(8), "细分后冻结")
    CheckVoxels(object, "细分后冻结")
    Check(object:Rewind(), "细分后回溯")
    CheckCounts(90, 0, "90个visual无body")
    FinishRewind(object)
    CheckVoxels(object, "90块回溯仍恢复全部体素")
    CheckCounts(1, 1, "90块重组")
    -- 第三级初碎同样必须限额并守恒，不仅修 Refine。
    Check(object:Shatter({ level = 3, silent = true }), "第三级初始碎裂")
    CheckVoxels(object, "第三级初碎")
    CheckCounts(#object.pieces, #object.pieces, "第三级初碎")
    local before = KeepVolumes(object)
    object:Dispose()
    CheckRetired(before, "Dispose pieces")
    CheckCounts(0, 0, "细分对象释放")
end

V.atFrame(5, function()
    local game = _G["RUINS"]
    Check(game ~= nil and game.scene ~= nil and game.world ~= nil, "真实 RUINS 场景已初始化")
    world = game.world
    baseVolumes, baseBodies = world:GetVolumeCount(), world:GetBodyCount()
    local automatic = world:IsUpdateEnabled()
    world:SetUpdateEnabled(false)
    local ok, err = pcall(function()
        Lifecycle(game.scene)
        ScatterAndRefine(game.scene)
        CheckCounts(0, 0, "全部生命周期完成")
    end)
    -- 不论是否失败，都清理测试实例并恢复世界步进；不修改谜题进度/玩家/项目配置。
    for _, object in ipairs(fixtures) do object:Dispose() end
    world:SetUpdateEnabled(automatic)
    if not ok then error(err) end
    print(string.format("TimeLifecycleTest: PASS, %d checks, base volumes=%d bodies=%d; no GC cleanup", checks, baseVolumes, baseBodies))
end)

-- 正常 RUINS 继续运行几个真实帧，确认无延迟残留；不要和其他变更世界的测试合跑。
V.atFrame(10, function()
    CheckCounts(0, 0, "恢复自动步进后体积/body不累积")
    Check(#retired > 0, "测试持有旧 userdata，不靠 GC")
end)
