-- RenderBudget.lua — 静态场景的阴影投射与绘制距离预算（只在建好场景 / 家园后执行一次，无每帧开销）。
--
-- 普查结论（高档，南门机位）：主光阴影约占全部批次与三角形的 45%；2000+ 个投影体里，
-- 1378 个是体素网格块，很多只有几十厘米，却在 140m 外的第三级级联里照样重画。
-- 小物件在远级联里的影子不到一个阴影纹素，按物体尺寸给每个 Drawable 一个阴影距离，
-- 大体量（墙、塔、柱廊）保持全程投影。岛壳只有朝下的岩壳和缓坡，不投影。
-- 引擎为每个体积建的网格块在 LOD 切换时复用同一组件，设置一次即可。
local M = {}

-- 动态体积（时之碎块、谜题物件）在打碎/回溯时会改变尺寸，同样按当前包围盒处理；
-- 新碎块使用引擎默认设置（投影、无距离限制），不在这里追踪。
local VOXEL_ROOTS = { VoxelVolume = true }
local PREFIX_ROOTS = { "TimePiece_" }

---@param d Drawable
---@param radius number
local function BudgetVoxel(d, radius)
    -- r=0.25m→20m、1m→40m、2m→80m；半径 3.5m 以上不限制（0 = 跟随灯光级联）。
    if radius < 3.5 then
        d.shadowDistance = math.max(20, radius * 40)
    end
    -- 远处小于几个像素的小装饰直接不画；雾从 80–100m 开始。
    if radius < 0.6 then
        d.drawDistance = math.max(70, radius * 200)
    end
end

---@param node Node
---@param fn fun(d: Drawable)
local function EachDrawable(node, fn)
    for _, t in ipairs({ "CustomGeometry", "StaticModel" }) do
        for _, c in ipairs(node:GetComponents(t, true)) do fn(c --[[@as Drawable]]) end
    end
end

---@param scene Scene
---@return table stats
function M.Apply(scene)
    local stats = { voxel = 0, limited = 0, culled = 0, shell = 0, foliage = 0 }
    for _, child in ipairs(scene:GetChildren()) do
        local name = child.name
        local voxel = VOXEL_ROOTS[name] == true
        if not voxel then
            for _, prefix in ipairs(PREFIX_ROOTS) do
                if name:sub(1, #prefix) == prefix then voxel = true; break end
            end
        end
        if voxel then
            EachDrawable(child, function(d)
                local size = d.worldBoundingBox.size
                local radius = size:Length() * 0.5
                stats.voxel = stats.voxel + 1
                if radius < 3.5 then stats.limited = stats.limited + 1 end
                if radius < 0.6 then stats.culled = stats.culled + 1 end
                BudgetVoxel(d, radius)
            end)
        elseif name == "IslandShell" then
            EachDrawable(child, function(d) d.castShadows = false; stats.shell = stats.shell + 1 end)
        elseif name == "Bush" then
            EachDrawable(child, function(d) d.shadowDistance = 30; d.drawDistance = 140; stats.foliage = stats.foliage + 1 end)
        elseif name == "Tree" then
            -- 树冠的影子是大块明暗，远处仍需要；方格枝干被树冠遮住，近处即可。
            for _, leaves in ipairs(child:GetChildrenWithName("Leaves", false)) do
                EachDrawable(leaves, function(d) d.shadowDistance = 110; stats.foliage = stats.foliage + 1 end)
            end
            for _, bark in ipairs(child:GetChildrenWithName("Bark", false)) do
                EachDrawable(bark, function(d) d.shadowDistance = 45 end)
            end
        elseif name == "Crystal" then
            EachDrawable(child, function(d) d.shadowDistance = 40; stats.foliage = stats.foliage + 1 end)
        end
    end
    print(string.format("RenderBudget: voxel %d (shadow-limited %d, draw-limited %d), shell %d no-cast, foliage %d",
        stats.voxel, stats.limited, stats.culled, stats.shell, stats.foliage))
    return stats
end

return M
