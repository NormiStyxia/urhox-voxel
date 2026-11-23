local V = _G["V"]
V.atFrame(3,function()
    local test = _G["TREE_MESH_TEST"]
    V.assert(test ~= nil,"树木外壳测试已加载")
    if not test then return end
    V.assert(test.quads == 6,"同色相邻两格合并为六个外表面")
    V.assert(test.faces == 10,"剔除两个内部面，保留十个外露单位面")
    local parts = test.tree:GetComponents("StaticModel",true)
    V.assert(#parts == 2,"树干和树冠仍为两个模型")
    V.assert(#test.scene:GetComponents("CustomGeometry",true)==0,"模型转换后不保留临时CPU几何")
    for _,part in ipairs(parts) do
        local bounds=part.worldBoundingBox.size
        V.assert(bounds.x>0 and bounds.y>0 and bounds.z>0,"树木各部分仍有有效实体范围")
    end
end)
