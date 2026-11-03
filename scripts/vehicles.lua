-- ====================================================================
-- vehicles.lua — 可驾驶载具:汽车 / 工程机械 / 船只 / 飞行器 / Assembly 教具
--
-- 从 VoxelVehicleDemo 移植的官方参考实现。三条铁律(设计文档 vehicle-system):
--   1. 悬挂挂点必须在壳体之外(壳底之下或雕空轮舱内),否则 ray 自命中火箭起飞
--   2. restLength 按"静载压缩 + 5cm"配,不是按行程配
--   3. 铰链马达正目标 = 臂向下;steer +1 = 右转(实测约定)
-- ====================================================================

local config = require("config")

local M = {}
M.list = {}    -- { name, chassis, vehicle?, wheels, assembly?, arms?, length, digTimer }

local world
---@type table?
local assemblyDemo = nil
---@type table?
local assemblyHelicopter = nil
local assemblyEventsSubscribed = false

-- Teardown 抽取模型(本地资产,gitignore;缺失时各 builder 回退程序化造型)。
-- 版权:Tuxedo Labs,仅限本地,禁止提交/分发。抽取工具:tools/dev/teardown_vehicle_extract.py
local function TeardownModel(name)
    return cache:GetResource("VoxelModel", "models/teardown/" .. name)
end

-- modelName/diaVox/widthVox 可选:换轮模型时给出其体素直径与厚度(默认引擎 VoxWheel,11 直径 3 厚)
local function AddVisualWheels(entry, corners, radius, attachY, rest, modelName, diaVox, widthVox)
    local model = (modelName ~= nil) and TeardownModel(modelName) or nil
    if model == nil then
        model = cache:GetResource("VoxelModel", "Models/VoxWheel.vox")
        diaVox, widthVox = 11, 3
    end
    local v = (radius * 2.0) / diaVox
    -- 左右侧分界:轮模型有里外脸(毂盖朝外),同朝向两侧共用会有一侧装反
    -- (用户抓获:车左侧轮里外反)。高 z 侧(车左)绕竖轴镜像 180 度。
    local zCenter = 0.0
    for _, c in ipairs(corners) do zCenter = zCenter + c.z end
    zCenter = zCenter / #corners
    for i, corner in ipairs(corners) do
        local hub = entry.chassis:GetNode():CreateChild("WheelHub" .. i)
        hub.temporary = true
        hub.position = Vector3(corner.x, corner.y, corner.z)
        local wheelVolume = world:CreateVolumeFromModel(model, v, Vector3.ZERO)
        wheelVolume.material = world:GetPaletteMaterial()
        wheelVolume:RebuildGeometry()
        local wheelNode = wheelVolume:GetNode()
        wheelNode.temporary = true
        wheelNode:SetParent(hub)
        if corner.z > zCenter then
            wheelNode.rotation = Quaternion(180.0, Vector3(0.0, 1.0, 0.0))
            wheelNode.position = Vector3(radius, -radius, 0.5 * widthVox * v)
        else
            wheelNode.position = Vector3(-radius, -radius, -0.5 * widthVox * v)
        end
        table.insert(entry.wheels, { node = hub, radius = radius, spin = 0.0,
            index = i - 1, x = corner.x, z = corner.z, attachY = attachY, rest = rest })
    end
end

-- 车头大灯:LIGHT_RECT 面光,挂在载具部件的子节点上跟随其变换(挖掘机挂
-- 驾驶舱,转舱时灯随舱转)。direction 是父节点局部系:+X 前向,带俯角照路。
-- 上车自动开(player 调 SetHeadlights),下车 Park 统一关。
local function AddHeadlight(entry, volume, localPos)
    local node = volume:GetNode():CreateChild("Headlight")
    node.temporary = true
    node.position = localPos
    node.direction = Vector3(1.0, -0.12, 0.0)   -- 俯角调浅:光毯甩得更远
    local light = node:CreateComponent("Light")
    light.lightType = LIGHT_RECT
    light.color = Color(1.0, 0.95, 0.82)
    light.range = 30.0
    light.brightness = 14.0
    light.sourceWidth = 0.35
    light.sourceHeight = 0.2
    light.castShadows = false
    light:SetAttribute("Affect Volumetric Fog", Variant(true))
    light.enabled = false
    entry.headlights = entry.headlights or {}
    table.insert(entry.headlights, light)
end

function M.SetHeadlights(entry, on)
    if entry == nil or entry.headlights == nil then return end
    for _, light in ipairs(entry.headlights) do
        if light:GetNode() ~= nil then light.enabled = on end
    end
end

local function AttachHinged(volume, parentVolume, anchor, axis, holdTorque, limitMin, limitMax)
    local constraint = volume:GetNode():CreateComponent("VoxelConstraint")
    constraint.constraintType = VOXEL_CONSTRAINT_HINGE
    constraint.otherVolume = parentVolume
    constraint.worldPosition = volume:GetNode().worldTransform * anchor
    constraint.rotation = Quaternion(Vector3.FORWARD, axis)
    local worldAxis = volume:GetNode().worldRotation * axis
    local otherAxis = parentVolume:GetNode().worldRotation:Inverse() * worldAxis
    constraint.otherRotation = Quaternion(Vector3.FORWARD, otherAxis)
    constraint:SetAngularMotorVelocity(0.0, holdTorque)
    if limitMin ~= nil then constraint:SetAngularLimits(limitMin, limitMax) end
    constraint:Rebuild()
    return constraint
end

-- 通用直线弹簧连接。Slider 的局部 X 轴是滑动轴，因此两个端点都把
-- Vector3.RIGHT 对齐到给定世界轴；组件挂在更重的 parentVolume 上，符合
-- Jolt 对质量差较大的 Slider body1 的建议。
local function AttachSpringSlider(parentVolume, childVolume, worldAnchor, worldAxis,
    limitMin, limitMax, restPosition, stiffness, damping)
    local constraint = parentVolume:GetNode():CreateComponent("VoxelConstraint")
    constraint.constraintType = VOXEL_CONSTRAINT_SLIDER
    constraint.otherVolume = childVolume
    constraint.worldPosition = worldAnchor
    local parentAxis = parentVolume:GetNode().worldRotation:Inverse() * worldAxis
    local childAxis = childVolume:GetNode().worldRotation:Inverse() * worldAxis
    constraint.rotation = Quaternion(Vector3.RIGHT, parentAxis)
    constraint.otherRotation = Quaternion(Vector3.RIGHT, childAxis)
    constraint:SetLinearLimits(limitMin, limitMax)
    constraint:SetLinearSpring(restPosition, stiffness, damping)
    assert(constraint:Rebuild(), "VoxelTown: failed to build spring slider")
    return constraint
end

-- VoxelAssembly 教具车:每个覆盖件仍是独立 VoxelVolume,但装配后只占一个
-- Jolt body。车门/保险杠保留自己的材质、碰撞参数和稳定 volumeId;撞墙后
-- 由 member stress 超阈值自动脱离,不是脚本删除 Node 的视觉把戏。
local function BuildAssemblyCrashWall(origin)
    local volume = world:CreateVolume(4, 24, 30, 0.1, origin, Quaternion())
    local g = volume:GetGrid()
    g:FillBox(0, 0, 0, 3, 23, 29, true)
    g:PaintBox(0, 0, 0, 3, 23, 29, config.MAT_CRASH_WALL)
    -- 黄黑警示条让测试墙从普通建筑中一眼可辨。
    for y = 2, 20, 6 do
        g:PaintBox(0, y, 0, 3, y + 2, 29, config.MAT_FUSE)
    end
    volume:GetNode().name = "AssemblyCrashWall"
    volume.destructible = false
    volume.material = world:GetPaletteMaterial()
    world:FinalizeVolume(volume)
    volume:RebuildGeometry()
    return volume
end

local function BuildAssemblyCar(origin)
    local entry = {
        name = "Assembly 解体车",
        wheels = {},
        length = 5.6,
        width = 2.4,
        height = 1.8,
        isAssemblyDemo = true,
        detachedCount = 0,
        initialMembers = 6,
        lastAssemblyMessage = "B 发射,或上车后撞向前方黄黑墙",
        partNames = {},
    }
    local v = 0.1

    local function MakePart(name, nx, ny, nz, offset, density, material, fill)
        local volume = world:CreateVolume(nx, ny, nz, v, origin + offset, Quaternion())
        volume:GetNode().name = name
        fill(volume:GetGrid())
        volume:GetGrid():PaintBox(0, 0, 0, 100000, 100000, 100000, material)
        volume.material = world:GetPaletteMaterial()
        volume.density = density
        world:FinalizeVolumeAsDynamic(volume)
        volume:RebuildGeometry()
        entry.partNames[volume:GetNode().ID] = name
        return volume
    end

    entry.chassis = MakePart("承力底盘", 52, 8, 22, Vector3.ZERO, 260.0,
        config.MAT_ASSEMBLY_BODY, function(g)
            g:FillBox(0, 0, 0, 51, 5, 21, true)
            g:FillBox(5, 6, 2, 46, 7, 19, true)
            -- 真轮拱让悬挂射线从壳体外出发,避免命中自己的底盘。
            for _, x in ipairs({ 7, 39 }) do
                g:FillBox(x, 0, 0, x + 7, 4, 3, false)
                g:FillBox(x, 0, 18, x + 7, 4, 21, false)
            end
        end)

    entry.frontBumper = MakePart("前保险杠", 5, 4, 24, Vector3(5.1, 0.2, -0.1), 180.0,
        config.MAT_ASSEMBLY_PANEL, function(g)
            g:FillBox(0, 0, 0, 4, 3, 23, true)
        end)
    entry.frontBumper.friction = 0.2
    entry.frontBumper.restitution = 0.05
    -- 解析代理默认以体素占用 bounds 为中心；localOffset 只用于在此基础上偏移。
    -- 保险杠尺寸与 5×4×24 个 0.1m 体素完全一致，因此不需要额外偏移。
    entry.frontBumper:SetCollisionBox(Vector3(0.5, 0.4, 2.4))

    entry.rearBumper = MakePart("后保险杠", 5, 4, 24, Vector3(-0.4, 0.2, -0.1), 180.0,
        config.MAT_ASSEMBLY_PANEL, function(g)
            g:FillBox(0, 0, 0, 4, 3, 23, true)
        end)
    entry.leftDoor = MakePart("左车门", 18, 7, 2, Vector3(1.7, 0.75, -0.05), 120.0,
        config.MAT_ASSEMBLY_PANEL, function(g)
            g:FillBox(0, 0, 0, 17, 6, 1, true)
        end)
    entry.rightDoor = MakePart("右车门", 18, 7, 2, Vector3(1.7, 0.75, 2.05), 120.0,
        config.MAT_ASSEMBLY_PANEL, function(g)
            g:FillBox(0, 0, 0, 17, 6, 1, true)
        end)
    entry.roof = MakePart("车顶笼", 28, 8, 18, Vector3(1.3, 0.8, 0.2), 90.0,
        config.MAT_ASSEMBLY_BODY, function(g)
            g:FillBox(0, 5, 0, 27, 7, 17, true)
            g:FillBox(0, 0, 0, 2, 7, 17, true)
            g:FillBox(25, 0, 0, 27, 7, 17, true)
        end)

    local assembly = world:CreateAssembly(entry.chassis)
    assert(assembly ~= nil, "VoxelTown: failed to create crash-car assembly")
    for _, member in ipairs({ entry.frontBumper, entry.rearBumper,
        entry.leftDoor, entry.rightDoor, entry.roof }) do
        assert(assembly:AddVolume(member), "VoxelTown: failed to add assembly member")
    end
    entry.assembly = assembly

    -- 纯参数控制焊点强度。引擎会把 Jolt compound contact impulse 归属到实际
    -- 命中的 member：路面颠簸主要由底盘承受，覆盖件不会误掉；重撞覆盖件时
    -- 则按这里的完整件 breakForce / breakTorque 自动脱离；体素受损会由引擎自动
    -- 削弱有效连接强度，边缘超载采用三步迟滞，严重撞击会立即断裂。
    assembly:SetMemberBreakThreshold(entry.frontBumper, 20000.0, 20000.0)
    assembly:SetMemberBreakThreshold(entry.leftDoor, 200000.0, 120000.0)
    assembly:SetMemberBreakThreshold(entry.rightDoor, 200000.0, 120000.0)
    assembly:SetMemberBreakThreshold(entry.rearBumper, 220000.0, 120000.0)
    assembly:SetMemberBreakThreshold(entry.roof, 350000.0, 250000.0)
    -- 通过 assembly façade 调整共享 body;CCD 防止 B 键高速发射穿过薄墙。
    assembly:SetLinearDamping(0.08)
    assembly:SetAngularDamping(0.35)
    assembly:SetCcdEnabled(true)

    entry.vehicle = entry.chassis:GetNode():CreateComponent("VoxelVehicle")
    local k, c, rest, r = 65000.0, 7600.0, 0.18, 0.42
    -- 轮拱 x 范围分别为 3.9..4.7m 和 0.7..1.5m，物理轮与视觉轮都取
    -- 几何中心，避免侧视时后轮偏在轮坑后缘。
    local frontWheelX, rearWheelX = 4.3, 1.1
    entry.vehicle:AddWheel(Vector3(frontWheelX, 0.16, 0.4), r, rest, k, c, true, false)
    entry.vehicle:AddWheel(Vector3(frontWheelX, 0.16, 1.8), r, rest, k, c, true, false)
    entry.vehicle:AddWheel(Vector3(rearWheelX, 0.16, 0.4), r, rest, k, c, false, true)
    entry.vehicle:AddWheel(Vector3(rearWheelX, 0.16, 1.8), r, rest, k, c, false, true)
    entry.vehicle.maxDriveForce = 9500.0
    entry.vehicle:SetMaxSpeed(16.0)
    entry.vehicle.maxSteerAngle = 30.0
    entry.vehicle.grip = 0.9
    entry.vehicle:ApplyAttributes()
    AddVisualWheels(entry, {
        Vector3(frontWheelX, 0.0, 0.3), Vector3(frontWheelX, 0.0, 1.9),
        Vector3(rearWheelX, 0.0, 0.3), Vector3(rearWheelX, 0.0, 1.9) }, r, 0.16, rest)

    -- 大灯属于保险杠 Node;保险杠脱落后灯也随部件飞走,验证各 member 的
    -- Scene 身份没有因为合体而被吞掉。
    AddHeadlight(entry, entry.frontBumper, Vector3(0.48, 0.27, 0.55))
    AddHeadlight(entry, entry.frontBumper, Vector3(0.48, 0.27, 1.85))
    entry.crashWall = BuildAssemblyCrashWall(Vector3(4.0, 0.0, 0.6))
    assemblyDemo = entry
    return entry
end

-- 实体轮组装车:车身是 VoxelAssembly，四个轮胎是真实的圆柱 VoxelVolume。
-- 每个轮端先用垂直 Slider 线性弹簧连接底盘，再连接转向节/轮胎。前轮链路为
-- “车身→弹簧滑块→转向节 Y 轴铰链→轮胎 Z 轴铰链”，后轮省略转向节。
-- 崎岖路面的垂直冲击由独立悬挂吸收，滚动/转向铰链不再承担悬挂自由度。
-- VoxelRollingContact 只负责方向性抓地，不读取整车或输入。
local function BuildRollingContactCar(origin)
    local entry = {
        name = "Assembly 实体轮车",
        kind = "rolling_contact_car",
        wheels = {},
        rollingContacts = {},
        driveConstraints = {},
        suspensionConstraints = {},
        suspensionCarriers = {},
        steeringConstraints = {},
        steeringKnuckles = {},
        length = 4.2,
        width = 2.0,
        height = 1.8,
        wheelMotorSpeed = 720.0,
        wheelMotorTorque = 2400.0,
        brakeTorque = 9000.0,
        coastTorque = 120.0,
        maxSteerAngle = 30.0,
        -- 运动时前轮方向性抓地会对转向节产生回正力矩；舵机上限必须覆盖
        -- 这部分轮胎载荷，否则只会在静止、无抓地负载时成功转向。
        steerTorque = 30000.0,
        steerSpeed = 150.0,
        suspensionMin = -0.12,
        suspensionMax = 0.20,
        suspensionStiffness = 35000.0,
        suspensionDamping = 4500.0,
        -- 轮胎侧向抓地会同时加载 Slider、转向铰链和轮轴铰链。速度迭代
        -- 抑制中性转向晃动，位置迭代防止角误差累积成可见外倾。回归扫描中
        -- 默认/40/50 次的中性转向单帧跳变分别为 4.08/1.90/1.14 度，60 次降至 0.84 度。
        solverVelocitySteps = 60,
        solverPositionSteps = 40,
    }
    local v = 0.1
    local collisionGroup = 143

    local function FinalizePart(volume, density, material)
        volume.material = world:GetPaletteMaterial()
        volume.density = density
        volume.collisionGroup = collisionGroup
        volume:GetGrid():PaintBox(0, 0, 0, 100000, 100000, 100000, material)
        world:FinalizeVolumeAsDynamic(volume)
        volume:RebuildGeometry()
        return volume
    end

    entry.chassis = world:CreateVolume(42, 6, 20, v,
        origin + Vector3(0.0, 0.62, 0.0), Quaternion())
    entry.chassis:GetNode().name = "实体轮车底盘"
    entry.chassis:GetGrid():FillBox(0, 0, 0, 41, 5, 19, true)
    entry.chassis:SetComOffset(Vector3(0.0, -0.18, 0.0))
    FinalizePart(entry.chassis, 180.0, config.MAT_ASSEMBLY_BODY)

    entry.cabin = world:CreateVolume(20, 9, 16, v,
        origin + Vector3(0.9, 1.22, 0.2), Quaternion())
    entry.cabin:GetNode().name = "实体轮车驾驶舱"
    local cabinGrid = entry.cabin:GetGrid()
    cabinGrid:FillBox(0, 0, 0, 19, 2, 15, true)
    cabinGrid:FillBox(0, 3, 0, 2, 8, 15, true)
    cabinGrid:FillBox(17, 3, 0, 19, 8, 15, true)
    cabinGrid:FillBox(3, 7, 0, 16, 8, 15, true)
    FinalizePart(entry.cabin, 120.0, config.MAT_ASSEMBLY_PANEL)

    entry.assembly = world:CreateAssembly(entry.chassis)
    assert(entry.assembly ~= nil, "VoxelTown: failed to create rolling-contact car assembly")
    assert(entry.assembly:AddVolume(entry.cabin),
        "VoxelTown: failed to add rolling-contact car cabin")
    entry.assembly:SetLinearDamping(0.04)
    entry.assembly:SetAngularDamping(0.18)
    entry.assembly:SetCcdEnabled(true)

    local wheelCenterLocal = Vector3(0.45, 0.45, 0.15)
    local frontX, rearX = origin.x + 3.35, origin.x + 0.85
    local wheelY = origin.y + 0.5
    local rightZ, leftZ = origin.z - 0.18, origin.z + 2.18

    local function MakeSuspensionCarrier(index, center)
        local carrier = world:CreateVolume(3, 3, 3, v,
            center - Vector3(0.15, 0.15, 0.15), Quaternion())
        carrier:GetNode().name = "实体轮车悬挂滑块" .. index
        carrier:GetGrid():FillBox(0, 0, 0, 2, 2, 2, true)
        -- 27 个实心体素得到约 108kg 的非簧载滑块，和约 1t 车身保持可解的
        -- 质量比；过轻的中间 body 会把单轮冲击放大成 Slider 的可见角误差。
        FinalizePart(carrier, 4000.0, config.MAT_FUSE)

        local suspension = AttachSpringSlider(entry.chassis, carrier, center, Vector3.UP,
            entry.suspensionMin, entry.suspensionMax, 0.0,
            entry.suspensionStiffness, entry.suspensionDamping)
        suspension:SetSolverVelocitySteps(entry.solverVelocitySteps)
        suspension:SetSolverPositionSteps(entry.solverPositionSteps)
        table.insert(entry.suspensionCarriers, carrier)
        table.insert(entry.suspensionConstraints, suspension)
        return carrier
    end

    local function MakeSteeringKnuckle(index, center, isLeft, suspensionCarrier)
        -- 转向轴穿过轮胎中心。0.3m 小方块从底盘伸进轮毂，既能看出机械连接，
        -- 又不会把左右轮刚性连成一根会整体摆动的前桥。
        local knuckleOriginZ = isLeft and center.z - 0.3 or center.z
        local knuckle = world:CreateVolume(3, 3, 3, v,
            Vector3(center.x - 0.15, center.y - 0.15, knuckleOriginZ), Quaternion())
        knuckle:GetNode().name = "实体轮车转向节" .. index
        knuckle:GetGrid():FillBox(0, 0, 0, 2, 2, 2, true)
        -- 转向节位于轮胎与近一吨车身之间，质量不能远小于轮胎；否则单轮上台阶时
        -- 重轮会把轻转向节的铰链解算误差放大成肉眼可见的倾斜。
        FinalizePart(knuckle, 1000.0, config.MAT_FUSE)

        local steeringPivotZ = isLeft and 0.3 or 0.0
        -- 车头朝 +X、车辆右侧为 -Z。采用向下的铰链轴，使正角度遵循本文件
        -- “steer +1 = 右转”的输入约定，D 无需在控制层额外反号。
        local steeringConstraint = AttachHinged(knuckle, suspensionCarrier,
            Vector3(0.15, 0.15, steeringPivotZ), Vector3.DOWN, entry.steerTorque,
            -entry.maxSteerAngle, entry.maxSteerAngle)
        steeringConstraint:SetServo(0.0, entry.steerTorque, entry.steerSpeed)
        steeringConstraint:SetSolverVelocitySteps(entry.solverVelocitySteps)
        steeringConstraint:SetSolverPositionSteps(entry.solverPositionSteps)
        table.insert(entry.steeringKnuckles, knuckle)
        table.insert(entry.steeringConstraints, steeringConstraint)
        return knuckle
    end

    local function MakeWheel(index, center, parent)
        local wheel = world:CreateVolume(9, 9, 3, v,
            center - wheelCenterLocal, Quaternion())
        wheel:GetNode().name = "实体轮胎" .. index
        local grid = wheel:GetGrid()
        for x = 0, 8 do
            for y = 0, 8 do
                local dx, dy = x - 4, y - 4
                local radiusSquared = dx * dx + dy * dy
                if radiusSquared >= 5 and radiusSquared <= 18 then
                    grid:FillBox(x, y, 0, x, y, 2, true)
                end
            end
        end
        wheel:SetCollisionCylinderAuto(Vector3.FORWARD)
        -- 144 个实心体素在 200kg/m^3 下约 29kg，接近普通车轮，也和转向节
        -- 质量相当。旧值 1100 会得到约 158kg 的重轮，崎岖路面会拖垮双铰链链条。
        FinalizePart(wheel, 200.0, config.MAT_CAB)

        local contact = wheel:GetNode():CreateComponent("VoxelRollingContact")
        contact:SetLongitudinalGrip(0.06, 1.35, 0.22, 1.0)
        contact:SetLateralGrip(3.0, 1.45, 20.0, 0.95)
        contact:SetSupportRange(0.2, 0.7)
        contact:SetSidewallFriction(0.2)
        contact:SetNonSupportFriction(0.3)
        contact:SetRollingResistance(0.015)
        contact:ApplyAttributes()

        local driveConstraint = AttachHinged(wheel, parent, wheelCenterLocal,
            Vector3.FORWARD, entry.brakeTorque)
        -- Jolt 对同一物理岛取最大 override；在整条轮端链上重复设置不会累加开销，
        -- 但可避免某一节拆除后剩余子岛退回默认精度。
        driveConstraint:SetSolverVelocitySteps(entry.solverVelocitySteps)
        driveConstraint:SetSolverPositionSteps(entry.solverPositionSteps)
        table.insert(entry.wheels, wheel)
        table.insert(entry.rollingContacts, contact)
        table.insert(entry.driveConstraints, driveConstraint)
    end

    local rightFrontCenter = Vector3(frontX, wheelY, rightZ)
    local leftFrontCenter = Vector3(frontX, wheelY, leftZ)
    local rightFrontCarrier = MakeSuspensionCarrier(1, rightFrontCenter)
    local leftFrontCarrier = MakeSuspensionCarrier(2, leftFrontCenter)
    local rightRearCenter = Vector3(rearX, wheelY, rightZ)
    local leftRearCenter = Vector3(rearX, wheelY, leftZ)
    local rightRearCarrier = MakeSuspensionCarrier(3, rightRearCenter)
    local leftRearCarrier = MakeSuspensionCarrier(4, leftRearCenter)
    local rightKnuckle = MakeSteeringKnuckle(1, rightFrontCenter, false, rightFrontCarrier)
    local leftKnuckle = MakeSteeringKnuckle(2, leftFrontCenter, true, leftFrontCarrier)
    MakeWheel(1, rightFrontCenter, rightKnuckle)
    MakeWheel(2, leftFrontCenter, leftKnuckle)
    MakeWheel(3, rightRearCenter, rightRearCarrier)
    MakeWheel(4, leftRearCenter, leftRearCarrier)

    AddHeadlight(entry, entry.chassis, Vector3(4.15, 0.38, 0.5))
    AddHeadlight(entry, entry.chassis, Vector3(4.15, 0.38, 1.5))
    return entry
end

local function BuildPickup(origin)
    local td = TeardownModel("td_pickup.vox")
    if td ~= nil then
        -- Teardown taskmaster-4wd:53×25×16 vox @0.1 → 5.3 长 × 2.5 宽 × 1.6 高
        -- 轮位取自抽取报告(vox local (x,y,z) → engine (x*0.1, z*0.1, y*0.1))
        local entry = { name = "皮卡", wheels = {}, length = 5.3, height = 1.9 }
        entry.chassis = world:CreateVolumeFromModel(td, 0.1, origin)
        entry.chassis.material = world:GetPaletteMaterial()
        entry.chassis.density = 180.0
        world:FinalizeVolumeAsDynamic(entry.chassis)
        entry.chassis:RebuildGeometry()
        entry.vehicle = entry.chassis:GetNode():CreateComponent("VoxelVehicle")
        local k, c, rest, r = 46000.0, 5600.0, 0.15, 0.45
        -- 轮位 = 抽取报告轮心(vox y 4..6/19..21 → z 0.5/2.0,两侧对称离边 0.5)。
        -- 曾手抄成 0.4/1.9(视觉表更错成 0.3/2.0),后视图左轮外凸 0.2m(用户抓获)
        entry.vehicle:AddWheel(Vector3(4.3, 0.18, 0.5), r, rest, k, c, true, false)
        entry.vehicle:AddWheel(Vector3(4.3, 0.18, 2.0), r, rest, k, c, true, false)
        entry.vehicle:AddWheel(Vector3(1.1, 0.18, 0.5), r, rest, k, c, false, true)
        entry.vehicle:AddWheel(Vector3(1.1, 0.18, 2.0), r, rest, k, c, false, true)
        entry.vehicle.maxDriveForce = 9000.0
        entry.vehicle:SetMaxSpeed(14.0)   -- ~50km/h,小镇街道合理极速
        entry.vehicle.maxSteerAngle = 32.0
        entry.vehicle.grip = 0.85
        entry.vehicle:ApplyAttributes()
        -- 视觉轮位对齐原版站姿:实测挡泥板本体宽 y3..21(画布 25 的最宽处是
        -- 后视镜,别拿它当车宽),原版轮外面与挡泥板面近齐平 → 轮心 0.4/2.1
        -- (轮厚 0.2,外面正落在挡泥板面 0.3/2.2)。物理锚点独立,留在轮窝
        -- 中心 0.5/2.0(悬挂射线要走窝内空腔)
        AddVisualWheels(entry, {
            Vector3(4.3, 0.0, 0.4), Vector3(4.3, 0.0, 2.1),
            Vector3(1.1, 0.0, 0.4), Vector3(1.1, 0.0, 2.1) }, r, 0.18, rest,
            "td_wheel.vox", 9, 2)
        AddHeadlight(entry, entry.chassis, Vector3(5.25, 0.75, 0.65))
        AddHeadlight(entry, entry.chassis, Vector3(5.25, 0.75, 1.85))
        return entry
    end

    local entry = { name = "皮卡", wheels = {}, length = 4.6 }
    local model = cache:GetResource("VoxelModel", "Models/VoxPickup.vox")
    entry.chassis = world:CreateVolumeFromModel(model, 0.1, origin)
    entry.chassis.material = world:GetPaletteMaterial()
    entry.chassis.density = 180.0
    world:FinalizeVolumeAsDynamic(entry.chassis)
    entry.chassis:RebuildGeometry()

    entry.vehicle = entry.chassis:GetNode():CreateComponent("VoxelVehicle")
    local k, c, rest, r = 30000.0, 3600.0, 0.15, 0.38
    entry.vehicle:AddWheel(Vector3(3.8, 0.18, 0.25), r, rest, k, c, true, false)
    entry.vehicle:AddWheel(Vector3(3.8, 0.18, 1.75), r, rest, k, c, true, false)
    entry.vehicle:AddWheel(Vector3(0.7, 0.18, 0.25), r, rest, k, c, false, true)
    entry.vehicle:AddWheel(Vector3(0.7, 0.18, 1.75), r, rest, k, c, false, true)
    entry.vehicle.maxDriveForce = 6500.0
    entry.vehicle.maxSteerAngle = 32.0
    entry.vehicle.grip = 0.85
    entry.vehicle:ApplyAttributes()
    AddVisualWheels(entry, {
        Vector3(3.8, 0.0, 0.16), Vector3(3.8, 0.0, 1.84),
        Vector3(0.7, 0.0, 0.16), Vector3(0.7, 0.0, 1.84) }, r, 0.18, rest)
    AddHeadlight(entry, entry.chassis, Vector3(4.62, 0.62, 0.5))
    AddHeadlight(entry, entry.chassis, Vector3(4.62, 0.62, 1.5))
    return entry
end

local function BuildBulldozer(origin)
    local td = TeardownModel("td_dozer.vox")
    if td ~= nil then
        -- Teardown frontloader:91×29×35 vox @0.08 → 7.3 长 × 2.3 宽 × 2.8 高,
        -- 铲臂/铲斗冻结进车身(推土玩法靠车体推撞,不需要臂关节)
        local entry = { name = "推土机", wheels = {}, length = 7.3, height = 3.1 }
        entry.chassis = world:CreateVolumeFromModel(td, 0.08, origin)
        entry.chassis.material = world:GetPaletteMaterial()
        -- 质心下移+略前移,只为防翘头(曾实测全油门 max pitch 20 度;
        -- 后移-0.6 治转向立刻翘回 32.8 度——质心一个旋钮治不了两个反向的病)。
        -- 转向权不靠质心:根因是引擎驱动力施力高度,已在引擎侧修复(见下方墓碑)
        entry.chassis:SetComOffset(Vector3(0.35, -0.45, 0.0))
        entry.chassis.density = 280.0
        world:FinalizeVolumeAsDynamic(entry.chassis)
        entry.chassis:RebuildGeometry()
        entry.vehicle = entry.chassis:GetNode():CreateComponent("VoxelVehicle")
        -- 铲斗刃在 y=0(车底),静止轮底要压到 -0.12 以下抬起铲斗,否则铲刃拖地栽头
        local k, c, rest, r = 110000.0, 16000.0, 0.35, 0.6
        entry.vehicle:AddWheel(Vector3(4.96, 0.75, 0.16), r, rest, k, c, true, true)
        entry.vehicle:AddWheel(Vector3(4.96, 0.75, 2.16), r, rest, k, c, true, true)
        entry.vehicle:AddWheel(Vector3(1.52, 0.75, 0.16), r, rest, k, c, false, true)
        entry.vehicle:AddWheel(Vector3(1.52, 0.75, 2.16), r, rest, k, c, false, true)
        -- 26000 是起步翘头的元凶之一(0.7 倍的倒车就没事);14000 仍够推箱撞墙
        entry.vehicle.maxDriveForce = 14000.0
        -- 装载机 ~25km/h 到顶:无极速时按住 W 飙到 20m/s+,那个动量下任何
        -- 转向都是必然侧滑("还是会飘"的根因,舵角衰减救不了动量)
        entry.vehicle:SetMaxSpeed(7.0)
        entry.vehicle.maxSteerAngle = 24.0
        entry.vehicle.grip = 0.95
        -- 后轴不反向舵。曾为治转向不足加过 -0.5(铰接转向等效),但根因
        -- 其实是驱动力在地面高度卸载前轴(引擎已改为质心高度施力,转入
        -- 实测 70 度/2秒);而后轮驱动力沿反向舵方向满推力输出,恰好死保
        -- 旧转向——全油门反打实测过冲 59 度且 4 秒回不了头(用户抓获),
        -- 去掉后过冲 10 度、4 秒回摆 174 度。勿回加。
        entry.vehicle:ApplyAttributes()
        AddVisualWheels(entry, {
            Vector3(4.96, 0.0, 0.1), Vector3(4.96, 0.0, 2.25),
            Vector3(1.52, 0.0, 0.1), Vector3(1.52, 0.0, 2.25) }, r, 0.75, rest,
            "td_wheel_dozer.vox", 15, 4)
        AddHeadlight(entry, entry.chassis, Vector3(7.2, 1.9, 0.6))
        AddHeadlight(entry, entry.chassis, Vector3(7.2, 1.9, 1.7))
        return entry
    end

    local entry = { name = "推土机", wheels = {}, length = 5.4 }
    local v = 0.1
    local volume = world:CreateVolume(54, 14, 30, v, origin, Quaternion())
    local g = volume:GetGrid()
    g:FillBox(0, 0, 2, 44, 13, 27, true)
    g:FillBox(0, 8, 2, 15, 13, 27, false)
    g:FillBox(45, 4, 10, 47, 9, 19, true)
    g:FillBox(48, 0, 0, 53, 12, 29, true)
    g:PaintBox(0, 0, 0, 47, 100000, 100000, config.MAT_DOZER)
    g:PaintBox(45, 0, 0, 100000, 100000, 100000, config.MAT_BLADE)
    volume.material = world:GetPaletteMaterial()
    volume.density = 280.0
    world:FinalizeVolumeAsDynamic(volume)
    volume:RebuildGeometry()
    entry.chassis = volume

    entry.vehicle = volume:GetNode():CreateComponent("VoxelVehicle")
    local k, c, rest, r = 60000.0, 9000.0, 0.16, 0.35
    for _, x in ipairs({ 0.5, 2.25, 4.0 }) do
        entry.vehicle:AddWheel(Vector3(x, -0.02, 0.5), r, rest, k, c, x > 3.0, true)
        entry.vehicle:AddWheel(Vector3(x, -0.02, 2.5), r, rest, k, c, x > 3.0, true)
    end
    entry.vehicle.maxDriveForce = 18000.0
    entry.vehicle.maxSteerAngle = 18.0
    entry.vehicle.grip = 0.95
    entry.vehicle:ApplyAttributes()
    AddVisualWheels(entry, {
        Vector3(0.5, 0.0, 0.35), Vector3(0.5, 0.0, 2.65),
        Vector3(2.25, 0.0, 0.35), Vector3(2.25, 0.0, 2.65),
        Vector3(4.0, 0.0, 0.35), Vector3(4.0, 0.0, 2.65) }, r, -0.02, rest)
    -- 顶置灯排:铲刀在车头下方挡光,灯装机舱顶越过铲刀照路
    AddHeadlight(entry, entry.chassis, Vector3(4.45, 1.25, 0.8))
    AddHeadlight(entry, entry.chassis, Vector3(4.45, 1.25, 2.2))
    return entry
end

local function BuildExcavator(origin)
    local entry = { name = "挖掘机", wheels = {}, length = 3.6, digTimer = 0.0 }
    local v = 0.1
    local group = 3

    local function MakePart(nx, ny, nz, offset, density, fill, comOffset)
        local volume = world:CreateVolume(nx, ny, nz, v, origin + offset, Quaternion())
        fill(volume:GetGrid())
        volume.material = world:GetPaletteMaterial()
        -- CoM 偏移须在 Finalize 前设置(引擎在建体时包 OffsetCenterOfMassShape)
        if comOffset ~= nil then volume:SetComOffset(comOffset) end
        volume.density = density
        world:FinalizeVolumeAsDynamic(volume)
        volume.collisionGroup = group
        volume:RebuildGeometry()
        return volume
    end

    entry.chassis = MakePart(36, 10, 26, Vector3(0.0, 0.0, 0.0), 400.0, function(g)
        g:FillBox(0, 0, 0, 35, 6, 6, true)
        g:FillBox(0, 0, 19, 35, 6, 25, true)
        g:FillBox(0, 5, 0, 1, 6, 6, false)
        g:FillBox(34, 5, 0, 35, 6, 6, false)
        g:FillBox(0, 5, 19, 1, 6, 25, false)
        g:FillBox(34, 5, 19, 35, 6, 25, false)
        g:FillBox(4, 4, 7, 31, 8, 18, true)
        for _, ax in ipairs({ 4, 16, 28 }) do
            g:FillBox(ax, 0, 1, ax + 3, 4, 5, false)
            g:FillBox(ax, 0, 20, ax + 3, 4, 24, false)
        end
        for x = 1, 34, 2 do
            g:FillBox(x, 0, 0, x, 0, 6, false)
            g:FillBox(x, 0, 19, x, 0, 25, false)
        end
        g:PaintBox(0, 0, 0, 100000, 100000, 100000, config.MAT_TRACK)
    end)
    -- 驾驶舱带尾部配重(真挖掘机同款):动臂+斗杆悬伸车头 2.6m,不配重则前排
    -- 悬挂多压出可见前倾,且倾斜车身的悬挂力产生水平分量推着整机蠕行
    entry.cab = MakePart(24, 12, 22, Vector3(0.6, 0.95, 0.2), 250.0, function(g)
        g:FillBox(0, 0, 0, 23, 7, 21, true)
        g:FillBox(0, 8, 4, 9, 10, 17, true)
        g:FillBox(16, 8, 14, 23, 11, 21, true)
        g:FillBox(17, 9, 15, 23, 11, 20, false)
        g:PaintBox(0, 0, 0, 100000, 100000, 100000, config.MAT_EXCAVATOR)
        g:PaintBox(0, 0, 0, 3, 100000, 100000, config.MAT_BLADE)
        g:PaintBox(16, 8, 14, 100000, 100000, 100000, config.MAT_CAB)
        g:PaintBox(2, 10, 6, 7, 10, 15, config.MAT_CAB)
    end, Vector3(-0.2, -0.4, 0.0))
    entry.boom = MakePart(32, 14, 6, Vector3(3.0, 1.15, 1.0), 250.0, function(g)
        g:FillBox(0, 0, 0, 11, 5, 5, true)
        g:FillBox(8, 3, 0, 21, 8, 5, true)
        g:FillBox(18, 6, 0, 31, 11, 5, true)
        g:PaintBox(0, 0, 0, 100000, 100000, 100000, config.MAT_EXCAVATOR)
    end)
    entry.stick = MakePart(20, 10, 6, Vector3(6.0, 1.15, 1.0), 250.0, function(g)
        g:FillBox(0, 7, 1, 19, 9, 4, true)
        g:FillBox(13, 0, 0, 19, 7, 5, true)
        g:FillBox(13, 2, 1, 17, 7, 4, false)
        for z = 1, 5, 2 do
            g:FillBox(13, 0, z, 13, 0, z, false)
        end
        g:PaintBox(0, 7, 0, 100000, 100000, 100000, config.MAT_EXCAVATOR)
        g:PaintBox(13, 0, 0, 100000, 6, 100000, config.MAT_BLADE)
    end)

    entry.vehicle = entry.chassis:GetNode():CreateComponent("VoxelVehicle")
    -- 行程 0.12 太紧:重心稍偏一头就砸穿到底、肚皮着地(实测后轴 0.117/前轴
    -- 0.006 跷跷板),履带蹭地把偏航锚死——"转向很困难"的元凶。放宽行程、
    -- 让中载荷落在半行程,两端各留吸收余量
    local k, c, rest, r = 70000.0, 12000.0, 0.22, 0.18
    -- 锚点抬到 0.25(仍在轮窝内):行程不变,可视底架落到贴地 ~0.07m
    -- (0.15 时整个履带底架悬浮 0.24m,像磁悬浮——藏轮设计底架即视觉)
    for _, x in ipairs({ 0.55, 1.75, 2.95 }) do
        entry.vehicle:AddWheel(Vector3(x, 0.25, 0.35), r, rest, k, c, false, true)
        entry.vehicle:AddWheel(Vector3(x, 0.25, 2.25), r, rest, k, c, false, true)
    end
    -- 六轮全驱,20000/轮的推力会让它起步后仰立起(与装载机同款翘头病);
    -- 履带机本就该慢,8000 仍有 0.5g 级牵引
    entry.vehicle.maxDriveForce = 8000.0
    entry.vehicle:SetMaxSpeed(4.0)        -- 挖掘机 ~14km/h
    entry.vehicle.grip = 1.0
    entry.vehicle:SetSkidSteer(true)
    entry.vehicle:ApplyAttributes()

    entry.arms = {
        cab = AttachHinged(entry.cab, entry.chassis,
            Vector3(1.2, -0.03, 1.1), Vector3(0.0, 1.0, 0.0), 15000.0),
        boom = AttachHinged(entry.boom, entry.cab,
            Vector3(0.1, 0.25, 0.3), Vector3(0.0, 0.0, 1.0), 60000.0, -74.4845, 28.6479),
        stick = AttachHinged(entry.stick, entry.boom,
            Vector3(0.1, 0.85, 0.3), Vector3(0.0, 0.0, 1.0), 25000.0, -34.3775, 80.2141),
    }
    -- 大灯挂驾驶舱:Q/E 转舱时灯随舱转,照向作业面
    AddHeadlight(entry, entry.cab, Vector3(2.45, 0.85, 0.5))
    AddHeadlight(entry, entry.cab, Vector3(2.45, 0.85, 1.7))
    return entry
end

-- 小艇:平底木壳,volume:ApplyForce 桨推 + 船尾舵(引擎浮力托底,推进纯脚本)。
local function BuildDinghy(origin)
    local td = TeardownModel("td_dinghy.vox")
    if td ~= nil then
        -- Teardown smallboat:52×23×16 vox @0.1 → 5.2 长 × 2.3 宽;质量 ~0.9t
        local entry = { name = "小艇", isBoat = true, wheels = {}, length = 5.2, width = 2.3,
            height = 1.9, power = 10000.0, rudder = 3600.0, rollStab = 70000.0, rollDamp = 16000.0 }
        local volume = world:CreateVolumeFromModel(td, 0.1, origin)
        volume.material = world:GetPaletteMaterial()
        volume.comOffset = Vector3(0.0, -0.5, 0.0)   -- 龙骨:质心压到船底,被动扶正
        volume.density = 320.0
        world:FinalizeVolumeAsDynamic(volume)
        volume.buoyancy = 2.4
        volume:RebuildGeometry()
        entry.chassis = volume
        AddHeadlight(entry, volume, Vector3(5.1, 0.9, 1.15))
        return entry
    end

    -- power 实测:2600N 极速仅 3.95 m/s(Jolt 水阻线性,极速∝推力),翻倍到 ~8 m/s
    -- width 供尾迹锚点用:VoxelVolume node 原点在网格角,不是船体中心
    local entry = { name = "小艇", isBoat = true, wheels = {}, length = 3.0, width = 1.4,
        power = 5600.0, rudder = 1900.0 }
    local v = 0.1
    local volume = world:CreateVolume(30, 8, 14, v, origin, Quaternion())
    local g = volume:GetGrid()
    g:FillBox(0, 0, 0, 29, 1, 13, true)          -- 平底
    g:FillBox(0, 2, 0, 27, 5, 1, true)           -- 左舷
    g:FillBox(0, 2, 12, 27, 5, 13, true)         -- 右舷
    g:FillBox(0, 2, 0, 1, 5, 13, true)           -- 尾板
    g:FillBox(26, 2, 1, 29, 5, 12, true)         -- 船头
    g:FillBox(28, 3, 4, 29, 6, 9, true)          -- 头尖上翘
    g:PaintBox(0, 0, 0, 100000, 100000, 100000, config.MAT_WOOD)
    volume.material = world:GetPaletteMaterial()
    volume.density = 320.0
    world:FinalizeVolumeAsDynamic(volume)
    volume.buoyancy = 2.4        -- 密封壳的排水量,比"按实心木头算"更托底
    volume:RebuildGeometry()
    entry.chassis = volume
    AddHeadlight(entry, volume, Vector3(2.95, 0.5, 0.65))   -- 船头灯
    return entry
end

-- 大游艇:双层船体 + 舱室。记录出生体素数,船体被打烂后浮力随完好度衰减
-- ——破舱进水下沉的玩法机制(vehicles.UpdateAll 每帧驱动)。
local function BuildYacht(origin)
    local td = TeardownModel("td_yacht.vox")
    if td ~= nil then
        -- Teardown yacht_small:256×61×74 vox @0.07 → 17.9 长 × 4.3 宽;质量 ~20t
        local entry = { name = "游艇", isBoat = true, wheels = {}, length = 17.9, width = 4.3,
            height = 5.5, power = 90000.0, rudder = 34000.0, baseBuoyancy = 2.6,
            rollStab = 2600000.0, rollDamp = 900000.0 }
        local volume = world:CreateVolumeFromModel(td, 0.07, origin)
        volume.material = world:GetPaletteMaterial()
        volume.comOffset = Vector3(0.0, -2.2, 0.0)   -- 龙骨:质心压到船底之下,被动扶正
        volume.density = 380.0
        world:FinalizeVolumeAsDynamic(volume)
        volume.buoyancy = entry.baseBuoyancy
        volume:RebuildGeometry()
        entry.chassis = volume
        entry.originalSolid = volume:GetGrid().solidCount
        AddHeadlight(entry, volume, Vector3(17.6, 2.6, 1.6))
        AddHeadlight(entry, volume, Vector3(17.6, 2.6, 2.7))
        return entry
    end

    local entry = { name = "游艇", isBoat = true, wheels = {}, length = 7.7, width = 2.64,
        power = 30000.0, rudder = 11000.0, baseBuoyancy = 2.6 }
    local v = 0.12
    local volume = world:CreateVolume(64, 18, 22, v, origin, Quaternion())
    local g = volume:GetGrid()
    g:FillBox(0, 0, 1, 63, 2, 20, true)          -- 船底
    g:FillBox(0, 2, 0, 60, 7, 2, true)           -- 左舷
    g:FillBox(0, 2, 19, 60, 7, 21, true)         -- 右舷
    g:FillBox(0, 2, 0, 2, 7, 21, true)           -- 尾板
    g:FillBox(56, 2, 2, 63, 8, 19, true)         -- 船头楔
    g:FillBox(0, 7, 1, 60, 8, 20, true)          -- 主甲板
    g:FillBox(14, 9, 4, 44, 15, 17, true)        -- 舱室
    g:FillBox(16, 11, 4, 42, 13, 17, false)      -- 舱室开窗带
    g:FillBox(18, 9, 6, 40, 15, 15, false)       -- 舱内掏空
    g:PaintBox(0, 0, 0, 100000, 8, 100000, config.MAT_WOOD)
    g:PaintBox(0, 9, 0, 100000, 100000, 100000, config.MAT_EXCAVATOR)  -- 白舱涂装用亮色
    volume.material = world:GetPaletteMaterial()
    volume.density = 380.0
    world:FinalizeVolumeAsDynamic(volume)
    volume.buoyancy = entry.baseBuoyancy
    volume:RebuildGeometry()
    entry.chassis = volume
    entry.originalSolid = volume:GetGrid().solidCount
    AddHeadlight(entry, volume, Vector3(7.5, 1.1, 0.9))
    AddHeadlight(entry, volume, Vector3(7.5, 1.1, 1.7))
    return entry
end

-- ====================================================================
-- 空中载具:机体=动态体积,飞行力走引擎速度/力 API(阻尼/重力系数/CCD
-- 见 recipes/voxel-physics.md「空中载具」)。模型手绘:Teardown 官方
-- 资产无飞行器,沿用挖掘机部件的 FillBox 路线。机头一律 +X。
-- ====================================================================

-- 几何中心(近似质心)世界坐标:飞行力施加点。角点施力白送力矩
-- ——引擎载具"驱动力抬到质心高度"同一堂课。
local function AircraftCenter(entry)
    return entry.chassis:GetNode().worldTransform * entry.centerLocal
end

-- 自动驾驶注入:M.autopilot = { [KEY_W]=true, ... } 时替代真实键盘。
-- 无人值守探针/基准测试用(键盘事件无法脚本合成)。
local function KeyDown(key)
    if M.autopilot ~= nil then return M.autopilot[key] == true end
    return input:GetKeyDown(key)
end

local function FinishAircraft(entry, volume, density)
    volume.material = world:GetPaletteMaterial()
    volume.density = density
    world:FinalizeVolumeAsDynamic(volume)
    volume:RebuildGeometry()
    entry.chassis = volume
    entry.mass = density * volume:GetGrid().solidCount * volume:GetVoxelSize() ^ 3
end

local function BuildHelicopter(origin)
    local entry = { name = "直升机", isAircraft = true, kind = "heli", wheels = {},
        length = 6.4, width = 1.6, height = 2.4,
        cruise = 14.0, climb = 6.0, servoGain = 3.0,
        yawTorque = 9000.0, uprightTorque = 24000.0,
        centerLocal = Vector3(3.2, 0.8, 0.8) }
    local v = 0.1
    local volume = world:CreateVolume(64, 24, 16, v, origin, Quaternion())
    local g = volume:GetGrid()
    g:FillBox(24, 6, 3, 46, 14, 12, true)         -- 座舱
    g:FillBox(46, 7, 4, 52, 13, 11, true)         -- 机头
    g:FillBox(52, 8, 5, 55, 12, 10, true)         -- 头锥
    g:FillBox(6, 9, 6, 24, 12, 9, true)           -- 尾梁
    g:FillBox(3, 9, 7, 9, 21, 8, true)            -- 垂尾
    g:FillBox(33, 14, 6, 37, 16, 9, true)         -- 旋翼桅
    g:FillBox(22, 0, 1, 50, 1, 2, true)           -- 左滑橇
    g:FillBox(22, 0, 13, 50, 1, 14, true)         -- 右滑橇
    g:FillBox(27, 1, 1, 29, 6, 2, true)           -- 撑杆 ×4
    g:FillBox(42, 1, 1, 44, 6, 2, true)
    g:FillBox(27, 1, 13, 29, 6, 14, true)
    g:FillBox(42, 1, 13, 44, 6, 14, true)
    g:PaintBox(0, 0, 0, 100000, 100000, 100000, config.MAT_AIRFRAME)
    g:PaintBox(24, 8, 3, 40, 10, 12, config.MAT_AIRACCENT)   -- 红腰带
    g:PaintBox(3, 9, 7, 9, 21, 8, config.MAT_AIRACCENT)      -- 红垂尾
    g:PaintBox(46, 9, 4, 55, 13, 11, config.MAT_CANOPY)      -- 风挡
    g:PaintBox(22, 0, 1, 50, 5, 14, config.MAT_CAB)          -- 深色滑橇
    volume.comOffset = Vector3(0.0, -0.25, 0.0)   -- 压低重心,悬停摆动小
    volume.angularDamping = 2.5                   -- 姿态稳定的主力
    volume.linearDamping = 0.25
    FinishAircraft(entry, volume, 260.0)

    -- 旋翼:纯视觉体积(不 Finalize、无物理体——同视觉轮模式),桅顶悬转
    local hub = volume:GetNode():CreateChild("RotorHub")
    hub.temporary = true
    hub.position = Vector3(3.5, 1.72, 0.75)
    local rotor = world:CreateVolume(88, 2, 88, v, Vector3.ZERO, Quaternion())
    local rg = rotor:GetGrid()
    rg:FillBox(0, 0, 42, 87, 0, 45, true)         -- 主桨叶对(沿 X)
    rg:FillBox(42, 0, 0, 45, 0, 87, true)         -- 交叉桨叶对(沿 Z)
    rg:FillBox(40, 0, 40, 47, 1, 47, true)        -- 桨毂
    rg:PaintBox(0, 0, 0, 100000, 100000, 100000, config.MAT_CAB)
    rotor.material = world:GetPaletteMaterial()
    rotor:RebuildGeometry()
    local rotorNode = rotor:GetNode()
    rotorNode.temporary = true
    rotorNode:SetParent(hub)
    rotorNode.position = Vector3(-4.4, 0.0, -4.4)
    entry.rotorHub = hub
    entry.rotorSpin = 0.0
    entry.rotorRate = 0.0

    AddHeadlight(entry, volume, Vector3(5.5, 0.9, 0.75))
    return entry
end

-- Assembly 直升机:固定结构由多个独立 VoxelVolume 共用一个刚体;主旋翼必须
-- 保持为第二个动态体并通过 VoxelConstraint 连接,否则加入机身 Assembly 后将无法
-- 相对旋转。升力仍作用于机身 Assembly,旋翼马达只负责真实的相对转动。
local function BuildAssemblyHelicopter(origin)
    local entry = { name = "Assembly 直升机", isAircraft = true, kind = "heli", wheels = {},
        length = 6.2, width = 1.9, height = 3.0, isAssemblyHelicopter = true,
        initialMembers = 7, detachedCount = 0, partNames = {},
        lastAssemblyMessage = "机身 Assembly 就绪,主旋翼为独立铰链刚体",
        cruise = 13.0, climb = 5.5, servoGain = 3.0,
        yawTorque = 18000.0, uprightTorque = 45000.0,
        centerLocal = Vector3(3.6, 0.8, 0.9), rotorMotorTorque = 8000.0 }
    local v = 0.1

    local function MakePart(name, nx, ny, nz, offset, density, material, fill)
        local volume = world:CreateVolume(nx, ny, nz, v, origin + offset, Quaternion())
        volume:GetNode().name = name
        fill(volume:GetGrid())
        volume:GetGrid():PaintBox(0, 0, 0, 100000, 100000, 100000, material)
        volume.material = world:GetPaletteMaterial()
        volume.density = density
        world:FinalizeVolumeAsDynamic(volume)
        volume:RebuildGeometry()
        entry.partNames[volume:GetNode().ID] = name
        return volume
    end

    -- 根只定义稳定玩法坐标系;质量由所有 member 的 density × solid volume 汇总。
    -- 根 grid 保留完整 6.2m 玩法坐标系,实心机身只占前段;这样进入检测、
    -- 相机和施力点都继续以整机尾角为 Node 原点,不随 COM 或成员变化漂移。
    entry.chassis = MakePart("AssemblyHeliFuselage", 62, 10, 18,
        Vector3(0.0, 0.55, 0.0), 260.0, config.MAT_ASSEMBLY_BODY, function(g)
            g:FillBox(22, 0, 1, 59, 8, 16, true)
            g:FillBox(53, 2, 0, 59, 7, 17, true) -- 加宽机鼻
        end)
    entry.chassis.comOffset = Vector3(0.0, -0.18, 0.0)

    entry.canopy = MakePart("AssemblyHeliCanopy", 20, 10, 16,
        Vector3(4.0, 1.45, 0.1), 90.0, config.MAT_CANOPY, function(g)
            g:FillBox(0, 0, 1, 18, 6, 14, true)
            g:FillBox(2, 7, 3, 14, 8, 12, true)
        end)
    entry.canopy:SetCollisionBox(Vector3(1.9, 0.9, 1.4), Vector3(0.0, 0.0, 0.0))

    entry.tailBoom = MakePart("AssemblyHeliTailBoom", 23, 7, 8,
        Vector3(0.3, 1.05, 0.5), 130.0, config.MAT_ASSEMBLY_PANEL, function(g)
            g:FillBox(0, 2, 2, 22, 5, 5, true)
            g:FillBox(17, 1, 1, 22, 6, 6, true)
        end)
    entry.tailFin = MakePart("AssemblyHeliTailFin", 8, 15, 4,
        Vector3(0.0, 1.35, 0.7), 110.0, config.MAT_AIRACCENT, function(g)
            g:FillBox(0, 0, 0, 7, 13, 3, true)
            g:FillBox(0, 10, 0, 3, 14, 3, true)
        end)

    local function FillSkid(g)
        g:FillBox(0, 0, 0, 31, 1, 2, true)
        g:FillBox(5, 2, 0, 8, 6, 2, true)
        g:FillBox(24, 2, 0, 27, 6, 2, true)
    end
    entry.leftSkid = MakePart("AssemblyHeliLeftSkid", 32, 8, 3,
        Vector3(2.4, 0.12, 0.02), 360.0, config.MAT_CAB, FillSkid)
    entry.rightSkid = MakePart("AssemblyHeliRightSkid", 32, 8, 3,
        Vector3(2.4, 0.12, 1.68), 360.0, config.MAT_CAB, FillSkid)
    entry.leftSkid:SetCollisionBox(Vector3(3.2, 0.2, 0.3), Vector3(0.0, -0.25, 0.0))
    entry.rightSkid:SetCollisionBox(Vector3(3.2, 0.2, 0.3), Vector3(0.0, -0.25, 0.0))

    -- 齿轮箱从机身顶面长出，向上收窄成主轴；不可只在旋翼下放一根短杆，
    -- 否则侧视时它与机舱仅有极小重叠，会产生旋翼悬空的错觉。
    entry.mast = MakePart("AssemblyHeliRotorMast", 12, 15, 10,
        Vector3(3.1, 1.45, 0.4), 420.0, config.MAT_CAB, function(g)
            g:FillBox(0, 0, 0, 11, 5, 9, true)  -- 机身上的宽齿轮箱
            g:FillBox(2, 6, 2, 9, 9, 7, true)   -- 收窄的上部机匣
            g:FillBox(4, 10, 3, 7, 14, 6, true) -- 插入旋翼轮毂的主轴
        end)

    local assembly = world:CreateAssembly(entry.chassis)
    assert(assembly ~= nil, "VoxelTown: failed to create helicopter assembly")
    for _, member in ipairs({ entry.canopy, entry.tailBoom, entry.tailFin,
        entry.leftSkid, entry.rightSkid, entry.mast }) do
        assert(assembly:AddVolume(member), "VoxelTown: failed to add helicopter member")
    end
    entry.assembly = assembly

    -- 完整件阈值只由参数控制。正常飞行载荷远低于这些值;撞建筑或被打残后
    -- 实际命中的 member 会由 C++ 应力模型自动削弱并脱离。
    local breakSettings = {
        { entry.canopy, 600000.0, 400000.0 },
        { entry.tailBoom, 1200000.0, 900000.0 },
        { entry.tailFin, 500000.0, 350000.0 },
        -- 落地瞬间的单侧接触反力会远高于静态重量，滑橇必须留足冲击裕量。
        { entry.leftSkid, 2500000.0, 1500000.0 },
        { entry.rightSkid, 2500000.0, 1500000.0 },
        { entry.mast, 2000000.0, 1500000.0 },
    }
    for _, setting in ipairs(breakSettings) do
        assembly:SetMemberBreakThreshold(setting[1], setting[2], setting[3])
    end
    assembly.linearDamping = 0.25
    assembly.angularDamping = 2.7
    assembly.ccdEnabled = true

    -- 物理主旋翼:独立 body + 铰链马达。collisionMask=0 让高速桨叶不把停机坪
    -- 和机身求解炸飞,但体素仍可射线命中、涂色和破坏。
    local rotorCenter = origin + Vector3(3.7, 2.9, 0.9)
    local rotor = world:CreateVolume(76, 6, 76, v,
        rotorCenter - Vector3(3.8, 0.3, 3.8), Quaternion())
    rotor:GetNode().name = "AssemblyHeliMainRotor"
    local rg = rotor:GetGrid()
    rg:FillBox(0, 2, 36, 75, 3, 39, true)
    rg:FillBox(36, 2, 0, 39, 3, 75, true)
    -- 轮毂以铰链锚点为中心向下包住固定主轴；中心对称，因此旋转时接缝稳定。
    rg:FillBox(34, 0, 34, 41, 5, 41, true)
    rg:PaintBox(0, 0, 0, 100000, 100000, 100000, config.MAT_CAB)
    rotor.material = world:GetPaletteMaterial()
    rotor.gravityFactor = 0.0
    rotor.angularDamping = 0.02
    rotor.friction = 0.05
    rotor.collisionMask = 0
    rotor.density = 25.0
    world:FinalizeVolumeAsDynamic(rotor)
    rotor:RebuildGeometry()
    entry.mainRotor = rotor
    entry.rotorOriginalSolid = rotor:GetGrid().solidCount

    local rotorConstraint = rotor:GetNode():CreateComponent("VoxelConstraint")
    rotorConstraint.constraintType = VOXEL_CONSTRAINT_HINGE
    rotorConstraint.otherVolume = entry.mast
    rotorConstraint.worldPosition = rotorCenter
    rotorConstraint.rotation = Quaternion(Vector3.FORWARD, Vector3.UP)
    rotorConstraint.otherRotation = Quaternion(Vector3.FORWARD, Vector3.UP)
    rotorConstraint.disableCollision = true
    rotorConstraint:SetAngularMotorVelocity(0.0, entry.rotorMotorTorque)
    assert(rotorConstraint:Rebuild(), "VoxelTown: failed to build helicopter rotor hinge")
    entry.rotorConstraint = rotorConstraint
    entry.rotorRate = 0.0
    entry.rotorSpin = 0.0

    -- 尾旋翼保留为轻量视觉体积,并挂在可脱落的尾翼 Node 上。
    local tailHub = entry.tailFin:GetNode():CreateChild("AssemblyHeliTailRotorHub")
    tailHub.temporary = true
    tailHub.position = Vector3(0.25, 0.72, -0.04)
    local tailRotor = world:CreateVolume(16, 16, 1, 0.06, Vector3.ZERO, Quaternion())
    local trg = tailRotor:GetGrid()
    trg:FillBox(0, 7, 0, 15, 8, 0, true)
    trg:FillBox(7, 0, 0, 8, 15, 0, true)
    trg:PaintBox(0, 0, 0, 100000, 100000, 100000, config.MAT_CAB)
    tailRotor.material = world:GetPaletteMaterial()
    tailRotor:RebuildGeometry()
    tailRotor:GetNode().temporary = true
    tailRotor:GetNode():SetParent(tailHub)
    tailRotor:GetNode().position = Vector3(-0.48, -0.48, -0.03)
    entry.tailRotorHub = tailHub

    AddHeadlight(entry, entry.canopy, Vector3(1.85, 0.35, 0.7))
    assemblyHelicopter = entry
    return entry
end

local function BuildFighter(origin)
    local entry = { name = "战斗机", isAircraft = true, kind = "plane", wheels = {},
        length = 10.4, width = 7.2, height = 2.8,
        thrustAccel = 8.0, liftSpeed = 26.0, maxSpeed = 60.0,
        pitchTorque = 90000.0, yawTorque = 50000.0, rollHold = 70000.0,
        weathercock = 500000.0, bank = 0.7,       -- tan35°:g·tan≈6.9m/s² 向心
        centerLocal = Vector3(4.8, 1.2, 3.55) }
    local v = 0.1
    local volume = world:CreateVolume(104, 28, 72, v, origin, Quaternion())
    local g = volume:GetGrid()
    g:FillBox(8, 8, 32, 87, 16, 39, true)         -- 机身
    g:FillBox(87, 9, 33, 96, 15, 38, true)        -- 机头
    g:FillBox(96, 10, 34, 102, 13, 37, true)      -- 头锥
    g:FillBox(60, 16, 33, 76, 19, 38, true)       -- 座舱盖
    g:FillBox(18, 10, 4, 44, 11, 67, true)        -- 三角翼(阶梯后掠)
    g:FillBox(44, 10, 14, 56, 11, 57, true)
    g:FillBox(56, 10, 24, 66, 11, 47, true)
    g:FillBox(9, 16, 34, 24, 26, 37, true)        -- 垂尾
    g:FillBox(8, 11, 20, 20, 12, 51, true)        -- 平尾
    g:PaintBox(0, 0, 0, 100000, 100000, 100000, config.MAT_AIRFRAME)
    g:PaintBox(60, 16, 33, 76, 19, 38, config.MAT_CANOPY)
    g:PaintBox(9, 16, 34, 24, 26, 37, config.MAT_AIRACCENT)  -- 红垂尾
    g:PaintBox(87, 8, 32, 102, 16, 39, config.MAT_AIRACCENT) -- 红机头
    g:PaintBox(8, 8, 32, 14, 16, 39, config.MAT_CAB)         -- 深色喷口
    volume.angularDamping = 1.6
    volume.linearDamping = 0.05
    volume.ccdEnabled = true      -- 高速机体防穿薄墙(引擎 LinearCast)
    FinishAircraft(entry, volume, 300.0)

    -- 起落架:纯物理悬挂轮(无视觉轮——喷气机轮子小,收进轮舱的观感)
    entry.vehicle = volume:GetNode():CreateComponent("VoxelVehicle")
    local k, c, rest, r = 45000.0, 6000.0, 0.55, 0.28
    entry.vehicle:AddWheel(Vector3(8.6, 0.7, 3.55), r, rest, k, c, true, false)
    entry.vehicle:AddWheel(Vector3(3.4, 0.7, 2.8), r, rest, k, c, false, false)
    entry.vehicle:AddWheel(Vector3(3.4, 0.7, 4.3), r, rest, k, c, false, false)
    entry.vehicle.maxSteerAngle = 40.0
    -- 起落架自由滚动:默认滚阻 0.02/步(1.2/s)会把 27kN 推力按死在 6m/s
    -- (实测),飞机的轮子必须近乎零滚阻,刹车归 Park 的驻车刹
    entry.vehicle.rollingResistance = 0.002
    entry.vehicle:ApplyAttributes()
    -- 视觉轮:隐形物理轮撑着机腹悬空 1.3m,截图里像浮空(踩过)
    AddVisualWheels(entry, {
        Vector3(8.6, 0.7, 3.55),
        Vector3(3.4, 0.7, 2.8), Vector3(3.4, 0.7, 4.3) }, 0.28, 0.7, 0.55)

    AddHeadlight(entry, volume, Vector3(10.1, 1.1, 3.55))
    return entry
end

local function BuildAirliner(origin)
    local entry = { name = "客机", isAircraft = true, kind = "plane", wheels = {},
        length = 16.8, width = 13.8, height = 4.8,
        thrustAccel = 6.0, liftSpeed = 17.0, maxSpeed = 42.0,
        pitchTorque = 500000.0, yawTorque = 260000.0, rollHold = 420000.0,
        weathercock = 3000000.0, bank = 0.4,      -- tan22°:客机端庄些
        centerLocal = Vector3(7.8, 2.6, 6.9) }
    local v = 0.15
    local volume = world:CreateVolume(112, 32, 92, v, origin, Quaternion())
    local g = volume:GetGrid()
    g:FillBox(4, 13, 40, 103, 24, 52, true)       -- 机身管
    g:FillBox(4, 13, 40, 14, 16, 52, false)       -- 尾锥底部掏斜
    g:FillBox(103, 15, 42, 109, 22, 50, true)     -- 机头
    g:FillBox(48, 14, 4, 64, 16, 88, true)        -- 主翼
    g:FillBox(44, 14, 24, 68, 16, 68, true)       -- 翼根加厚段
    g:FillBox(52, 9, 14, 66, 14, 21, true)        -- 发动机吊舱 ×2
    g:FillBox(52, 9, 71, 66, 14, 78, true)
    g:FillBox(4, 24, 44, 20, 31, 48, true)        -- 垂尾
    g:FillBox(2, 22, 26, 16, 23, 66, true)        -- 平尾
    g:PaintBox(0, 0, 0, 100000, 100000, 100000, config.MAT_AIRFRAME)
    g:PaintBox(10, 21, 40, 100, 22, 52, config.MAT_CANOPY)   -- 舷窗带
    g:PaintBox(103, 17, 42, 109, 21, 50, config.MAT_CANOPY)  -- 驾驶舱风挡
    g:PaintBox(4, 24, 44, 20, 31, 48, config.MAT_AIRACCENT)  -- 红垂尾
    g:PaintBox(4, 13, 40, 30, 15, 52, config.MAT_AIRACCENT)  -- 红尾腰线
    g:PaintBox(52, 9, 14, 66, 14, 21, config.MAT_CAB)        -- 深色发动机
    g:PaintBox(52, 9, 71, 66, 14, 78, config.MAT_CAB)
    -- 起落架支柱(视觉):必须离轮子锚点的垂线两格以上——首版只偏一格,
    -- 主柱边界(体素 43 止于 6.60m)恰好压住主轮锚点 x=6.6,悬挂射线
    -- 自命中火箭起飞,整机弹飞出停机坪(铁律 1 的活教材)
    g:FillBox(91, 5, 45, 92, 12, 47, true)       -- 前轮柱
    g:FillBox(41, 6, 36, 42, 13, 38, true)       -- 左主柱
    g:FillBox(41, 6, 53, 42, 13, 55, true)       -- 右主柱
    g:PaintBox(91, 5, 45, 92, 12, 47, config.MAT_CAB)
    g:PaintBox(41, 6, 36, 42, 13, 38, config.MAT_CAB)
    g:PaintBox(41, 6, 53, 42, 13, 55, config.MAT_CAB)
    volume.angularDamping = 3.2
    volume.linearDamping = 0.1
    FinishAircraft(entry, volume, 220.0)

    entry.vehicle = volume:GetNode():CreateComponent("VoxelVehicle")
    -- 挂点要低到机身壳外(壳底 1.95),ray 才够得着地:初版 attachY 1.6 +
    -- 行程 0.9 + 轮 0.5 正好只到网格底,出生落体冲穿行程直接肚皮着地
    local k, c, rest, r = 240000.0, 30000.0, 0.7, 0.5
    -- 主轮必须在质心(x≈7.9)之后,否则停机是跷跷板、尾锥砸地入土半米,
    -- 滑跑变犁地(实测 84kN 推力被尾部摩擦吃到只剩 1.3m/s²)
    entry.vehicle:AddWheel(Vector3(14.2, 1.0, 6.9), r, rest, k, c, true, false)
    entry.vehicle:AddWheel(Vector3(6.6, 1.0, 5.6), r, rest, k, c, false, false)
    entry.vehicle:AddWheel(Vector3(6.6, 1.0, 8.2), r, rest, k, c, false, false)
    entry.vehicle:AddWheel(Vector3(1.8, 1.9, 6.9), r, rest, k, c, false, false) -- 尾撑(平时悬空)
    entry.vehicle.maxSteerAngle = 32.0
    entry.vehicle.rollingResistance = 0.002   -- 同战斗机:起落架自由滚动
    entry.vehicle:ApplyAttributes()
    -- 视觉轮(尾撑轮平时悬空,不给视觉)
    AddVisualWheels(entry, {
        Vector3(14.2, 1.0, 6.9),
        Vector3(6.6, 1.0, 5.6), Vector3(6.6, 1.0, 8.2) }, 0.5, 1.0, 0.7)

    AddHeadlight(entry, volume, Vector3(16.3, 2.4, 6.9))
    return entry
end

-- 直升机:重力前馈 + 速度伺服(悬停零输入即静止,不用玩家配平)。
-- W/S 沿机头水平进退,A/D 偏航,Space 升 / C 降。
local function DriveHelicopter(entry, timeStep)
    local vol = entry.chassis
    local body = entry.assembly or vol
    local rot = vol:GetNode().worldRotation
    local fwdIn = (KeyDown(KEY_W) and 1.0 or 0.0)
        - (KeyDown(KEY_S) and 1.0 or 0.0)
    local yawIn = (KeyDown(KEY_D) and 1.0 or 0.0)
        - (KeyDown(KEY_A) and 1.0 or 0.0)
    local upIn = (KeyDown(KEY_SPACE) and 1.0 or 0.0)
        - (KeyDown(KEY_C) and 1.0 or 0.0)

    body:Activate()
    if entry.rotorConstraint ~= nil then
        if entry.mainRotor ~= nil and entry.mainRotor:GetNode() ~= nil then
            -- 物理旋翼平滑起转;马达目标与视觉尾桨共用 degree/s 遥测。
            entry.rotorRate = math.min((entry.rotorRate or 0.0) + 720.0 * timeStep, 1080.0)
            entry.rotorConstraint:SetAngularMotorVelocity(
                entry.rotorRate, entry.rotorMotorTorque)
        else
            entry.rotorRate = 0.0
        end
    else
        entry.rotorRate = 1080.0
    end

    local fwd = rot * Vector3(1.0, 0.0, 0.0)
    fwd.y = 0.0
    if fwd:Length() > 0.01 then fwd = fwd:Normalized() end
    local desired = fwd * (fwdIn * entry.cruise)
    desired.y = upIn * entry.climb
    local mass = body:GetMass()
    local rotorPower = 1.0
    if entry.mainRotor ~= nil then
        rotorPower = 0.0
        if entry.mainRotor:GetNode() ~= nil and entry.rotorOriginalSolid > 0 then
            local integrity = entry.mainRotor:GetGrid().solidCount / entry.rotorOriginalSolid
            rotorPower = math.min(entry.rotorRate / 900.0, 1.0) * integrity
        end
    end
    local force = (Vector3(0.0, mass * 9.81, 0.0)
        + (desired - body:GetLinearVelocity()) * (mass * entry.servoGain)) * rotorPower
    body:ApplyForce(force, AircraftCenter(entry))

    -- 偏航 + 扶正(前进带一点低头,纯姿态视觉)
    body:ApplyTorque(Vector3(0.0, yawIn * entry.yawTorque, 0.0) * rotorPower)
    local bodyUp = rot * Vector3(0.0, 1.0, 0.0)
    local targetUp = (Vector3(0.0, 1.0, 0.0) - fwd * (0.18 * fwdIn)):Normalized()
    body:ApplyTorque(bodyUp:CrossProduct(targetUp) * (entry.uprightTorque * rotorPower))
    return true
end

-- 固定翼:W 推力(近极速线性归零)/S 反推刹车,A/D 偏航转向,
-- Space 拉杆 / C 推杆。升力 ∝ (空速/起飞速度)²——低于失速速度自然下沉,
-- 跑道上加速过 liftSpeed 再拉杆才飞得起来。
local function DrivePlane(entry, timeStep)
    local vol = entry.chassis
    local rot = vol:GetNode().worldRotation
    local thrIn = KeyDown(KEY_W) and 1.0 or 0.0
    local revIn = KeyDown(KEY_S) and 1.0 or 0.0
    local yawIn = (KeyDown(KEY_D) and 1.0 or 0.0)
        - (KeyDown(KEY_A) and 1.0 or 0.0)
    local pitchIn = (KeyDown(KEY_SPACE) and 1.0 or 0.0)
        - (KeyDown(KEY_C) and 1.0 or 0.0)
    vol:Activate()

    local fwd = rot * Vector3(1.0, 0.0, 0.0)
    local up = rot * Vector3(0.0, 1.0, 0.0)
    local vel = vol.linearVelocity
    local mass = vol:GetMass()
    local speed = vel:DotProduct(fwd)
    local center = AircraftCenter(entry)

    local fade = 1.0 - math.max(speed, 0.0) / entry.maxSpeed
    if fade < 0.0 then fade = 0.0 end
    local thrust = (thrIn * fade - revIn * 0.6) * mass * entry.thrustAccel
    if thrust ~= 0.0 then
        vol:ApplyForce(fwd * thrust, center)
    end

    local liftRatio = math.min(math.abs(speed) / entry.liftSpeed, 1.15)
    vol:ApplyForce(up * (mass * 9.81 * liftRatio * liftRatio), center)

    -- 操纵权随空速增长(地面慢速不至于原地抬头翻跟斗)。
    -- 压坡转弯:A/D 令机体滚转入坡,升力的水平分量画弧——真机的转法。
    -- 首版平转(纯偏航)实测转弯半径 ~870m:风向标把机头限制在 ~6° 侧滑,
    -- 横向力只剩推力·sin6°,体感"转不动"。坡度随空速平方渐入,滑行不压坡;
    -- 机头由风向标自动跟上弯转的速度矢量 = 协调转弯,不用额外偏航耦合
    local auth = 0.25 + 0.75 * math.min(math.max(speed, 0.0) / entry.liftSpeed, 1.0)
    local airRatio = math.min(math.max(speed, 0.0) / entry.liftSpeed, 1.0)
    local rightDir = rot * Vector3(0.0, 0.0, -1.0)   -- 面向 +X 时右手边 = -Z(实测约定)
    local targetUp = (Vector3(0.0, 1.0, 0.0)
        + rightDir * (yawIn * entry.bank * airRatio * airRatio)):Normalized()
    local rollAmount = up:CrossProduct(targetUp):DotProduct(fwd)
    local torque = (rot * Vector3(0.0, 0.0, 1.0)) * (pitchIn * entry.pitchTorque * auth)
        + Vector3(0.0, yawIn * entry.yawTorque * auth, 0.0)
        + fwd * (rollAmount * entry.rollHold)
    -- 风向标自稳:机头被拉向速度方向(真机的静稳定性)。没有它,满杆
    -- 俯仰角无限增长——探针实测 3 秒仰到 40 度翻筋斗。有了它,满杆
    -- = 有限攻角(pitchTorque/weathercock ≈ sin 上限),松杆自动回平
    local vlen = vel:Length()
    if vlen > 4.0 then
        local velDir = vel * (1.0 / vlen)
        vol:ApplyTorque(fwd:CrossProduct(velDir)
            * (entry.weathercock * math.min(vlen / entry.liftSpeed, 1.5)))
    end
    vol:ApplyTorque(torque)

    -- 地面滑行:前轮转向跟 A/D(起落架是真悬挂,刹车归 Park)
    if entry.vehicle ~= nil then
        entry.vehicle:SetInput(0.0, yawIn, 0.0)
    end
    return true
end

---@param entry table
---@param volume VoxelVolume
local function IsAttachedDemoMember(entry, volume)
    return volume ~= nil and volume:GetNode() ~= nil
        and volume:GetAssembly() == entry.assembly
end

function VoxelTownAssemblyMemberDetached(eventType, eventData)
    local assembly = eventData["Assembly"]:GetPtr("VoxelAssembly")
    local entry = nil
    if assemblyDemo ~= nil and assembly == assemblyDemo.assembly then
        entry = assemblyDemo
    elseif assemblyHelicopter ~= nil and assembly == assemblyHelicopter.assembly then
        entry = assemblyHelicopter
    end
    if entry == nil then return end
    local volume = eventData["Volume"]:GetPtr("VoxelVolume")
    if volume == nil or volume:GetNode() == nil then return end
    local factor = eventData["BreakFactor"]:GetFloat()
    local reason = eventData["Reason"]:GetString()
    local partName = entry.partNames[volume:GetNode().ID] or "未知成员"
    entry.detachedCount = entry.detachedCount + 1
    entry.lastAssemblyMessage = string.format(
        "%s 脱落(%s, %.1fx)", partName, reason, factor)
    print("[VoxelTown Assembly] " .. entry.lastAssemblyMessage)
end

-- B 键调用:通过 Assembly façade 直接设置共享 body 速度,提供无需先上车的
-- 确定性撞墙演示。已经脱落的 member 不会被重新吸回,可反复观察残车行为。
function M.LaunchAssemblyDemo()
    local entry = assemblyDemo
    if entry == nil or entry.assembly == nil or entry.chassis:GetNode() == nil then return false end
    local forward = entry.chassis:GetNode().worldRotation * Vector3(1.0, 0.0, 0.0)
    entry.vehicle:SetInput(0.0, 0.0, 0.0)
    entry.assembly:SetLinearVelocity(forward * 13.0)
    entry.assembly:SetAngularVelocity(Vector3.ZERO)
    entry.assembly:Activate()
    entry.lastAssemblyMessage = "Assembly façade 发射:13m/s,断裂由物理参数决定"
    return true
end

function M.GetAssemblyStatus()
    local entry = assemblyDemo
    if entry == nil or entry.assembly == nil then return nil end
    local memberCount = entry.assembly:GetVolumeCount()
    local stress = 0.0
    if IsAttachedDemoMember(entry, entry.frontBumper) then
        stress = entry.assembly:GetMemberStress(entry.frontBumper).breakFactor
    elseif IsAttachedDemoMember(entry, entry.leftDoor) then
        stress = entry.assembly:GetMemberStress(entry.leftDoor).breakFactor
    end
    return string.format("Assembly 解体车: %d/%d members  mass %.0fkg  stress %.2fx | %s",
        memberCount, entry.initialMembers, entry.assembly:GetMass(), stress,
        entry.lastAssemblyMessage)
end

function M.GetAssemblyHelicopterStatus(entry)
    if entry == nil or entry ~= assemblyHelicopter or entry.assembly == nil then return nil end
    local rotorIntegrity = 0.0
    if entry.mainRotor ~= nil and entry.mainRotor:GetNode() ~= nil
        and entry.rotorOriginalSolid > 0 then
        rotorIntegrity = entry.mainRotor:GetGrid().solidCount / entry.rotorOriginalSolid
    end
    return string.format("Assembly %d/%d members  mass %.0fkg  rotor %.0f%% @ %.0fdeg/s | %s",
        entry.assembly:GetVolumeCount(), entry.initialMembers, entry.assembly:GetMass(),
        rotorIntegrity * 100.0, entry.rotorRate or 0.0, entry.lastAssemblyMessage)
end

function M.SpawnAll(worldRef)
    world = worldRef
    if not assemblyEventsSubscribed then
        -- 事件只更新演示 HUD，不参与断裂判定；断裂完全由 Assembly 参数驱动。
        SubscribeToEvent("VoxelAssemblyMemberDetached", "VoxelTownAssemblyMemberDetached")
        assemblyEventsSubscribed = true
    end
    -- 陆地载具沿西街 z=1 排成一列(车头朝东),出生点离建筑/停车道具留足空档
    -- ——大车身与道具重叠会出生弹射(踩过:装载机骑上路边橙车)
    table.insert(M.list, BuildAssemblyCar(Vector3(-8.0, 0.55, 1.0)))
    table.insert(M.list, BuildPickup(Vector3(-18.0, 0.5, 1.0)))
    table.insert(M.list, BuildBulldozer(Vector3(-28.0, 0.6, 1.0)))
    table.insert(M.list, BuildExcavator(Vector3(-38.0, 0.5, 1.0)))
    table.insert(M.list, BuildRollingContactCar(Vector3(-48.0, 0.0, 1.0)))
    table.insert(M.list, BuildDinghy(Vector3(40.0, 0.4, 10.0)))      -- 栈桥边
    table.insert(M.list, BuildYacht(Vector3(52.0, 0.6, 18.0)))       -- 湾心
    -- 南缘草地机场,跑道朝东(+X)。首版摆在 z=-38/-18,起飞滑跑一头撞进
    -- house6(-48,-34)和 tree2(-48,-20)——出生点无重叠≠跑道走廊无遮挡,
    -- 走廊已整体登记进 town_layout_check.py 的 EXTRA_BOXES 防回归
    table.insert(M.list, BuildAirliner(Vector3(-84.0, 0.5, -74.0)))
    table.insert(M.list, BuildFighter(Vector3(-84.0, 0.35, -58.0)))
    table.insert(M.list, BuildAssemblyHelicopter(Vector3(-72.0, 0.3, -46.0)))
    table.insert(M.list, BuildHelicopter(Vector3(-58.0, 0.3, -46.0)))
    -- 出生即拉驻车刹车(理由见 Park)
    for _, entry in ipairs(M.list) do
        if not entry.isBoat and entry.vehicle ~= nil then
            entry.vehicle:SetInput(0.0, 0.0, 1.0)
        end
    end
end

-- 轮子视觉:悬挂行程跟随 + 地速旋转。对**所有**陆地载具每帧执行,不只驾驶中
-- ——建车时 hub 摆在锚点位(attachY),正确停放位是 attachY-(rest-compression);
-- 该同步曾只写在 Drive 里,没开过的车轮子便以建车姿势沉在路面下(用户抓获:
-- "驾驶过一次就正常了")。停放车辆的压缩量照样可查(悬挂每步都在跑)。
local function UpdateWheelVisuals(entry, timeStep)
    if entry.vehicle == nil or entry.wheels == nil then return end
    local speed = entry.vehicle.forwardSpeed
    for _, wheel in ipairs(entry.wheels) do
        if wheel.node ~= nil then
            wheel.spin = wheel.spin + speed / wheel.radius * timeStep * 57.2958
            local compression = entry.vehicle:GetWheelCompression(wheel.index)
            wheel.node.position = Vector3(wheel.x,
                wheel.attachY - (wheel.rest - compression), wheel.z)
            wheel.node.rotation = Quaternion(0.0, 0.0, -wheel.spin)
        end
    end
end

-- 每帧杂务(main 调用):轮子视觉同步 + 游艇船体完好度 → 浮力衰减(破舱进水)
function M.UpdateAll(timeStep)
    for _, entry in ipairs(M.list) do
        if not entry.isBoat then UpdateWheelVisuals(entry, timeStep) end
        -- 旋翼:单体直升机驱动视觉主桨;Assembly 直升机的真实主桨由铰链
        -- 马达驱动,这里仅同步尾桨并保存转速表现。
        if entry.rotorHub ~= nil or entry.tailRotorHub ~= nil then
            entry.rotorRate = math.max((entry.rotorRate or 0.0) - 240.0 * timeStep, 0.0)
            if entry.rotorRate > 0.0 then
                entry.rotorSpin = (entry.rotorSpin + entry.rotorRate * timeStep) % 360.0
                if entry.rotorHub ~= nil then
                    entry.rotorHub.rotation = Quaternion(entry.rotorSpin, Vector3.UP)
                end
                if entry.tailRotorHub ~= nil then
                    entry.tailRotorHub.rotation = Quaternion(entry.rotorSpin * 2.3, Vector3.FORWARD)
                end
            end
        end
        -- (曾在此实现 Lua 横滚稳定器,P 版发散振荡、PD 版差分滞后弹飞,
        --  两版皆废;船体稳定改由引擎 CoM Offset 龙骨物理解决,勿再上控制环)
        if entry.isBoat and entry.originalSolid ~= nil
            and entry.chassis:GetNode() ~= nil then
            local integrity = entry.chassis:GetGrid().solidCount / entry.originalSolid
            local t = (integrity - 0.55) / 0.45
            if t < 0.0 then t = 0.0 elseif t > 1.0 then t = 1.0 end
            entry.chassis.buoyancy = entry.baseBuoyancy * t
        end
    end
end

-- 船只驾驶:桨推 + 尾舵,全部经 volume:ApplyForce。舵力施加在船尾:
-- steer=+1 把尾巴推向左舷(+Z),船头右摆——和车辆的 steer 语义一致。
local function DriveBoat(entry, timeStep)
    local node = entry.chassis:GetNode()
    local throttle = 0.0
    if input:GetKeyDown(KEY_W) then throttle = 1.0 end
    if input:GetKeyDown(KEY_S) then throttle = -0.55 end
    local steer = 0.0
    if input:GetKeyDown(KEY_A) then steer = -1.0 end
    if input:GetKeyDown(KEY_D) then steer = 1.0 end

    local rot = node.worldRotation
    -- 船尾中线点:z 用半船宽(旧写法 voxelSize*7 只适配 1.4m 宽的程序化小艇)
    local stern = node.worldTransform * Vector3(0.15, 0.15, (entry.width or 1.4) * 0.5)
    -- 桨得在水里才有劲
    if stern.y < world:GetWaterLevel() + 0.5 then
        if throttle ~= 0.0 then
            entry.chassis:ApplyForce(
                rot * Vector3(1.0, 0.0, 0.0) * (throttle * entry.power), stern)
        end
        if steer ~= 0.0 then
            entry.chassis:ApplyForce(
                rot * Vector3(0.0, 0.0, 1.0) * (steer * entry.rudder), stern)
        end
    end
    return true
end

local function DriveRollingContactCar(entry)
    local throttle = 0.0
    if input:GetKeyDown(KEY_W) then throttle = 1.0 end
    if input:GetKeyDown(KEY_S) then throttle = -0.65 end
    local steer = 0.0
    if input:GetKeyDown(KEY_A) then steer = -1.0 end
    if input:GetKeyDown(KEY_D) then steer = 1.0 end
    local braking = input:GetKeyDown(KEY_SPACE)

    local targetSpeed = throttle * entry.wheelMotorSpeed
    local motorTorque = throttle ~= 0.0 and entry.wheelMotorTorque or entry.coastTorque
    if braking then
        targetSpeed = 0.0
        motorTorque = entry.brakeTorque
    end
    for _, constraint in ipairs(entry.driveConstraints) do
        constraint:SetAngularMotorVelocity(targetSpeed, motorTorque)
    end
    for _, constraint in ipairs(entry.steeringConstraints) do
        constraint:SetServo(steer * entry.maxSteerAngle,
            entry.steerTorque, entry.steerSpeed)
    end
    return true
end

-- 载具驾驶:玩家上车后每帧调用。返回 false 表示载具已毁。
function M.Drive(entry, timeStep)
    if entry.chassis:GetNode() == nil then return false end
    if entry.isAircraft then
        if entry.kind == "heli" then return DriveHelicopter(entry, timeStep) end
        return DrivePlane(entry, timeStep)
    end
    if entry.isBoat then return DriveBoat(entry, timeStep) end
    if entry.kind == "rolling_contact_car" then return DriveRollingContactCar(entry) end

    local throttle = 0.0
    if input:GetKeyDown(KEY_W) then throttle = 1.0 end
    if input:GetKeyDown(KEY_S) then throttle = -0.7 end
    local steer = 0.0
    if input:GetKeyDown(KEY_A) then steer = -1.0 end
    if input:GetKeyDown(KEY_D) then steer = 1.0 end
    local brake = input:GetKeyDown(KEY_SPACE) and 1.0 or 0.0
    entry.vehicle:SetInput(throttle, steer, brake)

    -- 挖掘机臂(实测约定:马达正目标 = 向下;Z 抬 X 降,C 收 V 放,G 挖)
    if entry.arms ~= nil then
        local function axisInput(negKey, posKey)
            local value = 0.0
            if input:GetKeyDown(negKey) then value = value - 1.0 end
            if input:GetKeyDown(posKey) then value = value + 1.0 end
            return value
        end
        local cabSpin = axisInput(KEY_Q, KEY_E)
        local boomLift = axisInput(KEY_Z, KEY_X)
        local stickCurl = axisInput(KEY_V, KEY_C)
        entry.arms.cab:SetAngularMotorVelocity(cabSpin * 45.8366, 15000.0)
        entry.arms.boom:SetAngularMotorVelocity(boomLift * 28.6479, 60000.0)
        entry.arms.stick:SetAngularMotorVelocity(stickCurl * 45.8366, 25000.0)
        if cabSpin ~= 0.0 or boomLift ~= 0.0 or stickCurl ~= 0.0 then
            entry.cab:Activate()
            entry.boom:Activate()
            entry.stick:Activate()
        end
        entry.digTimer = entry.digTimer - timeStep
        if input:GetKeyDown(KEY_G) and entry.digTimer <= 0.0
            and entry.stick:GetNode() ~= nil then
            local tip = entry.stick:GetNode().worldTransform * Vector3(1.55, 0.1, 0.3)
            world:ApplyDamageAtWorldPoint(tip, 0.5, 3.0)
            entry.digTimer = 0.18
        end
    end

    return true
end

-- 停车状态:清零输入,松开马达目标
function M.Park(entry)
    M.SetHeadlights(entry, false)
    if entry.chassis:GetNode() == nil then return end
    if entry.isBoat then return end
    if entry.kind == "rolling_contact_car" then
        for _, constraint in ipairs(entry.driveConstraints) do
            constraint:SetAngularMotorVelocity(0.0, entry.brakeTorque)
        end
        for _, constraint in ipairs(entry.steeringConstraints) do
            constraint:SetServo(0.0, entry.steerTorque, entry.steerSpeed)
        end
        return
    end
    if entry.isAircraft then
        -- 直升机无 VoxelVehicle;固定翼拉驻车刹车防溜跑道
        if entry.vehicle ~= nil then entry.vehicle:SetInput(0.0, 0.0, 1.0) end
        if entry.rotorConstraint ~= nil and entry.mainRotor ~= nil
            and entry.mainRotor:GetNode() ~= nil then
            entry.rotorConstraint:SetAngularMotorVelocity(0.0, entry.rotorMotorTorque)
        end
        return
    end
    -- 驻车刹车:倾斜车身(挖掘机悬臂前倾)的悬挂推力靠它静态扛住,
    -- 车才能停稳入睡(引擎侧 brake 已不再唤醒睡眠体)
    entry.vehicle:SetInput(0.0, 0.0, 1.0)
    if entry.arms ~= nil then
        entry.arms.cab:SetAngularMotorVelocity(0.0, 15000.0)
        entry.arms.boom:SetAngularMotorVelocity(0.0, 60000.0)
        entry.arms.stick:SetAngularMotorVelocity(0.0, 25000.0)
    end
end

-- 找 position 附近 range 内最近的载具
-- 中心距离 + 半长修正:node 原点在网格角,大车(游艇 17.9m)按角点算会离谱
function M.VehicleCenter(entry)
    local node = entry.chassis:GetNode()
    if node == nil then return nil end
    return node.worldTransform *
        Vector3(entry.length * 0.5, 0.6, (entry.width or 2.0) * 0.5)
end

function M.FindNearest(position, range)
    local best, bestDist = nil, nil
    for _, entry in ipairs(M.list) do
        local center = M.VehicleCenter(entry)
        if center ~= nil then
            -- 减去半长让"贴着船舷"也算靠近(以中心为圆心、车长的一半为体表近似)
            local d = (center - position):Length() - entry.length * 0.35
            if d < range and (bestDist == nil or d < bestDist) then
                best, bestDist = entry, d
            end
        end
    end
    return best
end

return M
