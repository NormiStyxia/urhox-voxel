-- ====================================================================
-- town.lua — 街区装配:地面 + mmmm 社区模型摆放表
--
-- 一物一 volume 是刻意的:伤害分裂按 volume 标记,一栋楼一个 volume 比
-- 巨型场景块快得多,倒塌语义也自然。模型来自 Mini Mike's Metro Minis
-- (CC BY 4.0,见项目根 ATTRIBUTION.md),.vox 调色板自动认领世界空槽。
-- ====================================================================

local config = require("config")

local M = {}
M.lampLights = {}    -- 路灯点光,夜间由 main 开启

-- 中心轴心摆放:表里的 (x, z) 是模型脚印中心。volume 原生绕最小角旋转,
-- 带朝向的摆放会把脚印整个甩走(第一版出租车因此嵌进了房墙),这里按
-- 模型真实尺寸把最小角补偿回去,再 finalize。
local function PlaceModel(world, model, voxelSize, position, rotationY)
    local m = cache:GetResource("VoxelModel", "models/" .. model .. ".vox")
    if m == nil then
        print("[Town] missing model: " .. model)
        return nil
    end
    local rot = Quaternion(rotationY or 0.0, Vector3(0.0, 1.0, 0.0))
    local volume = world:CreateVolumeFromModel(m, voxelSize, Vector3.ZERO, rot)
    local dims = volume:GetGrid():GetDimensions()
    local node = volume:GetNode()
    node.position = position
        + rot * Vector3(-dims.x * voxelSize * 0.5, 0.0, -dims.z * voxelSize * 0.5)
    volume.material = world:GetPaletteMaterial()
    return volume
end

local function PlaceStatic(world, model, voxelSize, position, rotationY)
    local volume = PlaceModel(world, model, voxelSize, position, rotationY)
    if volume == nil then return nil end
    world:FinalizeVolume(volume)
    volume:RebuildGeometry()
    return volume
end

local function PlaceDynamic(world, model, voxelSize, position, rotationY, density)
    local volume = PlaceModel(world, model, voxelSize, position, rotationY)
    if volume == nil then return nil end
    volume.density = density or 250.0
    world:FinalizeVolumeAsDynamic(volume)
    volume:RebuildGeometry()
    return volume
end

-- 180m x 180m 地面:3x3 拼块(单块 240 格 x 0.25 = 60m,贴住 256/轴上限)。
-- 分块另有实利:炸药炸坑只标记所在块,伤害标记法不用扫整张大地皮。
-- 中列/中行的块上画贯通的十字沥青街;东列(tx==2, x>30)整体是**海湾**:
-- 泥沙海床沉到 -2.0,西缘一条 6m 沙滩坡爬回岸线,水面由 world 的水平面提供。
local function BuildGround(world)
    for tx = 0, 2 do
        for tz = 0, 2 do
            if tx == 2 then
                -- 海湾块:海床 + 西缘沙滩坡(海床顶 -2.0,7 层 x 0.25 = 1.75 厚)
                local origin = Vector3(-90.0 + tx * 60.0, -3.75, -90.0 + tz * 60.0)
                local ground = world:CreateVolume(240, 15, 240, 0.25, origin)
                local g = ground:GetGrid()
                g:FillBox(0, 0, 0, 239, 6, 239, true)
                -- 沙滩坡:x 局部 0..31(8m),每 4 格抬一层,爬到岸线高度 y=0
                for step = 0, 7 do
                    g:FillBox(step * 4, 7, 0, 239, 7 + step, 239, false)  -- 先清
                end
                for step = 0, 7 do
                    g:FillBox(0, 7 + step, 0, 31 - step * 4, 7 + step, 239, true)
                end
                g:PaintBox(0, 0, 0, 100000, 100000, 100000, config.MAT_DIRT)
                ground.material = world:GetPaletteMaterial()
                world:FinalizeVolume(ground)
                ground:RebuildGeometry()
            else
                local origin = Vector3(-90.0 + tx * 60.0, -0.75, -90.0 + tz * 60.0)
                local ground = world:CreateVolume(240, 3, 240, 0.25, origin)
                local g = ground:GetGrid()
                g:FillBox(0, 0, 0, 239, 2, 239, true)
                g:PaintBox(0, 0, 0, 100000, 100000, 100000, config.MAT_GRASS)
                if tx == 1 then    -- 南北街贯通中列
                    g:PaintBox(104, 0, 0, 135, 100000, 239, config.MAT_ASPHALT)
                end
                if tz == 1 then    -- 东西街贯通中行
                    g:PaintBox(0, 0, 104, 239, 100000, 135, config.MAT_ASPHALT)
                end
                ground.material = world:GetPaletteMaterial()
                world:FinalizeVolume(ground)
                ground:RebuildGeometry()
            end
        end
    end

    -- 木栈桥:东西街尽头伸进海湾,登船点
    -- 码头顶 = -0.30 + 0.5 = +0.20:高于水面(-0.15)+ 视觉波峰(≈0.19),
    -- 否则 Gerstner 浪尖从甲板穿出成白色泡沫斑(踩过)
    local pier = world:CreateVolume(40, 2, 10, 0.25, Vector3(29.0, -0.30, 6.8))
    local pg = pier:GetGrid()
    pg:FillBox(0, 0, 0, 39, 1, 9, true)
    pg:PaintBox(0, 0, 0, 100000, 100000, 100000, config.MAT_WOOD)
    pier.material = world:GetPaletteMaterial()
    world:FinalizeVolume(pier)
    pier:RebuildGeometry()
end

-- 可挖土堆(挖掘机/喷枪的目标)
local function BuildDirtMound(world, origin)
    local nx, ny, nz = 40, 14, 40
    local volume = world:CreateVolume(nx, ny, nz, 0.1, origin, Quaternion())
    local g = volume:GetGrid()
    for y = 0, ny - 1 do
        if nx - 1 - y > y then
            g:FillBox(y, y, y, nx - 1 - y, y, nz - 1 - y, true)
        end
    end
    g:PaintBox(0, 0, 0, 100000, 100000, 100000, config.MAT_DIRT)
    volume.material = world:GetPaletteMaterial()
    world:FinalizeVolume(volume)
    volume:RebuildGeometry()
    return volume
end

-- 演示门:通用抓取机制的教具——柱静态、门动态挂垂直铰链,走近右键抓住
-- 门沿即可拉开/推上(力走约束求解器,门自己绕铰链转)。
-- 门与柱之间留 0.1m 缝:约束不会关掉两体碰撞,贴脸会被摩擦焊死(单测踩过)。
local function BuildYardGate(world)
    local mat = world:GetPaletteMaterial()
    local post = world:CreateVolume(1, 8, 1, 0.25, Vector3(2.0, 0.0, -5.0))
    post:GetGrid():FillBox(0, 0, 0, 0, 7, 0, true)
    post:GetGrid():PaintBox(0, 0, 0, 0, 7, 0, config.MAT_TRACK)
    post.material = mat
    world:FinalizeVolume(post)
    local post2 = world:CreateVolume(1, 8, 1, 0.25, Vector3(3.5, 0.0, -5.0))
    post2:GetGrid():FillBox(0, 0, 0, 0, 7, 0, true)
    post2:GetGrid():PaintBox(0, 0, 0, 0, 7, 0, config.MAT_TRACK)
    post2.material = mat
    world:FinalizeVolume(post2)

    local door = world:CreateVolume(4, 7, 1, 0.25, Vector3(2.35, 0.25, -5.0))
    door:GetGrid():FillBox(0, 0, 0, 3, 6, 0, true)
    door:GetGrid():PaintBox(0, 0, 0, 3, 6, 0, config.MAT_WOOD)
    door.material = mat
    door.density = 300.0
    world:FinalizeVolumeAsDynamic(door)
    local hinge = door:GetNode():CreateComponent("VoxelConstraint")
    hinge.constraintType = VOXEL_CONSTRAINT_HINGE
    hinge.otherVolume = post
    hinge.worldPosition = Vector3(2.30, 1.0, -4.875)
    hinge.rotation = Quaternion(Vector3.FORWARD, Vector3.UP)
    hinge.otherRotation = Quaternion(Vector3.FORWARD, Vector3.UP)
    hinge:Rebuild()
end

-- 全息投影:SurfaceShader × 调色板纹理的参考示例(shader 见
-- assets/Shaders/BLGL/VoxelHologram.shader,注释里有完整心智模型)。
-- 体素顶点色只带调色板索引,自定义 shader 从 world:GetPaletteTexture() 查表
-- 拿到 .vox 原色再重新演绎——扫描线/闪烁/轮廓光全在 GPU,Lua 零每帧逻辑。
-- 悬浮呼吸是顶点位移(纯视觉),碰撞体不动;打碎后碎块继承材质,断面显示
-- 故障红(COLOR.g 断面位),破坏本身成为表演的一部分。
local holoMat = nil
local holoWorld = nil
local function BuildHologram(world)
    -- 巨型警察全息(小镇吉祥物),站十字路口北侧草坪空档(house2 东缘与土堆
    -- 西缘之间),离房子画布脚印/长椅/树都有余量
    local volume = PlaceModel(world, "chr_cop1", 0.16, Vector3(0.0, 0.35, 10.0), 180.0)
    if volume == nil then return end
    local mat = Material:new()
    if mat:SetSurfaceShader("Shaders/BLGL/VoxelHologram.shader") then
        holoMat = mat
        holoWorld = world
        volume.material = mat
        -- SetSurfaceShader 是同步的,返回 true 时槽位表已就绪:纹理设一次即可,
        -- 持久有效。只有开发期热重载 .shader(auto-reload 开启)会重新分配槽位,
        -- 那种场景在重载后重设一次,不需要每帧重申(实测 300 帧验证过)。
        mat:SetSurfaceTexture("palette_tex", world:GetPaletteTexture())
    end
    -- 失败时保持 PlaceModel 里已设的调色板材质,正常实体渲染
    world:FinalizeVolume(volume)
    volume:RebuildGeometry()
end


function M.Build(world)
    BuildGround(world)
    BuildDirtMound(world, Vector3(9.0, 0.0, 9.0))
    BuildDirtMound(world, Vector3(-42.0, 0.0, 26.0))

    -- 摆放表:{model, voxelSize, 中心x, 中心z, yaw}。街道十字在原点,沥青带
    -- x/z ∈ [-4, 4]。北排房临街面朝南(yaw 180),南排朝北(yaw 0)。
    -- 改表必跑 tools/dev/town_layout_check.py(同步它的表!):动态物嵌进静态体
    -- 会永久抖动——房子画布 64 格但实心常顶满,凭画布中心目测必嵌(修过 11 处)。
    local statics = {
        { "obj_house1", 0.15, -21.0, 9.5, 180.0 },
        { "obj_house2", 0.15, -11.0, 9.5, 180.0 },
        { "obj_house3", 0.15, 18.0, 9.5, 180.0 },
        { "obj_house4", 0.15, -21.0, -11.5, 0.0 },
        { "obj_house5", 0.15, -11.0, -11.5, 0.0 },
        { "obj_house6", 0.15, 9.0, -11.5, 0.0 },
        { "obj_house7", 0.15, 19.0, -11.5, 0.0 },
        { "obj_house8", 0.15, 9.0, 19.0, 180.0 },
        -- 街道家具(沿北侧人行道 z≈5)
        { "obj_busstop", 0.1, -7.5, 5.4, 180.0 },
        { "obj_bench1", 0.1, 1.5, 5.2, 180.0 },
        { "obj_fence1", 0.1, -21.0, 4.6, 0.0 },
        { "obj_tree1", 0.12, -16.0, 14.0, 0.0 },
        { "obj_tree2", 0.12, 13.0, 14.0, 60.0 },
        { "obj_tree3", 0.12, 15.0, -17.0, 0.0 },
        { "obj_celltower", 0.12, 23.0, 21.0, 0.0 },
        { "obj_crosswalk", 0.1, -1.5, -4.5, 0.0 },
        -- 外圈街区(180m 场地的四个象限)
        { "obj_house1", 0.15, -38.0, 9.5, 180.0 },
        { "obj_house5", 0.15, -52.0, 9.5, 180.0 },
        { "obj_house2", 0.15, -38.0, -11.5, 0.0 },
        { "obj_house7", 0.15, -52.0, -11.5, 0.0 },
        { "obj_house3", 0.15, -48.0, 22.0, 90.0 },
        { "obj_house6", 0.15, -48.0, -34.0, 0.0 },
        { "obj_house4", 0.15, 20.0, -44.0, 0.0 },
        { "obj_house8", 0.15, -13.0, 34.0, 180.0 },
        { "obj_house1", 0.15, 13.0, 34.0, 90.0 },
        { "obj_house2", 0.15, -13.0, -32.0, 0.0 },
        { "obj_house6", 0.15, 14.0, -32.0, -90.0 },
        { "obj_house5", 0.15, -22.0, -44.0, 0.0 },
        { "obj_fence1", 0.1, -38.0, 4.6, 0.0 },
        { "obj_fence1", 0.1, -44.0, -4.6, 0.0 },
        { "obj_busstop", 0.1, 26.0, -5.4, 0.0 },
        -- 第二环:房屋配色变体铺满纵街两侧与远端街区
        { "obj_house1a", 0.15, 9.5, 26.0, -90.0 },
        { "obj_house2a", 0.15, -9.5, 26.0, 90.0 },
        { "obj_house3a", 0.15, 9.5, 44.0, -90.0 },
        { "obj_house4a", 0.15, -9.5, 44.0, 90.0 },
        { "obj_house5a", 0.15, 9.5, -24.0, -90.0 },
        { "obj_house6a", 0.15, -9.5, -24.0, 90.0 },
        { "obj_house7a", 0.15, 9.5, -44.0, -90.0 },
        { "obj_house8a", 0.15, -9.5, -44.0, 90.0 },
        { "obj_house2", 0.15, -32.0, 34.0, 180.0 },
        { "obj_house7", 0.15, -56.0, 34.0, 120.0 },
        { "obj_house3", 0.15, -34.0, -40.0, 45.0 },
        { "obj_house4", 0.15, -34.0, 44.0, -135.0 },
        -- 行道树:沿东西街两侧成排
        { "obj_tree1", 0.12, -34.0, 20.0, 0.0 },
        { "obj_tree2", 0.12, -48.0, -20.0, 30.0 },
        { "obj_tree3", 0.12, -30.0, -26.0, 0.0 },
        { "obj_tree1", 0.12, 28.0, 24.0, 90.0 },
        { "obj_tree2", 0.12, -40.0, 36.0, 0.0 },
        { "obj_tree3", 0.12, 24.0, -28.0, 45.0 },
        { "obj_tree1", 0.12, -20.0, 40.0, 0.0 },
        { "obj_tree2", 0.12, 24.0, -40.0, 120.0 },
        { "obj_tree3", 0.12, -44.0, 44.0, 0.0 },
        { "obj_tree1a", 0.12, -28.0, 6.5, 0.0 },
        { "obj_tree1b", 0.12, -44.0, 6.5, 40.0 },
        { "obj_tree2a", 0.12, 24.0, 6.5, 0.0 },
        { "obj_tree2b", 0.12, 26.5, 6.5, 75.0 },
        { "obj_tree4", 0.12, -28.0, -6.8, 0.0 },
        { "obj_tree1a", 0.12, 22.0, -6.8, 160.0 },
        { "obj_tree4", 0.12, 27.0, -6.8, 0.0 },
        { "obj_tree1b", 0.12, 6.8, 22.0, 0.0 },
        { "obj_tree2a", 0.12, -6.8, 38.0, 220.0 },
        { "obj_tree4", 0.12, 6.8, -36.0, 0.0 },
        { "obj_tree2b", 0.12, -6.8, -20.0, 15.0 },
        -- 草丛点缀四方草地
        { "env_grass1a", 0.1, -14.0, 16.0, 0.0 },
        { "env_grass1b", 0.1, -26.0, 30.0, 70.0 },
        { "env_grass1c", 0.1, -40.0, 16.0, 0.0 },
        { "env_grass1d", 0.1, -18.0, -18.0, 120.0 },
        { "env_grass1a", 0.1, -38.0, -30.0, 0.0 },
        { "env_grass1b", 0.1, 18.0, 18.0, 0.0 },
        { "env_grass1c", 0.1, 24.0, 36.0, 45.0 },
        { "env_grass1d", 0.1, -46.0, 14.0, 0.0 },
        { "env_grass1a", 0.1, 20.0, -22.0, 200.0 },
        { "env_grass1b", 0.1, 22.0, -42.0, 0.0 },
        { "env_grass1c", 0.1, -22.0, 44.0, 90.0 },
        { "env_grass1d", 0.1, 14.0, 46.0, 0.0 },
        { "env_grass1a", 0.1, -46.0, -42.0, 30.0 },
        { "env_grass1b", 0.1, -52.0, -16.0, 0.0 },
    }
    for _, e in ipairs(statics) do
        PlaceStatic(world, e[1], e[2], Vector3(e[3], 0.0, e[4]), e[5])
    end

    -- 路灯:obj_stlight 系列(注意不是 obj_street——那是街道地件,曾被误当
    -- 路灯摆了一轮,"只见光不见杆")。
    --
    -- 灯罩坐标表:离线解析 .vox 的暖色玻璃体素所得(assets/models/_shade_scan.py,
    -- 引擎坐标系、体素单位)。运行时按 voxelSize 缩放、经节点变换跟随旋转。
    -- 曾用"顶部体素带聚类"运行时猜测:多臂灯四罩被并成一簇挂在杆心、单臂灯
    -- 的臂/杆顶被误判成额外光源——灯罩位置是资产事实,该离线求准,不该猜。
    local LAMP_SHADES = {
        obj_stlight1 = { Vector3(2.5, 30.5, 2.0), Vector3(35.5, 30.5, 2.0) },
        obj_stlight2 = { Vector3(2.5, 30.5, 2.0) },
        obj_stlight3 = { Vector3(13.0, 60.5, 2.5), Vector3(13.0, 60.5, 25.5),
                         Vector3(23.5, 60.5, 14.0), Vector3(2.5, 60.5, 14.0) },
    }

    -- 朝向约定:灯臂必须探向街面(远离临街建筑)。街道带 |x|<=4 或 |z|<=4,
    -- 灯立在 ±4.6 的人行道沿。若某盏灯臂方向反了,只调它的 yaw。
    local lamps = {
        { "obj_stlight1", -16.0, 4.6, 0.0 }, { "obj_stlight2", 12.0, 4.6, 0.0 },
        { "obj_stlight1", 26.0, -4.6, 180.0 }, { "obj_stlight3", -30.0, -4.6, 180.0 },
        { "obj_stlight2", 4.6, 16.0, -90.0 }, { "obj_stlight1", -4.6, 30.0, 90.0 },
        { "obj_stlight3", 4.6, -16.0, -90.0 }, { "obj_stlight2", -4.6, -34.0, 90.0 },
    }
    for _, e in ipairs(lamps) do
        local volume = PlaceStatic(world, e[1], 0.1, Vector3(e[2], 0.0, e[3]), e[4])
        if volume ~= nil then
            local node = volume:GetNode()
            local voxelSize = volume.voxelSize
            for _, c in ipairs(LAMP_SHADES[e[1]] or {}) do
                local shadeWorld = node.worldTransform * (c * voxelSize)
                -- 标准路灯:灯罩下垂直下照的宽锥聚光。
                -- 锥角用 inner/outerConeAngle(本引擎 UE 式聚光参数,用户抓帧
                -- 定位;老 fov 属性是死参数,设了无效——锥恒为默认 30 度)。
                -- 朝正下 = Quaternion(+90, X):-90 朝天,SetDirection(0,-1,0) 与
                -- UP 共线退化(五灯判决探针,2026-08-04)。
                local lightNode = node:GetScene():CreateChild("LampLight")
                lightNode.position = shadeWorld + Vector3(0.0, -0.3, 0.0)
                lightNode.rotation = Quaternion(90.0, Vector3(1.0, 0.0, 0.0))
                local light = lightNode:CreateComponent("Light")
                light.lightType = LIGHT_SPOT
                light.color = Color(1.0, 0.72, 0.42)
                light.range = 12.0
                light.innerConeAngle = 65.0
                light.outerConeAngle = 90.0
                light.brightness = 30.0
                light.castShadows = false
                light:SetAttribute("Affect Volumetric Fog", Variant(true))
                light.enabled = false
                table.insert(M.lampLights, light)
            end
        end
    end

    -- 路口红绿灯(纯装饰道具)
    PlaceStatic(world, "obj_trlight1", 0.1, Vector3(4.8, 0.0, 4.8), 180.0)

    -- 动态道具:可推、可拖(右键)、可炸飞。停放车沿南侧路缘 z≈-5.6。
    local dynamics = {
        { "veh_car1", 0.12, -8.0, -5.6, 90.0, 220.0 },
        { "veh_car2", 0.12, -14.0, -5.6, 90.0, 220.0 },
        { "veh_cab1", 0.12, 7.0, -5.6, -90.0, 220.0 },
        { "veh_police1", 0.12, -11.0, -3.0, -90.0, 220.0 },
        { "veh_bus", 0.12, 16.0, 2.8, 90.0, 300.0 },
        { "obj_hydrant", 0.08, -5.0, 5.0, 0.0, 500.0 },
        { "obj_mailbox", 0.08, -3.2, 5.0, 180.0, 350.0 },
        { "obj_trashcan1", 0.08, 3.6, 5.0, 0.0, 200.0 },
        { "obj_cone1", 0.08, -1.0, -2.0, 0.0, 120.0 },
        { "obj_cone1", 0.08, 1.2, -0.8, 25.0, 120.0 },
        { "obj_container1", 0.12, 4.8, 11.5, 15.0, 280.0 },
        { "obj_planter1", 0.1, -9.8, 4.15, 0.0, 400.0 },
        { "chr_cop1", 0.09, -1.8, 4.3, 135.0, 400.0 },
        { "chr_lady1", 0.09, 6.5, 0.8, -120.0, 400.0 },
        -- 外圈停放与杂物
        { "veh_car1", 0.12, -32.6, -5.6, 90.0, 220.0 },
        { "veh_car2", 0.12, 27.5, -3.0, 90.0, 220.0 },
        { "veh_cab1", 0.12, 5.4, -33.0, 0.0, 220.0 },
        { "obj_container1", 0.12, -46.0, 30.0, -20.0, 280.0 },
        { "obj_trashcan1", 0.08, 29.2, -4.4, 0.0, 200.0 },
        { "obj_cone1", 0.08, 4.6, -24.0, 0.0, 120.0 },
        { "obj_cone1", 0.08, -4.0, 30.4, 40.0, 120.0 },
        -- 第二批:更多车与街景道具
        { "veh_suv1", 0.12, -20.0, -5.6, 90.0, 240.0 },
        { "veh_mini1", 0.12, 14.0, -5.6, 90.0, 200.0 },
        { "veh_car3", 0.12, -5.6, 16.4, 0.0, 220.0 },
        { "veh_car4", 0.12, -5.1, -14.0, 180.0, 220.0 },
        { "veh_lunch1", 0.12, 18.2, -5.8, -90.0, 300.0 }, -- 餐车(南人行道)
        { "obj_cart1", 0.1, 10.8, 4.6, 200.0, 180.0 },
        { "obj_bench2", 0.1, -4.8, 8.5, -90.0, 260.0 },
        { "obj_trashcan2", 0.08, -15.5, 4.2, 0.0, 200.0 },
        { "obj_mailbox2", 0.08, 23.7, 4.6, 180.0, 350.0 },
        { "obj_planter2", 0.1, 8.0, 4.8, 0.0, 400.0 },
    }
    for _, e in ipairs(dynamics) do
        PlaceDynamic(world, e[1], e[2], Vector3(e[3], 0.05, e[4]), e[5], e[6])
    end

    BuildYardGate(world)
    BuildHologram(world)

    world:OptimizeBroadPhase()
end

function M.SetLampsEnabled(enabled)
    for _, light in ipairs(M.lampLights) do
        light.enabled = enabled
    end
end

return M
