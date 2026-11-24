-- 遗迹植被：复用家园实体体素树；草丛用封闭、有厚度的弯折叶体。
-- Tree / Bush 兼容现有入口与根节点命名；草叶按共享材质合并，每丛一个 drawable。
local HomeTrees = require("ruins.HomeTrees")
local M = {}
local sin, cos, pi = math.sin, math.cos, math.pi

---@type Material|nil
local hiddenMat_

local function Mat(path)
    local m = Material:new()
    if not m:SetSurfaceShader(path) then
        print("RuinsTrees: shader failed " .. path)
        m:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    end
    return m
end

---@class RuinsTreeOptions
---@field h? number
---@field r? number
---@field trunk? number
---@field gold? boolean
---@field lean? number
---@field leanA? number
---@field seed? integer

---@param scene Scene
---@param world VoxelPhysicsWorld|nil
---@param x number
---@param gy number 地面高度
---@param z number
---@param o? RuinsTreeOptions
---@return Node
function M.Tree(scene, world, x, gy, z, o)
    o = o or {}
    -- 不修改调用方的选项；实体生成器要求七个字段完整，缺省保持遗迹原有尺度。
    ---@type HomeTreeOptions
    local options = {
        h = o.h or 7,
        r = o.r or 3.2,
        trunk = o.trunk or 0.45,
        gold = o.gold or false,
        lean = o.lean or 0,
        leanA = o.leanA or 0,
        seed = o.seed or (math.floor(x * 31 + z * 17) + 7),
    }
    local root = HomeTrees.Tree(scene, x, gy, z, options)
    -- 碰撞沿用原有隐藏方形体素树干，尺寸、位置、不可破坏标记均保持。
    if world ~= nil and hiddenMat_ == nil then
        local mat = Material:new()
        if mat:SetSurfaceShader("Shaders/BLGL/HiddenVoxel.shader") then hiddenMat_ = mat end
    end
    if world ~= nil and hiddenMat_ ~= nil then
        local h, tr = options.h, options.trunk
        local s = 0.25
        local w = math.tointeger(math.max(2, math.floor(tr * 1.6 / s + 0.5))) or 2
        local nyv = math.tointeger(math.floor(h * 0.7 / s)) or 8
        local v = world:CreateVolume(w, nyv, w, s, Vector3(x - w * s * 0.5, gy - 0.25, z - w * s * 0.5))
        v:GetGrid():FillBox(0, 0, 0, w - 1, nyv - 1, w - 1, true)
        v.destructible = false
        v.material = hiddenMat_
        world:FinalizeVolume(v)
        v:RebuildGeometry()
    end
    return root
end

-- 时晶：六棱柱 + 尖顶，倾斜插在地里（纯装饰，无碰撞）
local crystalModel_ = nil
local crystalMat_ = nil
---@param scene Scene
function M.Crystal(scene, x, gy, z, h, r, tilt, a, violet)
    if crystalModel_ == nil then
        crystalMat_ = Mat("Shaders/BLGL/RuinsCrystal.shader")
        -- 单位尺寸（几何体以中心为原点，高 1、半径 1）：节点缩放成柱身 0.8h + 尖顶 0.2h
        crystalModel_ = { body = CylinderGeometry(1.0, 0.9, 1.0, 6, 1, false):ToModel(),
            tip = ConeGeometry(1.0, 1.0, 6, 1, true):ToModel() }
    end
    local root = scene:CreateChild("Crystal")
    root.position = Vector3(x, gy - 0.15, z)
    root.rotation = Quaternion(a * 57.2958, Vector3.UP) * Quaternion(tilt * 57.2958, Vector3.RIGHT)
    local col = violet and Color(1.15, 0.85, 1.05) or Color(1, 1, 1)
    local bn = root:CreateChild("Body")
    bn.position = Vector3(0, h * 0.4, 0)
    bn.scale = Vector3(r, h * 0.8, r)
    local sm = bn:CreateComponent("StaticModel")
    sm.model = crystalModel_.body
    sm.material = crystalMat_
    sm.instanceColor = col
    sm.castShadows = true
    local tn = root:CreateChild("Tip")
    tn.position = Vector3(0, h * 0.8 + h * 0.1, 0)
    tn.scale = Vector3(r, h * 0.2, r)
    local tm = tn:CreateComponent("StaticModel")
    tm.model = crystalModel_.tip
    tm.material = crystalMat_
    tm.instanceColor = col
    tm.castShadows = true
    return root
end

---@type Color[]
local GRASS_COLORS = {
    Color(.30, .43, .17), Color(.38, .52, .21), Color(.46, .58, .25),
    Color(.53, .63, .30), Color(.36, .50, .26),
}

-- 四棱截面顺序（俯视顺时针），对应 ±X / ±Z 四个角。
local BLADE_CORNERS = { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } }
-- 分四段：根部收窄、腹部鼓起、尖端收束，整株沿本地 +Z 弯折。
local BLADE_SEGMENTS = 4

--- 一片草叶。顶点直接按 root 局部坐标写进共享几何，
--- 因此不需要平移/变形/合并这三步（引擎的 ProceduralGeometry 不提供它们）。
--- 材质 HomeTreeVoxel 只读顶点色，所以这里既不产 UV，也不会有 UV 缺失的顶点声明。
---@param geom CustomGeometry
---@param height number
---@param width number
---@param thickness number
---@param bend number
---@param color Color
---@param rot number 绕 Y 轴的朝向（弧度）
---@param px number
---@param pz number
---@param baseY number
local function AddBlade(geom, height, width, thickness, bend, color, rot, px, pz, baseY)
    local cosR, sinR = cos(rot), sin(rot)
    ---@type Vector3[][]
    local rings = {}
    for i = 0, BLADE_SEGMENTS do
        local t = i / BLADE_SEGMENTS
        local belly = .55 + 1.2 * sin(pi * t)
        local taper = .30 + .70 * math.max(0, 1 - t)
        local hw = width * .5 * belly * taper
        local ht = thickness * .5 * belly * taper
        local y = baseY + height * t
        local zc = bend * t * t
        local ring = {}
        for k = 1, 4 do
            local lx = BLADE_CORNERS[k][1] * hw
            local lz = BLADE_CORNERS[k][2] * ht + zc
            ring[k] = Vector3(px + lx * cosR + lz * sinR, y, pz - lx * sinR + lz * cosR)
        end
        rings[i + 1] = ring
    end
    -- 底部偏冷灰、顶端偏暖白，和原先那条渐变一致，乘在叶片基色上。
    local function shade(t)
        return Color(color.r * (.64 + .36 * t), color.g * (.72 + .28 * t), color.b * (.57 + .31 * t))
    end
    local function emit(a, b, c, n, col)
        for _, v in ipairs({ a, b, c }) do
            geom:DefineVertex(v)
            geom:DefineNormal(n)
            geom:DefineColor(col)
        end
    end
    for i = 1, BLADE_SEGMENTS do
        local r0, r1 = rings[i], rings[i + 1]
        local t0 = (i - 1) / BLADE_SEGMENTS
        local t1 = i / BLADE_SEGMENTS
        local col = shade((t0 + t1) * .5)
        -- 该段截面中心：四角对称，只剩弯折造成的位移。
        local zcMid = bend * ((t0 + t1) * .5) ^ 2
        local cx, cz = px + zcMid * sinR, pz + zcMid * cosR
        for k = 1, 4 do
            local k2 = k % 4 + 1
            local v00, v01, v11, v10 = r0[k], r0[k2], r1[k2], r1[k]
            -- 引擎左手系：正面 = (b-a)×(c-a) 指向的一侧，所以法线直接取第一个三角形的叉积。
            local n = (v01 - v00):CrossProduct(v11 - v00)
            local outX = (v00.x + v01.x + v11.x + v10.x) * .25 - cx
            local outZ = (v00.z + v01.z + v11.z + v10.z) * .25 - cz
            -- 朝外校验：不朝外就整片翻转（顶点顺序与法线一起翻，两者始终同向）。
            if n.x * outX + n.z * outZ < 0 then
                v00, v10 = v10, v00
                v01, v11 = v11, v01
                n = Vector3(-n.x, -n.y, -n.z)
            end
            if n:LengthSquared() < 1e-12 then n = Vector3(0, 1, 0) else n = n:Normalized() end
            emit(v00, v01, v11, n, col)
            emit(v00, v11, v10, n, col)
        end
    end
    -- 底封口朝下、顶面朝上；两个三角形都按“叉积与法线同向”的顺序写入。
    local base, cap = rings[1], rings[BLADE_SEGMENTS + 1]
    local baseColor, capColor = shade(0), shade(1)
    local down, up = Vector3(0, -1, 0), Vector3(0, 1, 0)
    emit(base[1], base[3], base[2], down, baseColor)
    emit(base[1], base[4], base[3], down, baseColor)
    emit(cap[1], cap[2], cap[3], up, capColor)
    emit(cap[1], cap[3], cap[4], up, capColor)
end

-- 原 Bush r 为占地尺度：保留草地生成预算和 Bush 根名，每处三小簇、共 7–10 片。
-- 高 0.72r–1.20r，叶宽参数 0.12r–0.18r、厚 0.035r–0.05r；无碰撞。
---@param scene Scene
---@param x number
---@param gy number
---@param z number
---@param r number
---@param rng NoiseRng
---@return Node
function M.Bush(scene, x, gy, z, r, rng)
    local root = scene:CreateChild("Bush")
    root.position = Vector3(x, gy, z)
    -- 整丛共用一份几何：每片叶子的顶点直接累加，最后只有一个 drawable。
    local leaves = root:CreateChild("Leaves")
    local geom = leaves:CreateComponent("CustomGeometry")
    geom:BeginGeometry(0, TRIANGLE_LIST)
    local count = rng:Int(7, 10)
    local phase = rng:Range(0, 2 * pi)
    for i = 1, count do
        local clump = (i - 1) % 3
        local a = phase + clump * 2 * pi / 3
        local spread = r * .22
        local px = cos(a) * spread + rng:Range(-.07, .07) * r
        local pz = sin(a) * spread + rng:Range(-.07, .07) * r
        -- 各小簇中心叶较高，周边叶较短且向外舒展；不形成等高杆状轮廓。
        local height = r * (i <= 3 and rng:Range(1.02, 1.20) or rng:Range(.72, .98))
        local width = r * rng:Range(.12, .18)
        local thickness = r * rng:Range(.035, .05)
        local bend = r * rng:Range(.22, .46)
        local color = assert(GRASS_COLORS[rng:Int(1, #GRASS_COLORS)])
        AddBlade(geom, height, width, thickness, bend, color,
            rng:Range(0, 2 * pi), px, pz, -.025 * r)
    end
    geom:Commit()
    geom:SetMaterial(cache:GetResource("Material", "Materials/HomeTreeVoxel.xml"))
    leaves.castShadows = true
    return root
end

return M
