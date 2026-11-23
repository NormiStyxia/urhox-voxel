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

-- 四棱封闭锥体分四段弯折。横截面宽厚比约 4:1，根窄、腹部稍宽、尖端收束。
-- 每片只有几十个顶点；小形体 Deform 后重算法线，不逐叶建节点或材质。
---@param height number
---@param width number
---@param thickness number
---@param bend number
---@param color Color
---@return ProceduralGeometry
local function GrassBlade(height, width, thickness, bend, color)
    return ConeGeometry(1, 1, 4, 4, false)
        :Translate(0, .5, 0)
        :Deform(function(x, y, z)
            local belly = .55 + 1.2 * sin(pi * y)
            return x * width * .5 * belly,
                y * height,
                z * thickness * .5 * belly + bend * y * y
        end)
        :ComputeVertexNormals()
        :SetVertexColor(color)
        :ApplyGradientColor({
            from = 0, to = height,
            colorFrom = Color(.64, .72, .57), colorTo = Color(1, 1, .88),
        })
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
    ---@type ProceduralGeometry[]
    local parts = {}
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
        parts[#parts + 1] = GrassBlade(height, width, thickness, bend, color)
            :ApplyQuaternion(Quaternion(rng:Range(0, 360), Vector3.UP))
            :Translate(px, -.025 * r, pz)
    end
    local merged = assert(MergeGeometries(parts, false), "RuinsTrees: grass merge failed")
    local leaves = root:CreateChild("Leaves")
    local drawable = leaves:CreateComponent("StaticModel")
    drawable.model = merged:ToModel()
    drawable.material = cache:GetResource("Material", "Materials/HomeTreeVoxel.xml")
    drawable.castShadows = true
    return root
end

return M
