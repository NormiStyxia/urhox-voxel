-- ====================================================================
-- TimeObject.lua — 时之物件：可被诺米「碎时」打散、「冻结」定格、「回溯」重组的体素物件
--
-- 数据模型（回溯的关键：永远保留一份原始体素快照）：
--   self.voxels   = { {i,j,k,mat}, ... }       原始体素（物件局部格坐标）
--   self.home     = 物件完整时的世界变换（origin + yaw）
--   self.pieces   = 碎块列表，每块 = 一个动态 VoxelVolume，记录它包含哪些原始体素、
--                   在物件局部坐标里的偏移，以及一条运动轨迹（定时采样的世界位姿）
--
-- 状态机：
--   WHOLE    完整（静态体积，可站人）
--   SHATTERED 已碎（碎块是动态刚体，物理在跑，同时录轨迹）
--   FROZEN   冻结（碎块显式释放动态 body 后重建为静态体积，可以踩）
--   REWIND   回溯（碎块沿录下的轨迹倒放 → 最后一段插值回原位 → 合并成完整物件）
--
-- 碎裂算法（大小不一的碎块）：
--   在物件包围盒里随机撒 N 个种子（数量随伤害等级），每个体素归属最近的种子（带权重的
--   Voronoi，权重随机 → 有大块也有小块）；最小单元模式下每个体素自成一块。
--   每个 Voronoi 单元再按 6 邻接拆成连通块，避免一块碎片里出现悬空离散体素。
--
-- 体素数目大时碎块很多，碎块数受 MAX_PIECES 限制；超出的单元合并到最近的种子。
-- ====================================================================

local Noise = require("ruins.Noise")
local DebugLog = require("ruins.DebugLog")

local M = {}

-- 统一索引所有 live 体积（包括无碰撞的回溯残片）；释放前必须注销。
---@type table<VoxelVolume, TimeObject>
local volumeOwners = {}

---@param volume VoxelVolume|nil
---@return TimeObject|nil
function M.FindByVolume(volume)
    if volume == nil then return nil end
    return volumeOwners[volume]
end

local MAX_PIECES = 90         -- 单个物件最多碎块数
local RECORD_DT = 1.0 / 20.0  -- 轨迹采样间隔
local MAX_RECORD = 12.0       -- 最多记录多少秒（之后静止的碎块不再采样）
local REWIND_SPEED = 2.2      -- 回溯倍速（相对录制时长）
local REWIND_SETTLE = 0.6     -- 轨迹倒放完后插值归位的时长

M.STATE = { WHOLE = "WHOLE", SHATTERED = "SHATTERED", FROZEN = "FROZEN", REWIND = "REWIND" }

---@class TimePiece
---@field vol VoxelVolume|nil
---@field node Node|nil
---@field ids integer[]        原始体素下标
---@field minI integer
---@field minJ integer
---@field minK integer
---@field nx integer
---@field ny integer
---@field nz integer
---@field track table[]        { t, pos, rot }
---@field restPos Vector3      碎块完整时的世界位置（体积最小角）
---@field restRot Quaternion
---@field frozen boolean
---@field mode string|nil      dynamic / static / visual（不把 IsStatic 当成无 body 的判定）
---@field aimSlot Vector3|nil
---@field aimT number|nil
---@field aimFrom Vector3|nil
---@field aimLanded boolean|nil
---@field freezeVel Vector3|nil
---@field freezeAng Vector3|nil
---@field from table|nil       { pos: Vector3, rot: Quaternion }

---@class TimeObject
---@field id string
---@field title string
---@field lastMode number|nil  shader mode 是浮点参数；nil 表示尚未同步
---@field world VoxelPhysicsWorld
---@field scene Scene
---@field voxels table[]
---@field size number
---@field center Vector3
---@field fixedSeeds table[]|nil
---@field shatterAim fun(self: TimeObject, pieces: TimePiece[], rng: table)|nil
---@field radius number
---@field origin Vector3
---@field yaw number
---@field rot Quaternion
---@field dims integer[]
---@field state string
---@field whole VoxelVolume|nil
---@field pieces TimePiece[]
---@field material Material
---@field time number
---@field recT number
---@field rewindT number
---@field fx number
---@field hover number
---@field hoverColor Color|nil
---@field lastHoverColor Color|nil
---@field marker Node|nil
---@field listeners table
---@field canShatter boolean
---@field canRewind boolean
---@field canFreeze boolean
local T = {}
T.__index = T

local function Clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
local function Smooth(t) t = Clamp(t, 0, 1) return t * t * (3 - 2 * t) end

-- 时之物件共享材质（同一调色板库的体积可共享；按 mode 分三份）
local mats = {}
---@param world VoxelPhysicsWorld
function M.Material(world, mode, size)
    local key = mode .. "_" .. size
    local m = mats[key]
    if m ~= nil then return m end
    m = Material:new()
    if m:SetSurfaceShader("Shaders/BLGL/TimeVoxel.shader") then
        m:SetSurfaceTexture("palette_tex", world:GetPaletteTexture())
        m:SetShaderParameter("mode", Variant(mode))
        m:SetShaderParameter("voxel_size", Variant(size))
        m:SetShaderParameter("strength", Variant(1.0))
    else
        print("TimeObject: TimeVoxel.shader failed, fallback to palette material")
        m = world:GetPaletteMaterial()
    end
    mats[key] = m
    return m
end

-- 每个物件单独一份「印记」材质，方便单独调 hover / strength
local function OwnMaterial(world, size)
    local m = Material:new()
    if m:SetSurfaceShader("Shaders/BLGL/TimeVoxel.shader") then
        m:SetSurfaceTexture("palette_tex", world:GetPaletteTexture())
        m:SetShaderParameter("mode", Variant(0.0))
        m:SetShaderParameter("voxel_size", Variant(size))
        m:SetShaderParameter("strength", Variant(1.0))
        return m
    end
    return world:GetPaletteMaterial()
end

-- o = { id, world, scene, voxels, size, origin, yaw, dims, shattered(初始即碎), seed,
--       canShatter, canRewind, canFreeze, startScatter = function(piece, rng) → pos, rot }
function M.New(o)
    local self = setmetatable({}, T)
    self.id = o.id
    self.world = o.world
    self.scene = o.scene
    self.voxels = o.voxels
    self.size = o.size
    self.origin = o.origin
    self.yaw = o.yaw or 0
    self.rot = Quaternion(self.yaw, Vector3.UP)
    self.dims = o.dims
    self.seed = o.seed or 1
    self.state = M.STATE.WHOLE
    self.pieces = {}
    self.time = 0
    self.recT = 0
    self.rewindT = 0
    self.fx = 0
    self.hover = 0
    self.listeners = {}
    self.canShatter = o.canShatter ~= false
    self.canRewind = o.canRewind ~= false
    self.canFreeze = o.canFreeze ~= false
    self.freezeTime = o.freezeTime
    self.pieceGravity = o.pieceGravity or 1.0  -- 碎块重力倍率（悬石用 0.4：遗迹里时间流速偏慢）
    self.shatterPower = o.shatterPower or 1.0
    self.material = OwnMaterial(self.world, self.size)
    self.effectMaterials = {}
    self.lastHover = -1
    -- 体素中心（世界坐标）的包围盒，用于瞄准高亮和距离判定
    local s = self.size
    self.center = self.origin + self.rot * Vector3(self.dims[1] * s * 0.5, self.dims[2] * s * 0.5, self.dims[3] * s * 0.5)
    self.radius = math.sqrt(self.dims[1] ^ 2 + self.dims[2] ^ 2 + self.dims[3] ^ 2) * s * 0.5
    -- 开局散落直接生成残片；不要先建立整桥/整碑再删掉那份碰撞。
    if o.shattered then
        self:Shatter({ level = o.shatterLevel or 1, point = self.center, scatter = o.startScatter, silent = true, force = true })
        self:SettleAsRubble()
    else
        self:BuildWhole()
    end
    print(string.format("TimeObject[%s]: %d voxels, %dx%dx%d @%.2fm", self.id, #self.voxels,
        self.dims[1], self.dims[2], self.dims[3], s))
    return self
end

function T:On(fn) self.listeners[#self.listeners + 1] = fn end
function T:Emit(ev, data)
    for _, fn in ipairs(self.listeners) do fn(self, ev, data) end
end

-- ---------------------------------------------------------------- 完整体积
function T:EffectMaterial(mode)
    if self.effectMaterials[mode] == nil then
        local m=OwnMaterial(self.world,self.size)
        m:SetShaderParameter("mode",Variant(mode))
        m:SetShaderParameter("hover",Variant(self.hover or 0))
        if self.hoverColor ~= nil then m:SetShaderParameter("hover_color",Variant(self.hoverColor)) end
        self.effectMaterials[mode]=m
    end
    return self.effectMaterials[mode]
end

function T:BuildWhole()
    self:RemoveWhole() -- 幂等：世界内只保留一个完整体积。
    local s = self.size
    local d = self.dims
    local vol = self.world:CreateVolume(d[1], d[2], d[3], s, self.origin, self.rot)
    local g = vol:GetGrid()
    for _, v in ipairs(self.voxels) do
        g:SetSolid(v[1], v[2], v[3], true)
        g:SetVoxelMaterial(v[1], v[2], v[3], v[4])
    end
    vol.destructible = false -- 破坏走自己的碎裂逻辑，不走引擎弹坑
    vol.evictable = false
    vol.material = self.material
    self.world:FinalizeVolume(vol)
    vol:RebuildGeometry()
    vol:GetNode().name = "Time_" .. self.id
    self.whole = vol
    volumeOwners[vol] = self
end

-- 世界注册表与 component 生命周期分别释放；单独 Dispose 可能留下 world 空槽。
-- 先 mask=0，再注销体积并显式释放，不依赖 GC。
---@param world VoxelPhysicsWorld
---@param volume VoxelVolume
local function DisposeVolume(world, volume)
    local node = volume:GetNode()
    volumeOwners[volume] = nil
    volume.collisionMask = 0
    world:RemoveVolume(volume)
    volume:Dispose()
    if node ~= nil then node:Dispose() end
end

function T:RemoveWhole()
    if self.whole ~= nil then
        DisposeVolume(self.world, self.whole) -- 注销世界体积并立即释放。
        self.whole = nil
    end
end

function T:Dispose()
    self:RemoveWhole()
    for _, p in ipairs(self.pieces) do self:RemovePieceVolume(p) end
    self.pieces = {}
    self.listeners = {}
end

-- 物件局部格坐标 → 世界坐标（格最小角）
function T:LocalToWorld(i, j, k)
    local s = self.size
    return self.origin + self.rot * Vector3(i * s, j * s, k * s)
end

-- 世界点 → 物件局部格坐标（浮点）
function T:WorldToLocal(p)
    local inv = self.rot:Inverse()
    local l = inv * (p - self.origin)
    return l.x / self.size, l.y / self.size, l.z / self.size
end

-- ---------------------------------------------------------------- 碎裂分块
-- level: 1 = 大块（6–10 块）、2 = 中块（18–30）、3 = 最小单元（每个体素一块，受上限约束时退化为 2x2x2 小块）
function T:Partition(level, hitLocal)
    local rng = Noise.Rng(self.seed * 7919 + math.floor(self.time * 1000))
    local vox = self.voxels
    local n = #vox
    local assign = {}
    if level >= 3 then
        -- 最小单元：体素量太大时按 2x2x2 分组，保证块数不爆
        local cellK = (n > MAX_PIECES * 6) and 2 or 1
        if n <= MAX_PIECES then cellK = 1 end
        local map, count = {}, 0
        for idx, v in ipairs(vox) do
            local key = (v[1] // cellK) * 1000000 + (v[2] // cellK) * 1000 + (v[3] // cellK)
            local g = map[key]
            if g == nil then count = count + 1; g = count; map[key] = g end
            assign[idx] = g
        end
        return assign, count
    end
    local want = (level == 1) and rng:Int(6, 10) or rng:Int(18, 30)
    want = math.min(want, math.max(2, n // 6), MAX_PIECES)
    -- 种子：一半撒在命中点附近（碎得更细），一半全局随机；物件可用 fixedSeeds 指定固定种子（谜题用）
    local seeds = {}
    if level == 1 and self.fixedSeeds ~= nil then
        for si, sd in ipairs(self.fixedSeeds) do seeds[si] = sd end
        want = #seeds
    end
    local d = self.dims
    for si = #seeds + 1, want do
        local near = hitLocal ~= nil and si <= want // 2
        local sx, sy, sz
        if near then
            local r = math.max(d[1], d[2], d[3]) * 0.25
            sx = hitLocal[1] + rng:Range(-r, r)
            sy = hitLocal[2] + rng:Range(-r, r)
            sz = hitLocal[3] + rng:Range(-r, r)
        else
            local v = vox[rng:Int(1, n)]
            sx, sy, sz = v[1] + rng:Range(-1, 1), v[2] + rng:Range(-1, 1), v[3] + rng:Range(-1, 1)
        end
        seeds[si] = { sx, sy, sz, rng:Range(0.6, 1.6) } -- 第 4 项：权重（越大块越大）
    end
    for idx, v in ipairs(vox) do
        local best, bd = 1, 1e18
        for si, sd in ipairs(seeds) do
            local dx, dy, dz = v[1] - sd[1], v[2] - sd[2], v[3] - sd[3]
            local dist = (dx * dx + dy * dy + dz * dz) / (sd[4] * sd[4])
            if dist < bd then bd, best = dist, si end
        end
        assign[idx] = best
    end
    return assign, want
end

-- 超预算只合并分组，不删原始 ids。Refine 仅合并同一母块（位姿/轨迹一致）的子块；
-- 不把已经飞到不同位置的旧碎块硬并成一个体积，否则会凭空移动碰撞。
local function LimitComponents(voxels, components, limit)
    if #components <= limit then return components end
    table.sort(components, function(a, b) return #a > #b end)
    local keep, anchors = {}, {}
    for i = 1, limit do
        keep[i] = components[i]
        local v = voxels[components[i][1]]
        anchors[i] = { v[1], v[2], v[3] }
    end
    for i = limit + 1, #components do
        local component = components[i]
        local v = voxels[component[1]]
        local best, distance = 1, math.huge
        for j, anchor in ipairs(anchors) do
            local dx, dy, dz = v[1] - anchor[1], v[2] - anchor[2], v[3] - anchor[3]
            local d = dx * dx + dy * dy + dz * dz
            if d < distance then best, distance = j, d end
        end
        local target = keep[best]
        for _, id in ipairs(component) do target[#target + 1] = id end
    end
    return keep
end

-- 把每个分组按 6 邻接拆成连通块，返回 { {ids...}, ... }
function T:Components(assign, groups)
    local vox = self.voxels
    local index = {}
    for idx, v in ipairs(vox) do index[v[1] * 1000000 + v[2] * 1000 + v[3]] = idx end
    local seen = {}
    local out = {}
    local NB = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }
    for idx = 1, #vox do
        if not seen[idx] then
            local g = assign[idx]
            local comp = { idx }
            seen[idx] = true
            local head = 1
            while head <= #comp do
                local ci = comp[head] or 1
                local v = vox[ci]
                head = head + 1
                for _, nb in ipairs(NB) do
                    local key = (v[1] + nb[1]) * 1000000 + (v[2] + nb[2]) * 1000 + (v[3] + nb[3])
                    local ni = index[key]
                    if ni ~= nil and not seen[ni] and assign[ni] == g then
                        seen[ni] = true
                        comp[#comp + 1] = ni
                    end
                end
            end
            out[#out + 1] = comp
        end
    end
    -- 完整体超过预算时也守恒全部体素；聚合组可能含不相连的小岛，但空格不填实。
    return LimitComponents(vox, out, MAX_PIECES)
end

-- 生成碎块体积（位于完整时的原位）
---@return TimePiece
function T:MakePiece(ids, dynamic, pos, rot)
    local vox = self.voxels
    local i0, j0, k0, i1, j1, k1 = 1e9, 1e9, 1e9, -1e9, -1e9, -1e9
    for _, id in ipairs(ids) do
        local v = vox[id]
        if v[1] < i0 then i0 = v[1] end
        if v[2] < j0 then j0 = v[2] end
        if v[3] < k0 then k0 = v[3] end
        if v[1] > i1 then i1 = v[1] end
        if v[2] > j1 then j1 = v[2] end
        if v[3] > k1 then k1 = v[3] end
    end
    local nx, ny, nz = i1 - i0 + 1, j1 - j0 + 1, k1 - k0 + 1
    ---@type TimePiece
    local p = { ids = ids, minI = i0, minJ = j0, minK = k0, nx = nx, ny = ny, nz = nz, track = {}, frozen = false }
    p.restPos = self:LocalToWorld(i0, j0, k0)
    p.restRot = self.rot
    if dynamic ~= nil then self:SpawnPieceVolume(p, dynamic, pos or p.restPos, rot or p.restRot) end
    return p
end

---@param p TimePiece
function T:SpawnPieceVolume(p, dynamic, pos, rot)
    -- 幂等重建：不允许覆写 live vol 引用后遗失其 body。
    self:RemovePieceVolume(p)
    local s = self.size
    local vol = self.world:CreateVolume(math.tointeger(p.nx) or 1, math.tointeger(p.ny) or 1, math.tointeger(p.nz) or 1, s, pos, rot)
    local g = vol:GetGrid()
    local vox = self.voxels
    for _, id in ipairs(p.ids) do
        local v = vox[id]
        local x, y, z = math.tointeger(v[1] - p.minI) or 0, math.tointeger(v[2] - p.minJ) or 0, math.tointeger(v[3] - p.minK) or 0
        g:SetSolid(x, y, z, true)
        g:SetVoxelMaterial(x, y, z, v[4])
    end
    vol.destructible = false
    vol.evictable = false
    vol.material = self.material
    if dynamic == "dynamic" then
        vol.density = 1800.0
        vol.linearDamping = 0.05
        vol.angularDamping = 0.15
        vol.gravityFactor = self.pieceGravity
        self.world:FinalizeVolumeAsDynamic(vol)
    elseif dynamic == "static" then
        self.world:FinalizeVolume(vol)
    else
        -- 没有 Finalize = 无 solver body；mask=0 也排除角色/查询的粗筛路径。
        -- SetCollidable(false) 仅保留到场景载入时，不是运行时 body 开关。
        vol:SetCollidable(false)
        vol.collisionMask = 0
    end
    vol:RebuildGeometry()
    vol:GetNode().name = "TimePiece_" .. self.id
    p.vol = vol
    p.node = vol:GetNode()
    p.mode = dynamic
    volumeOwners[vol] = self
end

---@param p TimePiece
function T:RemovePieceVolume(p)
    if p.vol ~= nil then
        DisposeVolume(self.world, p.vol) -- 同一释放路径覆盖所有碎块模式。
        p.vol, p.node, p.mode = nil, nil, nil
    end
end

-- API 没有公开 static/dynamic/bodyless 原地切换；反复 Finalize 的旧 body 清理
-- 未文档化，不能冒险。需要转换时真正释放再建；同模式只改 Node（visual 无 body）。
---@param p TimePiece
function T:SetPieceMode(p, mode, pos, rot)
    if p.vol ~= nil and p.mode == mode then
        if mode == "visual" then
            p.node.worldPosition = pos
            p.node.worldRotation = rot
            return
        end
        -- 静态/动态 Node 移动不保证 solver teleport；只有完全相同的位姿可以跳过重建。
        if p.node.worldPosition == pos and p.node.worldRotation == rot then return end
    end
    self:SpawnPieceVolume(p, mode, pos, rot)
end

-- ---------------------------------------------------------------- 碎时
-- o = { level, point(世界命中点), dir(冲击方向), power, scatter, silent }
function T:Shatter(o)
    o = o or {}
    if not self.canShatter and not o.force then return false end
    if self.state == M.STATE.REWIND then return false end
    local level = o.level or 1
    -- 已碎：再次碎时 → 把命中点附近的碎块进一步细分
    if self.state == M.STATE.SHATTERED or self.state == M.STATE.FROZEN then
        return self:Refine(o)
    end
    local hl = nil
    if o.point ~= nil then
        local x, y, z = self:WorldToLocal(o.point)
        hl = { x, y, z }
    end
    local assign, groups = self:Partition(level, hl)
    local comps = self:Components(assign, groups)
    self:RemoveWhole()
    self.pieces = {}
    local rng = Noise.Rng(self.seed * 131 + #comps)
    for _, ids in ipairs(comps) do
        local p
        if o.scatter ~= nil then
            -- 开局散落：直接在散落位置生成静态碎块
            p = self:MakePiece(ids, nil)
            local pos, rot = o.scatter(self, p, rng)
            self:SpawnPieceVolume(p, "static", pos, rot)
            p.track = { { t = 0, pos = pos, rot = rot } }
            p.frozen = true
        else
            p = self:MakePiece(ids, "dynamic")
        end
        self.pieces[#self.pieces + 1] = p
    end
    -- 冲击：从命中点向外的径向冲量 + 沿施法方向
    if o.scatter == nil and self.shatterAim ~= nil then
        -- 物件自定义碎块飞行（谜题用：让碎块按设计路径散开）
        self.shatterAim(self, self.pieces, rng)
    elseif o.point ~= nil and o.scatter == nil then
        local power = (o.power or 1.0) * self.shatterPower
        for _, p in ipairs(self.pieces) do
            local v = p.vol
            if v ~= nil then
                local c = p.node.worldPosition + p.node.worldRotation * Vector3(p.nx * self.size * 0.5, p.ny * self.size * 0.5, p.nz * self.size * 0.5)
                local away = c - o.point
                local dist = math.max(0.3, away:Length())
                local dir = away:Normalized()
                local push = dir * (3.5 / (0.6 + dist * 0.35)) + Vector3(0, 2.2, 0)
                if o.dir ~= nil then push = push + o.dir * 2.5 end
                push = push * power * (0.7 + rng:Next() * 0.6)
                v.linearVelocity = push
                v.angularVelocity = Vector3(rng:Range(-4, 4), rng:Range(-4, 4), rng:Range(-4, 4))
            end
        end
    end
    self.restored = false
    self.material:SetShaderParameter("restored", Variant(0.0))
    self.state = M.STATE.SHATTERED
    self.recT = 0
    self.recAcc = 0
    if o.scatter == nil then self:RecordAll(0) end
    if not o.silent then self:Emit("shatter", { level = level, count = #self.pieces }) end
    if DebugLog.enabled then DebugLog.Log("TimeObject","TimeObject[%s]: shattered into %d pieces (level %d)", self.id, #self.pieces, level) end
    return true
end

-- 已碎再碎：命中点 2.2m 内的碎块重新分成更小的块（level+1）
function T:Refine(o)
    local pt = o.point
    if pt == nil or #self.pieces >= MAX_PIECES then return false end
    local s = self.size
    local changed, extra = 0, MAX_PIECES - #self.pieces
    local newList = {}
    local rng = Noise.Rng(self.seed * 17 + #self.pieces)
    for _, p in ipairs(self.pieces) do
        local c = p.node ~= nil and (p.node.worldPosition + p.node.worldRotation * Vector3(p.nx * s * 0.5, p.ny * s * 0.5, p.nz * s * 0.5)) or p.restPos
        if extra > 0 and p.node ~= nil and (c - pt --[[@as Vector3]]):Length() < (o.radius or 2.2) + math.max(p.nx, p.ny, p.nz) * s * 0.5 and #p.ids > 1 and changed < 6 then
            -- 先确定预算内的最终子组，再释放母块；不能先造超量碎块再截断 newList。
            local cellK = (#p.ids > 64) and 2 or 1
            local groups, components = {}, {}
            for _, id in ipairs(p.ids) do
                local v = self.voxels[id]
                local key = ((v[1] - p.minI) // cellK) * 1000000 + ((v[2] - p.minJ) // cellK) * 1000 + ((v[3] - p.minK) // cellK)
                if groups[key] == nil then
                    groups[key] = {}
                    components[#components + 1] = groups[key]
                end
                local group = groups[key]
                group[#group + 1] = id
            end
            components = LimitComponents(self.voxels, components, extra + 1)
            if #components > 1 then
                changed = changed + 1
                extra = extra - (#components - 1)
                local pos, rot = p.node.worldPosition, p.node.worldRotation
                local vel = (p.vol ~= nil and not p.frozen) and p.vol.linearVelocity or Vector3.ZERO
                self:RemovePieceVolume(p)
                for _, ids in ipairs(components) do
                    local q = self:MakePiece(ids, nil)
                    local off = Vector3((q.minI - p.minI) * s, (q.minJ - p.minJ) * s, (q.minK - p.minK) * s)
                    local qpos = pos + rot * off
                    self:SpawnPieceVolume(q, "dynamic", qpos, rot)
                    -- 有限量继承母块轨迹；所有原始 ids 和轨迹坐标都保留，回溯可精确归位。
                    for _, tr in ipairs(p.track) do
                        q.track[#q.track + 1] = { t = tr.t, pos = tr.pos + tr.rot * off, rot = tr.rot }
                    end
                    local away = (qpos - pt):Normalized()
                    q.vol.linearVelocity = vel + away * rng:Range(2.0, 4.5) + Vector3(0, rng:Range(1.0, 3.0), 0)
                    q.vol.angularVelocity = Vector3(rng:Range(-6, 6), rng:Range(-6, 6), rng:Range(-6, 6))
                    newList[#newList + 1] = q
                end
            else
                newList[#newList + 1] = p
            end
        else
            newList[#newList + 1] = p
        end
    end
    if changed == 0 then return false end
    self.pieces = newList
    self.state = M.STATE.SHATTERED
    self:Emit("shatter", { level = 3, count = #self.pieces })
    if DebugLog.enabled then DebugLog.Log("TimeObject","TimeObject[%s]: refined %d pieces → %d", self.id, changed, #self.pieces) end
    return true
end

-- 开局散落：碎块直接变成静态（轨迹只有一个点：当前位置；回溯时从这里飞回家）
function T:SettleAsRubble()
    for _, p in ipairs(self.pieces) do
        if p.node ~= nil then
            self:SetPieceMode(p, "static", p.node.worldPosition, p.node.worldRotation)
            p.frozen = true
        end
    end
    self.state = M.STATE.FROZEN
    self.rubble = true
    self.recT = 0
end

-- ---------------------------------------------------------------- 轨迹录制
function T:RecordAll(t)
    for _, p in ipairs(self.pieces) do
        if p.node ~= nil then
            local tr = p.track
            local last = tr[#tr]
            local pos, rot = p.node.worldPosition, p.node.worldRotation
            -- 静止不动的碎块不重复记点（省内存）；倒放时按时间戳插值，空档自然是静止
            if last == nil or (last.pos - pos):LengthSquared() > 1e-5 or math.abs(last.rot:DotProduct(rot)) < 0.99999 then
                tr[#tr + 1] = { t = t, pos = pos, rot = rot }
            end
        end
    end
end

-- ---------------------------------------------------------------- 冻结
function T:Freeze(duration)
    if not self.canFreeze then return false end
    if self.state == M.STATE.WHOLE then
        -- 完整物件冻结：只做表现（材质切到冰），用于「冻结机关」
        self.frozenWhole = duration or 8.0
        self:Emit("freeze", {})
        return true
    end
    if self.state ~= M.STATE.SHATTERED then return false end
    -- 含坠入虚空的 visual 残片也转静态；冻结期间所有残片都必须能踩。
    self:RecordAll(math.min(self.recT, MAX_RECORD))
    for _, p in ipairs(self.pieces) do
        if p.vol ~= nil and p.mode ~= "static" then
            local pos, rot = p.node.worldPosition, p.node.worldRotation
            p.freezeVel = p.vol.linearVelocity
            p.freezeAng = p.vol.angularVelocity
            self:SetPieceMode(p, "static", pos, rot)
            p.frozen = true
            p.vol.material = self:EffectMaterial(1.0)
        end
    end
    self.state = M.STATE.FROZEN
    self.freezeLeft = duration or 8.0
    self:Emit("freeze", {})
    if DebugLog.enabled then DebugLog.Log("TimeObject","TimeObject[%s]: frozen %d pieces for %.1fs", self.id, #self.pieces, self.freezeLeft) end
    return true
end

-- 冻结结束：碎块恢复冻结前的速度继续下落（开局散落的不恢复）
function T:Unfreeze()
    if self.state ~= M.STATE.FROZEN then return end
    if self.rubble then return end
    for _, p in ipairs(self.pieces) do
        if p.frozen and p.vol ~= nil then
            local pos, rot = p.node.worldPosition, p.node.worldRotation
            self:SetPieceMode(p, "dynamic", pos, rot)
            p.vol.linearVelocity = p.freezeVel or Vector3.ZERO
            p.vol.angularVelocity = p.freezeAng or Vector3.ZERO
            p.frozen = false
        end
    end
    self.state = M.STATE.SHATTERED
    self:Emit("unfreeze", {})
end

-- ---------------------------------------------------------------- 回溯
function T:Rewind()
    if not self.canRewind then return false end
    if self.state ~= M.STATE.SHATTERED and self.state ~= M.STATE.FROZEN then return false end
    -- 轨迹终点：最后一次真正有运动的采样时间（之后碎块都是静止的，不浪费回放时间）
    local lastMove = 0
    for _, p in ipairs(self.pieces) do
        local last = p.track[#p.track]
        if last ~= nil and last.t > lastMove then lastMove = last.t end
    end
    local tEnd = math.min(lastMove + 0.15, MAX_RECORD)
    for _, p in ipairs(self.pieces) do
        if p.node ~= nil then
            local pos, rot = p.node.worldPosition, p.node.worldRotation
            self:SetPieceMode(p, "visual", pos, rot)
            p.vol.material = self:EffectMaterial(2.0)
            p.track[#p.track + 1] = { t = tEnd, pos = pos, rot = rot }
            p.from = { pos = pos, rot = rot }
        end
        p.frozen = false
    end
    -- 没有真实轨迹（开局散落 / 刚碎就回溯）：碎块沿弧线依次飞回
    self.noTrack = lastMove < 0.3
    self.rewindFrom = tEnd
    self.rewindLen = self.noTrack and (1.8 + math.min(1.2, #self.pieces * 0.02)) or math.max(1.0, tEnd / REWIND_SPEED)
    self.rewindT = 0
    self.state = M.STATE.REWIND
    self:Emit("rewind_start", { duration = self.rewindLen + REWIND_SETTLE })
    if DebugLog.enabled then DebugLog.Log("TimeObject","TimeObject[%s]: rewinding %d pieces, track %.2fs, noTrack=%s", self.id, #self.pieces, tEnd, tostring(self.noTrack)) end
    return true
end

-- 轨迹按时间插值
local function Sample(track, t)
    local n = #track
    if n == 0 then return nil, nil end
    if t <= track[1].t then return track[1].pos, track[1].rot end
    if t >= track[n].t then return track[n].pos, track[n].rot end
    -- 二分
    local lo, hi = 1, n
    while hi - lo > 1 do
        local mid = (lo + hi) // 2
        if track[mid].t <= t then lo = mid else hi = mid end
    end
    local a, b = track[lo], track[hi]
    local u = (t - a.t) / math.max(1e-6, b.t - a.t)
    return a.pos:Lerp(b.pos, u), a.rot:Slerp(b.rot, u)
end

function T:UpdateRewind(dt)
    self.rewindT = self.rewindT + dt
    local len = self.rewindLen
    if self.noTrack then
        -- 依次起飞：按离原位远近错开，弧线 + 旋转回正
        local n = #self.pieces
        local stagger = math.min(0.8, len * 0.35)
        for idx, p in ipairs(self.pieces) do
            if p.node ~= nil and p.from ~= nil then
                local delay = stagger * ((idx * 0.618) % 1.0)
                local w = Smooth((self.rewindT - delay) / (len - stagger))
                local dist = (p.from.pos - p.restPos):Length()
                local lift = math.sin(w * math.pi) * (0.8 + dist * 0.25)
                p.node.worldPosition = p.from.pos:Lerp(p.restPos, w) + Vector3(0, lift, 0)
                p.node.worldRotation = p.from.rot:Slerp(p.restRot, w)
            end
        end
        if self.rewindT >= len + 0.05 then self:Reassemble() end
        return
    end
    -- 倒放录下的轨迹（smoothstep 时间曲线：起止慢、中间快），最后一小段插值到精确原位
    local u = Clamp(self.rewindT / len, 0, 1)
    local ue = u * u * (3 - 2 * u)
    local tq = self.rewindFrom * (1 - ue)
    local su = Smooth((self.rewindT - len) / REWIND_SETTLE)
    for _, p in ipairs(self.pieces) do
        if p.node ~= nil then
            local pos, rot = Sample(p.track, tq)
            if pos ~= nil then
                if self.rewindT > len then
                    pos = pos:Lerp(p.restPos, su)
                    rot = rot:Slerp(p.restRot, su)
                end
                p.node.worldPosition = pos
                p.node.worldRotation = rot
            end
        end
    end
    if self.rewindT >= len + REWIND_SETTLE then self:Reassemble() end
end

function T:Reassemble()
    if self.state ~= M.STATE.REWIND then return end
    for _, p in ipairs(self.pieces) do self:RemovePieceVolume(p) end
    self.pieces = {}
    -- 清空过渡表现，再生成完整体；不能让首帧沿用冻结/回溯高亮。
    self.frozenWhole, self.freezeLeft = nil, nil
    self.hover, self.hoverTarget, self.flash = 0, 0, 0
    self.material:SetShaderParameter("mode", Variant(0.0))
    self.material:SetShaderParameter("hover", Variant(0.0))
    self.material:SetShaderParameter("restored", Variant(1.0))
    self.lastMode, self.lastHover = 0, 0
    self:BuildWhole()
    self.state = M.STATE.WHOLE
    self.rubble = false
    self.restored = true
    self:Emit("restored", {})
    if DebugLog.enabled then DebugLog.Log("TimeObject","TimeObject[%s]: restored", self.id) end
end

-- ---------------------------------------------------------------- 更新
function T:Update(dt)
    self.time = self.time + dt
    if self.state == M.STATE.SHATTERED then
        self.recT = self.recT + dt
        self.recAcc = (self.recAcc or 0) + dt
        if self.recAcc >= RECORD_DT and self.recT < MAX_RECORD then
            self.recAcc = 0
            self:RecordAll(self.recT)
        end
        -- 掉出世界的碎块：停在谷底以下就不再动（保留，回溯时能飞回来）
        for _, p in ipairs(self.pieces) do
            if p.node ~= nil and not p.frozen and p.node.worldPosition.y < -30 then
                local pos, rot = p.node.worldPosition, p.node.worldRotation
                self:SetPieceMode(p, "visual", Vector3(pos.x, -30, pos.z), rot)
                p.frozen = true
            end
        end
    elseif self.state == M.STATE.FROZEN then
        if self.freezeLeft ~= nil and not self.rubble then
            self.freezeLeft = self.freezeLeft - dt
            if self.freezeLeft <= 0 then
                self.freezeLeft = nil
                self:Unfreeze()
            end
        end
    elseif self.state == M.STATE.REWIND then
        self:UpdateRewind(dt)
    end
    -- 冻结中的完整物件（机关用）
    if self.frozenWhole ~= nil then
        self.frozenWhole = self.frozenWhole - dt
        if self.frozenWhole <= 0 then self.frozenWhole = nil; self:Emit("unfreeze", {}) end
    end
    -- 表现：hover 高亮、复原闪光
    local hv = self.hoverTarget or 0
    self.hover = self.hover + (hv - self.hover) * (1 - math.exp(-12 * dt))
    self.flash = math.max(0, (self.flash or 0) - dt * 0.8)
    -- 选中光颜色：由瞄准逻辑按可施放的法术设置（碎时红 / 回溯黄）
    local hc = self.hoverColor
    if hc ~= nil and hc ~= self.lastHoverColor then
        self.lastHoverColor = hc
        self.material:SetShaderParameter("hover_color", Variant(hc))
        for _,m in pairs(self.effectMaterials) do m:SetShaderParameter("hover_color",Variant(hc)) end
    end
    local h = math.floor((self.hover + self.flash) * 20 + 0.5) / 20
    if h ~= self.lastHover then
        self.lastHover = h
        self.material:SetShaderParameter("hover", Variant(h))
        for _,m in pairs(self.effectMaterials) do m:SetShaderParameter("hover",Variant(h)) end
    end
    local wantMode = (self.frozenWhole ~= nil) and 1.0 or 0.0
    if wantMode ~= self.lastMode then
        self.lastMode = wantMode
        self.material:SetShaderParameter("mode", Variant(wantMode))
    end
    self.hoverTarget = 0
end

function T:IsWhole() return self.state == M.STATE.WHOLE end
function T:IsBroken() return self.state == M.STATE.SHATTERED or self.state == M.STATE.FROZEN end

-- 某个体积是不是这个物件的一部分
---@param vol VoxelVolume
function T:Owns(vol)
    return vol ~= nil and volumeOwners[vol] == self
end

-- 当前视觉中心（碎了取碎块平均）
function T:CurrentCenter()
    if self.state == M.STATE.WHOLE or #self.pieces == 0 then return self.center end
    local sum, n = Vector3(0, 0, 0), 0
    local s = self.size
    for _, p in ipairs(self.pieces) do
        if p.node ~= nil then
            sum = sum + p.node.worldPosition + p.node.worldRotation * Vector3(p.nx * s * 0.5, p.ny * s * 0.5, p.nz * s * 0.5)
            n = n + 1
        end
    end
    if n == 0 then return self.center end
    return sum * (1.0 / n)
end

-- 碎块的世界中心列表（特效用）
function T:PieceCenters(maxN)
    local out = {}
    local s = self.size
    for i, p in ipairs(self.pieces) do
        if p.node ~= nil then
            out[#out + 1] = p.node.worldPosition + p.node.worldRotation * Vector3(p.nx * s * 0.5, p.ny * s * 0.5, p.nz * s * 0.5)
            if maxN ~= nil and #out >= maxN then break end
        end
    end
    return out
end

return M
