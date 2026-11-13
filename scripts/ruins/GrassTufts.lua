-- ====================================================================
-- GrassTufts.lua — GrassField 不可用时（如 WebGL）的兜底草地
--
-- 每簇 5–7 片细三角草叶，按 6m 分块合并成一个 CustomGeometry（每块一个 draw call），
-- 只铺在内环 / 外环平台这类玩家看得到的平地上；风摆在 RuinsGrassTuft.shader 里做。
-- ====================================================================

local Noise = require("ruins.Noise")

local M = {}

local sin, cos, floor, sqrt = math.sin, math.cos, math.floor, math.sqrt

---@param scene Scene
---@param T table RuinsTerrain 模块
function M.Build(scene, T)
    local t0 = os.clock()
    local mat = Material:new()
    if not mat:SetSurfaceShader("Shaders/BLGL/RuinsGrassTuft.shader") then
        print("GrassTufts: shader failed")
        return nil
    end
    local root = scene:CreateChild("GrassTufts")
    local rng = Noise.Rng(5150)
    local BLOCK = 6.0
    local R0, R1 = T.COURT_R + 6.5, 68.0
    local blocks, tufts = 0, 0
    for bx = -R1, R1 - BLOCK, BLOCK do
        for bz = -R1, R1 - BLOCK, BLOCK do
            local cx, cz = bx + BLOCK * 0.5, bz + BLOCK * 0.5
            local rc = sqrt(cx * cx + cz * cz)
            if rc > R0 - 5 and rc < R1 + 4 then
                local node = root:CreateChild("Tufts")
                local geo = node:CreateComponent("CustomGeometry")
                geo:BeginGeometry(0, TRIANGLE_LIST)
                local n = 0
                for _ = 1, 70 do
                    local x, z = bx + rng:Next() * BLOCK, bz + rng:Next() * BLOCK
                    local w = T.GrassAt(x, z)
                    if T.HasGround(x,z,1) and w > 0.25 and rng:Next() < w then
                        local y = T.Height(x, z) - 0.02
                        local blades = rng:Int(5, 7)
                        local tint = 0.85 + rng:Next() * 0.3
                        local dry = rng:Next() < 0.12
                        local col = dry and Color(1.35 * tint, 1.15 * tint, 0.7 * tint) or Color(tint, tint, tint)
                        for _ = 1, blades do
                            local a = rng:Next() * 6.2832
                            local lean = 0.08 + rng:Next() * 0.18
                            local h = 0.22 + rng:Next() * 0.3
                            local wdt = 0.025 + rng:Next() * 0.02
                            local ox, oz = cos(a) * 0.06, sin(a) * 0.06
                            local px, pz = -sin(a) * wdt, cos(a) * wdt
                            local base = Vector3(x + ox, y, z + oz)
                            local tip = Vector3(x + ox + cos(a) * lean, y + h, z + oz + sin(a) * lean)
                            local verts = {
                                { base + Vector3(px, 0, pz), Vector2(0, 0) },
                                { base - Vector3(px, 0, pz), Vector2(1, 0) },
                                { tip, Vector2(0.5, 1) },
                            }
                            for _, v in ipairs(verts) do
                                geo:DefineVertex(v[1] - node.position)
                                geo:DefineNormal(Vector3.UP)
                                geo:DefineColor(col)
                                geo:DefineTexCoord(v[2])
                            end
                        end
                        n = n + 1
                    end
                end
                if n > 0 then
                    geo:Commit()
                    geo:SetMaterial(mat)
                    geo.castShadows = false
                    blocks, tufts = blocks + 1, tufts + n
                else
                    node:Remove()
                end
            end
        end
    end
    print(string.format("GrassTufts: %d tufts in %d blocks, %.2fs", tufts, blocks, os.clock() - t0))
    return { root = root, material = mat }
end

return M
