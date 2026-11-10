-- 临时：像素粒子材质颜色测试（测试后删除）
local scene
function Start()
    scene = Scene()
    scene:CreateComponent("Octree")
    local cn = scene:CreateChild("Cam")
    cn.position = Vector3(0, 0, -6)
    local cam = cn:CreateComponent("Camera")
    renderer:SetViewport(0, Viewport:new(scene, cam))
    local VoxelFX = require("dragon.VoxelFX")
    local cols = { Color(1, 0.95, 0.7), Color(1, 0.75, 0.3), Color(0.95, 0.4, 0.75), Color(0.5, 0.2, 0.9), Color(0.6, 0.9, 1.0), Color(0.2, 0.5, 1.0) }
    for row, glow in ipairs({ false, true }) do
        local n = scene:CreateChild("B" .. row)
        local bb = n:CreateComponent("BillboardSet")
        bb:SetMaterial(VoxelFX.Material("square", glow))
        bb:SetNumBillboards(#cols)
        for i, c in ipairs(cols) do
            local b = bb:GetBillboard(i - 1)
            b.position = Vector3(-4.2 + i * 1.2, (row == 1) and 0.8 or -0.8, 0)
            b.size = Vector2(0.8, 0.8)
            b.color = c
            b.enabled = true
        end
        bb:Commit()
    end
end
