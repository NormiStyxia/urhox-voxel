-- 固定坑壁视角，只由渲染验证加载，不改变正式游戏流程。
local V = _G["V"]
V.atFrame(8, function()
    local game = _G["RUINS"]
    V.assert(game ~= nil, "遗迹场景已加载")
    if not game then return end
    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("SceneUpdate")
    UnsubscribeFromEvent("PostUpdate")
    game.world.updateEnabled = false
    local camera = game.nomiCtl:CameraNode()
    camera.worldPosition = Vector3(10.5, 2.1, 12.0)
    camera:LookAt(Vector3(17.5, 2.8, 11.0))
    game.nomiCtl:Camera().fov = 62
    game.dayNight.lockHour = 15
    game.dayNight:SetHour(15)
    game.dayNight:Update(0.5)
    local surfaces = 0
    for i = 0, game.world:GetVolumeCount() - 1 do
        local volume = game.world:GetVolume(i)
        local material = volume.material
        if material and material:GetShaderParameter("masonry_mode"):GetFloat() == 4 then
            surfaces = surfaces + 1
            V.assertNear(material:GetShaderParameter("wall_radius"):GetFloat(), 20.75, 0.001, "坑壁石缝使用内圈半径")
            local grid = volume:GetGrid()
            local dims = grid:GetDimensions()
            local upperMoss = 0
            local upperStone = 0
            for x = 0, dims.x - 1 do
                for z = 0, dims.z - 1 do
                    for y = 0, dims.y - 1 do
                        if grid:IsSolid(x, y, z) then
                            local height = volume:GetNode():LocalToWorld(Vector3(0, (y + 0.5) * volume.voxelSize, 0)).y
                            if height > 3 and height < 5.5 then
                                local slot = grid:GetVoxelMaterial(x, y, z)
                                if slot == 104 then upperMoss = upperMoss + 1 end
                                if slot >= 100 and slot <= 103 then upperStone = upperStone + 1 end
                            end
                        end
                    end
                end
            end
            V.assert(upperMoss == 0 and upperStone > 0, "上半墙不再被整列标记为潮湿墙脚")
        end
    end
    V.assert(surfaces == 4, "四片坑壁均启用独立环形砌石材质")
    print("WallSurfaceViewTest: 固定中央坑壁视角，检查四片挡土墙")
end)
