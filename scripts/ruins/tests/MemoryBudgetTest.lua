-- 只由 -validate-test 加载；记录真实网格/体素/Lua 堆，避免把包体大小当作运行内存。
local V = _G["V"]
V.atFrame(3, function()
    local game = _G["RUINS"]
    V.assert(game ~= nil, "遗迹场景完成初始化")
    if not game then return end
    local cells, vertices, hiddenVertices = 0, 0, 0
    local largest = {}
    for i = 0, game.world:GetVolumeCount() - 1 do
        local volume = game.world:GetVolume(i)
        if volume then
            local dims = volume:GetGrid():GetDimensions()
            local count = dims.x * dims.y * dims.z
            local mesh = volume:GetVertexCount()
            cells, vertices = cells + count, vertices + mesh
            if volume.material == require("ruins.RuinsTerrain").HiddenMaterial() then
                hiddenVertices = hiddenVertices + mesh
            end
            largest[#largest + 1] = {cells = count, vertices = mesh, dims = tostring(dims), name = volume:GetNode().name}
        end
    end
    table.sort(largest, function(a, b) return a.vertices > b.vertices end)
    print(string.format("MemoryBudgetTest: volumes=%d cells=%d vertices=%d hiddenVertices=%d luaKB=%.1f resourcesKB=%.1f",
        game.world:GetVolumeCount(), cells, vertices, hiddenVertices, collectgarbage("count"), cache:GetTotalMemoryUse() / 1024))
    for i = 1, math.min(12, #largest) do
        local item = largest[i]
        print(string.format("MemoryBudgetTest: mesh rank=%d vertices=%d cells=%d dims=%s name=%s", i, item.vertices, item.cells, item.dims, item.name))
    end
    local treeVertices, trees = 0, 0
    for _, node in ipairs(game.scene:GetChildrenWithName("Tree", true)) do
        trees = trees + 1
        for _, part in ipairs(node:GetComponents("StaticModel", true)) do
            local geometry = part.model:GetGeometry(0, 0)
            treeVertices = treeVertices + geometry.vertexCount
        end
        for _, part in ipairs(node:GetComponents("CustomGeometry", true)) do
            treeVertices = treeVertices + part:GetNumVertices(0)
        end
    end
    print(string.format("MemoryBudgetTest: trees=%d treeVertices=%d", trees, treeVertices))
    print("MemoryBudgetTest: dda=" .. game.world:GetDdaStatsString())
end)
