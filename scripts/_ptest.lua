-- 临时：粒子材质渲染测试（测试后删除）
local scene
function Start()
    scene = Scene()
    scene:CreateComponent("Octree")
    local cn = scene:CreateChild("Cam")
    cn.position = Vector3(0, 0, -6)
    local cam = cn:CreateComponent("Camera")
    renderer:SetViewport(0, Viewport:new(scene, cam))
    local zn = scene:CreateChild("Z")
    local z = zn:CreateComponent("Zone")
    z.boundingBox = BoundingBox(-100, 100)
    z.fogColor = Color(0.75, 0.8, 0.88)
    local VoxelFX = require("dragon.VoxelFX")
    local techs = { "Techniques/DiffUnlitParticleAlpha.xml", "Techniques/DiffUnlitParticleAdd.xml", "Techniques/DiffUnlitAlpha.xml", "Techniques/DiffAlpha.xml", "Techniques/DiffVColUnlitAlpha.xml" }
    for i, tn in ipairs(techs) do
        local n = scene:CreateChild("B" .. i)
        local bb = n:CreateComponent("BillboardSet")
        local m = Material:new()
        m:SetTechnique(0, cache:GetResource("Technique", tn))
        m:SetTexture(TU_DIFFUSE, VoxelFX.Texture("flake"))
        bb:SetMaterial(m)
        bb:SetNumBillboards(1)
        local b = bb:GetBillboard(0)
        b.position = Vector3(-4 + i * 1.4, 0, 0)
        b.size = Vector2(0.6, 0.6)
        b.color = Color(0.2, 0.5, 1.0, 1)
        b.enabled = true
        bb:Commit()
    end
end
