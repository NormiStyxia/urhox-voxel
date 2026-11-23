-- GroundContact.lua — 体素建筑的落地遮蔽（RuinsGroundContact.shaderinc 的数据端）。
--
-- 把岛面可见高度烘成一张 16 位小贴图（R 高位、G 低位），体素材质按世界坐标查表：
-- 竖直面在离地 0.9m 内、朝下的面在离地 1m 内衰减间接光。遗迹岛（a）用地形可见高度
-- 1m 网格；家园（b）用家园地面 0.5m 网格。建一次贴图，没有每帧开销。
-- 材质登记为弱引用；档位只写一个 float。
local M = {}

---@type table<Material, boolean>
local materials = setmetatable({}, { __mode = "k" })
---@type table<string, {texture: Texture2D, frame: Vector4, range: Vector4}>
local regions = {}
local strength = 0.0

---@param material Material
local function BindRegions(material)
    for slot, r in pairs(regions) do
        material:SetSurfaceTexture("ground_height_" .. slot, r.texture)
        material:SetShaderParameter("ground_frame_" .. slot, Variant(r.frame))
        material:SetShaderParameter("ground_range_" .. slot, Variant(r.range))
    end
    material:SetShaderParameter("ground_contact_strength", Variant(strength))
end

---@param material Material|nil
function M.Register(material)
    if material == nil or materials[material] then return end
    materials[material] = true
    BindRegions(material)
end

-- 编码与 RuinsTerrain 的 Terrain 高度图相同：v = (h - base) / unit，R = floor(v)，G = 小数 × 256。
---@param image Image
---@param i integer
---@param j integer
---@param h number
---@param base number
---@param unit number
function M.EncodeHeight(image, i, j, h, base, unit)
    local v = (h - base) / unit
    if v < 0 then v = 0 elseif v > 255.99 then v = 255.99 end
    local hi = math.floor(v)
    local lo = math.floor((v - hi) * 256)
    image:SetPixelInt(i, j, hi | (lo << 8))
end

-- image 第 0 行是最北（maxZ）；像素 (i, j) 的中心在 (minX + i/texelsPerMetre, maxZ - j/texelsPerMetre)。
---@param slot string "a" | "b"
---@param image Image
---@param minX number
---@param maxZ number
---@param texelsPerMetre number
---@param base number
---@param unit number
function M.SetRegion(slot, image, minX, maxZ, texelsPerMetre, base, unit)
    local texture = Texture2D:new()
    texture:SetNumLevels(1)
    if not texture:SetData(image, false) then
        print("GroundContact: height texture upload failed for region " .. slot)
        return false
    end
    texture:SetFilterMode(FILTER_BILINEAR)
    texture:SetAddressMode(COORD_U, ADDRESS_CLAMP)
    texture:SetAddressMode(COORD_V, ADDRESS_CLAMP)
    regions[slot] = {
        texture = texture,
        frame = Vector4(minX, maxZ, texelsPerMetre, image.width),
        range = Vector4(base, unit, image.height, 0),
    }
    for material in pairs(materials) do BindRegions(material) end
    return true
end

---@param value number
function M.SetStrength(value)
    value = math.max(0, math.min(0.5, value or 0))
    if value == strength then return end
    strength = value
    local v = Variant(strength)
    for material in pairs(materials) do material:SetShaderParameter("ground_contact_strength", v) end
end

-- 场景停止时释放贴图与引用；下一次 Start 重新登记。
function M.Reset()
    regions = {}
    materials = setmetatable({}, { __mode = "k" })
end

return M
