-- ====================================================================
-- BlockCharacter.lua - 方块拼装角色（Blockbench 数据 → CustomGeometry）
--
-- 每根骨骼一个 Node，骨骼上的方块合并成一个 CustomGeometry；动画直接旋转
-- 骨骼 Node（Minecraft 实体同款程序化动画），不需要 .mdl / .ani 转换。
--
-- 数据来自 scripts/game/NomiModelData.lua（art/nomi_ysm/build_nomi.py 生成）。
-- Blockbench 空间 → UrhoX：z 取反（右手系转左手系，正面 -Z → +Z），
-- 1 单位 = UNIT 米。
-- ====================================================================

---@class BlockCharacter
---@field root Node
---@field bones table<string, Node>
---@field basePos table<string, Vector3>
---@field time number
---@field phase number
---@field gait number
---@field air number
---@field crouch number
---@field armed number
---@field useTimer number
---@field handSocketPositions table<string, Vector3>|nil
local M = {}
---@type number|nil 截图验证用的强制移动速度
M.debugMoveSpeed = nil
M.__index = M
-- 调用方在创建角色前选择数据；不热替换已创建的角色，不隐式覆盖传入的 data。
M.USE_ELBOW_DATA = false

function M.LoadVoxelData()
    if M.USE_ELBOW_DATA then return require "game.NomiVoxelDataElbow" end
    return require "game.NomiVoxelData"
end

-- 主场景与骑龙场景只使用这一份修长体型配置。
M.SLENDER = {
    scale = { head = 0.82, hair_locks = 0.85, hair_back = 0.85 },
    stretch = { leg_right = 1.35, leg_left = 1.35 },
    widen = { x = 0.85, z = 0.92, skip = { "head" } },
}

local UNIT = 0.05            -- 头顶约 1.7m，与 config.PLAYER_HEIGHT 对齐
local MATERIAL = "Materials/Nomi.xml"
local UV_INSET = 0.01        -- UV 往面内缩一点，避免最近点采样串到相邻像素

---@param v number[]
---@param pivot number[]
---@return Vector3
local function ToLocal(v, pivot)
    local x, y, z = v[1] or 0, v[2] or 0, v[3] or 0
    local px, py, pz = pivot[1] or 0, pivot[2] or 0, pivot[3] or 0
    return Vector3((x - px) * UNIT, (y - py) * UNIT, -(z - pz) * UNIT)
end

-- 与 Blockbench box UV 一致的六面 UV 矩形 {x1, y1, x2, y2}（UV 单位）
local function FaceUVs(u, v, w, h, d)
    return {
        north = { u + d, v + d, u + d + w, v + d + h },
        east = { u, v + d, u + d, v + d + h },
        south = { u + 2 * d + w, v + d, u + 2 * d + 2 * w, v + d + h },
        west = { u + d + w, v + d, u + 2 * d + w, v + d + h },
        up = { u + d + w, v + d, u + d, v },
        down = { u + d + 2 * w, v, u + d + w, v + d },
    }
end

-- 每个面按「从外面看过去」的 左上/右上/右下/左下 给出角点（UrhoX 空间），
-- 顺时针为正面（Urho 默认剔除逆时针）。lo/hi 为盒子最小/最大角。
local function FaceCorners(face, lo, hi)
    if face == "north" then -- 角色正面，+Z
        return Vector3(0, 0, 1), {
            Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
            Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z) }
    elseif face == "south" then -- 背面，-Z
        return Vector3(0, 0, -1), {
            Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z),
            Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, lo.z) }
    elseif face == "east" then -- 角色右侧，+X
        return Vector3(1, 0, 0), {
            Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z),
            Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, lo.y, lo.z) }
    elseif face == "west" then -- 角色左侧，-X
        return Vector3(-1, 0, 0), {
            Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z),
            Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z) }
    elseif face == "up" then
        return Vector3(0, 1, 0), {
            Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
            Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z) }
    else -- down
        return Vector3(0, -1, 0), {
            Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
            Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z) }
    end
end

local FACE_ORDER = { "north", "south", "east", "west", "up", "down" }

---@param geom CustomGeometry
local function EmitCube(geom, cube, pivot, uvW, uvH)
    local inf = cube.inflate or 0
    local f, s = cube.from, cube.size
    -- Blockbench 空间的最小/最大角（含 inflate），换算后 z 翻转，所以要重新取 min/max
    local a = ToLocal({ f[1] - inf, f[2] - inf, f[3] - inf }, pivot)
    local b = ToLocal({ f[1] + s[1] + inf, f[2] + s[2] + inf, f[3] + s[3] + inf }, pivot)
    local lo = Vector3(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z))
    local hi = Vector3(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z))
    local uvs = FaceUVs(cube.uv[1], cube.uv[2], s[1], s[2], s[3])
    local count = 0

    for _, face in ipairs(FACE_ORDER) do
        local r = uvs[face]
        if r[1] ~= r[3] and r[2] ~= r[4] then -- 零面积的面（薄片的侧面）跳过
            local normal, c = FaceCorners(face, lo, hi)
            local sx = r[3] > r[1] and UV_INSET or -UV_INSET
            local sy = r[4] > r[2] and UV_INSET or -UV_INSET
            local u1, v1 = (r[1] + sx) / uvW, (r[2] + sy) / uvH
            local u2, v2 = (r[3] - sx) / uvW, (r[4] - sy) / uvH
            local t = {
                Vector2(u1, v1), Vector2(u2, v1), Vector2(u2, v2), Vector2(u1, v2),
            }
            for _, k in ipairs({ 1, 2, 3, 1, 3, 4 }) do
                geom:DefineVertex(c[k])
                geom:DefineNormal(normal)
                geom:DefineTexCoord(t[k])
            end
            count = count + 1
        end
    end
    return count
end

--- 在 parent 下构建角色。返回带 Update 的角色对象。
---@param parent Node
---@param data table
---@return BlockCharacter
function M.Create(parent, data)
    ---@type BlockCharacter
    local self = setmetatable({}, M)
    self.root = parent:CreateChild("BlockCharacter")
    self.bones = {}      ---@type table<string, Node>
    self.basePos = {}    ---@type table<string, Vector3>
    self.time = 0.0
    self.phase = 0.0
    self.gait = 0.0
    self.air = 0.0
    self.crouch = 0.0
    self.armed = 0.0
    self.useTimer = 0.0

    local material = cache:GetResource("Material", MATERIAL)
    if material == nil then
        print("BlockCharacter: material not found: " .. MATERIAL)
    end

    local pivots = {}
    for _, b in ipairs(data.bones) do
        pivots[b.name] = b.pivot
        local parentNode = b.parent and self.bones[b.parent] or self.root
        local parentPivot = b.parent and pivots[b.parent] or { 0, 0, 0 }
        local node = parentNode:CreateChild(b.name)
        node.position = ToLocal(b.pivot, parentPivot)
        self.bones[b.name] = node
        self.basePos[b.name] = node.position
    end

    local faces, cubes = 0, 0
    for _, b in ipairs(data.bones) do
        local list = {}
        for _, c in ipairs(data.cubes) do
            if c.bone == b.name then table.insert(list, c) end
        end
        if #list > 0 then
            local geom = self.bones[b.name]:CreateComponent("CustomGeometry")
            geom:BeginGeometry(0, TRIANGLE_LIST)
            for _, c in ipairs(list) do
                faces = faces + EmitCube(geom, c, b.pivot, data.uvWidth, data.uvHeight)
                cubes = cubes + 1
            end
            geom:Commit()
            if material ~= nil then geom:SetMaterial(0, material) end
            geom.castShadows = true
        end
    end
    print(string.format("BlockCharacter: built %d bones, %d cubes, %d faces", #data.bones, cubes, faces))
    return self
end

-- 体素 quad 方向 → FaceCorners 的面名（体素数据已是 UrhoX 坐标，不需要翻 z）
local VOXEL_FACE = { "east", "west", "up", "down", "north", "south" }
local VOXEL_NORMAL_AXIS = { 1, 1, 2, 2, 3, 3 }

--- 体素版：数据来自 scripts/game/NomiVoxelData.lua（art/nomi_voxel/voxelize.py 生成）。
--- 每根骨骼一个 CustomGeometry，颜色写在顶点上；骨骼节点和动画与方块版共用。
--- variant（可选）：同一份体素数据换一套比例，不另做模型。
---   scale   = { 骨骼名 = 统一缩放 }（绕骨骼轴心，如头缩小）
---   stretch = { 骨骼名 = Y 向拉长 }（腿用；整体会抬高，脚仍踩在地上）
---   widen   = { x =, z =, skip = {骨骼名...} }（身体往中线收窄，skip 里的骨骼不收）
---@param parent Node
---@param data table
---@param variant table|nil
---@return BlockCharacter
function M.CreateVoxel(parent, data, variant)
    ---@type BlockCharacter
    local self = setmetatable({}, M)
    self.root = parent:CreateChild("VoxelCharacter")
    self.bones = {}
    self.basePos = {}
    self.time, self.phase, self.gait = 0.0, 0.0, 0.0
    self.air, self.crouch, self.armed, self.useTimer = 0.0, 0.0, 0.0, 0.0

    local unit = data.unit
    local ox, oy, oz = data.origin[1], data.origin[2], data.origin[3]
    local material = cache:GetResource("Material", "Materials/NomiVoxel.xml")
    if material == nil then
        print("BlockCharacter: voxel material not found")
    end

    -- 体型收窄（修长版用）：直接改几何和骨骼轴心的位置，不用节点非等比缩放——
    -- 父节点非等比缩放时子节点一转（摆臂、外套飘）就会剪切变形
    local wx, wz, zc = 1.0, 1.0, -1.0
    local widenSkip = {}
    if variant ~= nil and variant.widen ~= nil then
        wx, wz = variant.widen.x or 1.0, variant.widen.z or 1.0
        for _, name in ipairs(variant.widen.skip or {}) do widenSkip[name] = true end
    end
    ---@return number, number, number
    local function Shape(bone, x, y, z)
        if widenSkip[bone] then return x, y, z end
        return x * wx, y, zc + (z - zc) * wz
    end

    local pivots = {}
    for _, b in ipairs(data.bones) do
        pivots[b.name] = b.pivot
        local parentNode = b.parent and self.bones[b.parent] or self.root
        local node = parentNode:CreateChild(b.name)
        -- 子骨骼挂点 = 父骨骼形变后的空间里，子骨骼轴心所在的位置
        local owner = b.parent or b.name
        local cx, cy, cz = Shape(owner, b.pivot[1], b.pivot[2], b.pivot[3])
        local px0, py0, pz0 = 0.0, 0.0, 0.0
        if b.parent then
            local pp = pivots[b.parent]
            px0, py0, pz0 = Shape(b.parent, pp[1], pp[2], pp[3])
        end
        node.position = Vector3((cx - px0) * unit, (cy - py0) * unit, (cz - pz0) * unit)
        self.bones[b.name] = node
        self.basePos[b.name] = node.position
    end

    if variant ~= nil then
        local lift = 0.0
        for name, sc in pairs(variant.scale or {}) do
            local node = self.bones[name]
            if node ~= nil then node.scale = Vector3(sc, sc, sc) end
        end
        for name, sy in pairs(variant.stretch or {}) do
            local node = self.bones[name]
            if node ~= nil then
                node.scale = Vector3(1.0, sy, 1.0)
                -- 腿绕髋部拉长会往下伸，整个角色抬高同样的量，脚还踩在地上
                lift = math.max(lift, pivots[name][2] * (sy - 1.0) * unit)
            end
        end
        local root = self.bones.root
        if root ~= nil then
            root.position = root.position + Vector3(0.0, lift, 0.0)
            self.basePos.root = root.position
        end
    end

    -- 沿用当前施法/武器掌心坐标，只有所属骨骼变化；零肘角时挂点世界位姿不变。
    -- 惰性创建挂点，旧调用方不调用 HandSocket 时节点树与旧版一致。
    self.handSocketPositions = {}
    for _, side in ipairs({ "right", "left" }) do
        local owner = self.bones["forearm_" .. side] and ("forearm_" .. side) or ("arm_" .. side)
        local pivot = pivots[owner]
        if pivot then
            local x = side == "right" and 19 or -19
            local hx, hy, hz = Shape(owner, x, 33, -0.75)
            local px, py, pz = Shape(owner, pivot[1], pivot[2], pivot[3])
            self.handSocketPositions[side] = Vector3(hx - px, hy - py, hz - pz) * unit
        end
    end

    local palette = {}
    for i, c in ipairs(data.palette) do
        palette[i] = Color(c[1], c[2], c[3], 1.0)
    end

    local total, totalTris = 0, 0
    for _, b in ipairs(data.bones) do
        local quads = data.quads[b.name] or {}
        local hasTris = data.tris ~= nil and data.tris[b.name] ~= nil
        if #quads > 0 or hasTris then
            local px, py, pz = Shape(b.name, b.pivot[1], b.pivot[2], b.pivot[3])
            local bone = b.name
            local geom = self.bones[b.name]:CreateComponent("CustomGeometry")
            geom:BeginGeometry(0, TRIANGLE_LIST)
            for _, q in ipairs(quads) do
                local dir, layer, u, v, w, h = q[1], q[2], q[3], q[4], q[5], q[6]
                local color = palette[q[7]] or Color.WHITE
                -- 体素索引 → 体素坐标：x = i + ox, y = j + oy, z = k + oz
                local lo, hi
                local axis = VOXEL_NORMAL_AXIS[dir]
                local plane = layer + ((dir % 2 == 1) and 1 or 0) -- 正方向的面在格子远端
                if axis == 1 then
                    lo = { plane + ox, v + oy, u + oz }
                    hi = { plane + ox, v + h + oy, u + w + oz }
                elseif axis == 2 then
                    lo = { u + ox, plane + oy, v + oz }
                    hi = { u + w + ox, plane + oy, v + h + oz }
                else
                    lo = { u + ox, v + oy, plane + oz }
                    hi = { u + w + ox, v + h + oy, plane + oz }
                end
                local lx, ly, lz = Shape(bone, lo[1], lo[2], lo[3])
                local hx, hy, hz = Shape(bone, hi[1], hi[2], hi[3])
                local vlo = Vector3((lx - px) * unit, (ly - py) * unit, (lz - pz) * unit)
                local vhi = Vector3((hx - px) * unit, (hy - py) * unit, (hz - pz) * unit)
                local normal, c = FaceCorners(VOXEL_FACE[dir], vlo, vhi)
                for _, k in ipairs({ 1, 2, 3, 1, 3, 4 }) do
                    geom:DefineVertex(c[k])
                    geom:DefineNormal(normal)
                    geom:DefineColor(color)
                end
            end
            -- 斜面三角形（台阶切成的 45° 楔形），顶点已按正面朝外排好
            local tris = data.tris and data.tris[b.name] or nil
            if tris ~= nil then
                for _, t in ipairs(tris) do
                    local color = palette[t[10]] or Color.WHITE
                    local p = {}
                    for n = 0, 2 do
                        local vx, vy, vz = Shape(bone, t[n * 3 + 1] + ox, t[n * 3 + 2] + oy, t[n * 3 + 3] + oz)
                        p[n + 1] = Vector3((vx - px) * unit, (vy - py) * unit, (vz - pz) * unit)
                    end
                    local normal = (p[2] - p[1]):CrossProduct(p[3] - p[1]):Normalized()
                    for n = 1, 3 do
                        geom:DefineVertex(p[n])
                        geom:DefineNormal(normal)
                        geom:DefineColor(color)
                    end
                end
                totalTris = totalTris + #tris
            end
            geom:Commit()
            if material ~= nil then geom:SetMaterial(0, material) end
            geom.castShadows = true
            total = total + #quads
        end
    end
    print(string.format("BlockCharacter: built voxel character, %d bones, %d quads, %d slope tris",
        #data.bones, total, totalTris))
    return self
end

--- 角色拥有的掌心节点；调用方只挂子节点，不删除/移动此节点。
--- 无肘时复用 arm 下已有 SpellPalm / hand_left；有肘时位于 forearm 末端掌心。
---@param side string 'right'|'left'
---@return Node|nil
function M:HandSocket(side)
    assert(side == "right" or side == "left", "HandSocket side must be right or left")
    local owner = self.bones["forearm_" .. side] or self.bones["arm_" .. side]
    if owner == nil then return nil end
    local name = side == "right" and "SpellPalm" or "hand_left"
    local socket = owner:GetChild(name, false)
    if socket ~= nil then return socket end
    local position = self.handSocketPositions and self.handSocketPositions[side]
    -- 历史 Blockbench 路径没有体素掌心标定，不猜测挂点。
    if position == nil then return nil end
    socket = owner:CreateChild(name)
    socket.position = position
    return socket
end

---@param name string
---@param pitch number 绕 X（正值：骨骼下端往后摆）
---@param yaw number 绕 Y
---@param roll number 绕 Z（正值：骨骼下端往 +X 摆）
function M:SetBone(name, pitch, yaw, roll)
    local node = self.bones[name]
    if node == nil then return end
    node.rotation = Quaternion(pitch, yaw, roll)
end

function M:TriggerUse()
    self.useTimer = 0.3
end

function M:IsUsing()
    return self.useTimer > 0.0
end

---@param timeStep number
---@param s table { moveSpeed, onGround, armed, aiming, crouching, aimPitch }
function M:Update(timeStep, s)
    if M.debugMoveSpeed ~= nil then
        -- 截图验证用：强制一个移动速度看跑步姿态；正常游戏为 nil
        s = { moveSpeed = M.debugMoveSpeed, onGround = true, armed = s.armed, aiming = s.aiming,
              crouching = s.crouching, aimPitch = s.aimPitch }
    end
    local dt = math.min(timeStep, 0.1)
    self.time = self.time + dt
    self.useTimer = math.max(0.0, self.useTimer - dt)
    local k = 1.0 - math.exp(-10.0 * dt)

    local speed = s.moveSpeed or 0.0
    local targetGait = s.onGround and Clamp(speed / 5.0, 0.0, 1.7) or 0.0
    self.gait = Lerp(self.gait, targetGait, k)
    self.air = Lerp(self.air, s.onGround and 0.0 or 1.0, k)
    self.crouch = Lerp(self.crouch, s.crouching and 1.0 or 0.0, k)
    self.armed = Lerp(self.armed, (s.armed or s.aiming) and 1.0 or 0.0, k)
    self.phase = self.phase + dt * (3.0 + speed * 1.5)

    local t = self.time
    local g = math.min(self.gait, 1.3)
    local swing = math.sin(self.phase) * 38.0 * g
    local idle = 1.0 - math.min(self.gait, 1.0)
    local breath = math.sin(t * 2.2)

    -- 根节点：走路上下颠、蹲下降低、空中不动
    local bob = math.abs(math.sin(self.phase)) * 0.035 * g + breath * 0.004 * idle
    self.bones.root.position = self.basePos.root + Vector3(0.0, bob - self.crouch * 0.12, 0.0)

    -- 腿：前后交替；空中收腿；蹲下前屈
    local airLegR, airLegL = -28.0 * self.air, 14.0 * self.air
    self:SetBone("leg_right", -swing + airLegR - self.crouch * 30.0, 0, 0)
    self:SetBone("leg_left", swing + airLegL - self.crouch * 30.0, 0, 0)

    -- 身体：跑起来前倾，蹲下前倾
    self:SetBone("body", g * 6.0 + self.crouch * 14.0, math.sin(self.phase) * 4.0 * g, 0)

    -- 手臂：与腿反向摆；A 字外张；空中张开；持械时右手前举
    local spread = 6.0 + breath * 1.5 * idle + self.air * 30.0
    local armR = swing * 0.8
    local armL = -swing * 0.8
    local use = self.useTimer > 0.0 and (self.useTimer / 0.3) * 25.0 or 0.0
    armR = Lerp(armR, -80.0 + (s.aimPitch or 0.0) * 0.6 - use, self.armed)
    if s.aiming then
        armL = Lerp(armL, -70.0 + (s.aimPitch or 0.0) * 0.6, self.armed)
    end
    -- 绕 Z 正转把下端甩向 +X：右臂（+X 侧）取正值外张，左臂取负值
    self:SetBone("arm_right", armR, 0, spread)
    self:SetBone("arm_left", armL, 0, -spread)
    -- 基础层归零，CombatAnim / SeatPose 在 Update 之后覆盖；不叠旧整臂角。
    self:SetBone("forearm_right", 0, 0, 0)
    self:SetBone("forearm_left", 0, 0, 0)

    -- 头：抵消一点身体前倾，待机时轻微左右看
    local headYaw = math.sin(t * 0.7) * 6.0 * idle
    self:SetBone("head", -g * 4.0 - self.crouch * 10.0 + breath * 1.0 * idle, headYaw, 0)
    -- 肩前发束挂在身体上（不跟头点头，免得扫进肩膀），只跟一半的左右转头
    self:SetBone("hair_locks", 0, headYaw * 0.5, 0)
    -- 帽兜：挂在外套上半，跑起来稍微往后掀
    self:SetBone("hood", g * 5.0 + self.air * 8.0 + math.sin(t * 5.0 + 0.6) * 0.8 * g, 0, 0)
    -- 背后长发：跟一半转头，跑起来往后飘一点
    self:SetBone("hair_back", 2.0 + g * 8.0 + self.air * 10.0 + math.sin(t * 4.0) * 1.5 * g, headYaw * 0.5, 0)

    -- 裙摆、斗篷：随速度往后飘，带一点抖动
    self:SetBone("skirt", g * 5.0 + self.air * 8.0, 0, 0)
    self:SetBone("cloak", g * 8.0 + self.air * 12.0, 0, 0)
    -- 体素版外套：上半从肩部轻微后仰，下摆从腰部往后飘、左右荡（碎条挂在下摆上继续叠加）
    local wave = math.sin(t * 5.0 + 0.6)
    self:SetBone("coat_upper", 2.0 + g * 6.0 + self.air * 6.0 + wave * 0.8 * g, 0, 0)
    self:SetBone("coat_lower", 3.0 + g * 16.0 + self.air * 18.0 + wave * (1.5 + 5.0 * g),
        math.sin(self.phase) * 3.0 * g, math.sin(self.phase * 0.5 + 0.3) * 2.5 * g)
    -- 碎条：方块版是 cloak_strip_1..6，体素版是 cloak_strip_r / _l / _b
    local i = 0
    for name, _ in pairs(self.bones) do
        if string.sub(name, 1, 12) == "cloak_strip_" then
            i = i + 1
            local flutter = math.sin(t * (6.0 + i * 0.7) + i * 1.3) * (3.0 + 9.0 * g)
            -- 体素版碎条挂在外套下摆下面，角度会叠加，所以基础量小一些
            local onCoat = self.bones.coat_lower ~= nil
            local back = onCoat and (3.0 + 14.0 * g + 18.0 * self.air) or (6.0 + 26.0 * g + 30.0 * self.air)
            self:SetBone(name, back + flutter, 0, 0)
        end
    end

    -- 丸子头和丝带：跟着步子晃
    local sway = math.sin(self.phase * 2.0) * 5.0 * g + math.sin(t * 1.6) * 2.0 * idle
    self:SetBone("bun_right", sway, 0, 0)
    self:SetBone("bun_left", -sway, 0, 0)
end

return M
