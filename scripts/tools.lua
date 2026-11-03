-- ====================================================================
-- tools.lua — 玩法工具箱:炸药 / 散弹枪 / 喷漆 / 喷枪(挖掘),右键拖拽
--
-- 全部由引擎原语组合而成,是 docs/design/voxel-physics/scripting-api.md
-- "玩法配方"一节的可运行版本。原则:先组合,证明热点再下沉引擎。
-- ====================================================================

local config = require("config")

local M = {}
M.current = 1    -- 当前工具索引(1..4)

local world
local player
local cooldown = 0.0
local bombs = {}          -- { volume, fuse }
local grabHandle = nil    -- 引擎抓取句柄(kinematic 锚点+柔性零长弹簧)
local grabDist = 0.0      -- 持距(滚轮可调)

local function SelectTool(index)
    M.current = index
    local weaponType = player.WeaponType.NORMAL
    if index >= 2 then
        weaponType = player.WeaponType.RIFLE
    end
    player.SetWeaponType(weaponType)
end

function M.Init(worldRef, playerRef)
    world = worldRef
    player = playerRef
    SelectTool(M.current)
    -- 炸弹碰撞引爆 + 未来的落地烟尘都吃这一路事件
    world:SetContactEventThreshold(3.0)
    SubscribeToEvent("VoxelContact", "VoxelTownBombContact")
end

-- 相机视线射线
local function AimRay(maxDist)
    local cam = player.GetCamera()
    local origin = cam.worldPosition
    local dir = cam.worldRotation * Vector3(0.0, 0.0, 1.0)
    return origin, dir, world:RaycastSingle(Ray(origin, dir), maxDist)
end

-- 第三人称瞄准分两段：相机射线决定准星目标，工具从角色出口点朝目标发射。
-- 这样投射物不会从镜头凭空出现，角色身前的近距离遮挡也能正确挡住射线。
local function ToolAim(maxDist)
    local cameraOrigin, cameraDirection, cameraHit = AimRay(maxDist)
    local target = cameraHit.hit and cameraHit.position
        or cameraOrigin + cameraDirection * maxDist
    local origin = player.GetToolOrigin()
    local toTarget = target - origin
    if toTarget:LengthSquared() < 0.0001 then
        return origin, cameraDirection
    end
    return origin, toTarget:Normalized()
end

-- 工具 1:炸弹——黑色圆球 + 橙色引信头。硬着陆立即引爆(接触事件),
-- 引信计时只兜底轻放/空掷的情况。
local function ThrowBomb()
    local origin, aimDirection = ToolAim(40.0)
    local volume = world:CreateVolume(5, 7, 5, 0.07, origin, Quaternion())
    local g = volume:GetGrid()
    for z = 0, 4 do
        for y = 0, 4 do
            for x = 0, 4 do
                local dx, dy, dz = x - 2, y - 2, z - 2
                if dx * dx + dy * dy + dz * dz <= 5 then
                    g:FillBox(x, y, z, x, y, z, true)
                end
            end
        end
    end
    g:FillBox(2, 5, 2, 2, 6, 2, true)   -- 引信杆
    g:PaintBox(0, 0, 0, 100000, 100000, 100000, config.MAT_BOMB)
    g:PaintBox(2, 5, 2, 2, 6, 2, config.MAT_FUSE)
    volume.material = world:GetPaletteMaterial()
    volume.density = 800.0
    world:FinalizeVolumeAsDynamic(volume)
    volume:RebuildGeometry()
    local dir = (aimDirection + Vector3(0.0, 0.15, 0.0)):Normalized()
    volume:ApplyImpulse(dir * 220.0, origin)   -- 炸弹 ~16 kg → 出手 ~13 m/s
    table.insert(bombs, {
        volume = volume,
        fuse = config.BOMB_FUSE,
        nodeId = volume:GetNode().ID,
        armDelay = 0.15,   -- 出手瞬间不炸自己
    })
end

-- 接触事件:炸弹硬着陆 → 立即引爆(置零引信,下一帧 UpdateBombs 处理)
function VoxelTownBombContact(eventType, eventData)
    local a = eventData["VolumeA"]:GetPtr("VoxelVolume")
    local b = eventData["VolumeB"]:GetPtr("VoxelVolume")
    for _, bomb in ipairs(bombs) do
        if bomb.armDelay <= 0.0 then
            local node = bomb.volume:GetNode()
            if node ~= nil then
                local id = node.ID
                if (a ~= nil and a:GetNode() ~= nil and a:GetNode().ID == id)
                    or (b ~= nil and b:GetNode() ~= nil and b:GetNode().ID == id) then
                    bomb.fuse = 0.0
                end
            end
        end
    end
end

local function UpdateBombs(timeStep)
    for i = #bombs, 1, -1 do
        local bomb = bombs[i]
        bomb.fuse = bomb.fuse - timeStep
        bomb.armDelay = bomb.armDelay - timeStep
        local node = bomb.volume:GetNode()
        if node == nil then
            table.remove(bombs, i)
        elseif bomb.fuse <= 0.0 then
            local at = node.worldPosition
            world:RemoveVolume(bomb.volume)
            -- 先炸开再推:冲量顺带唤醒范围内的冻结碎片
            world:ApplyDamageAtWorldPoint(at, config.BOMB_RADIUS, config.BOMB_POWER)
            world:ApplyRadialImpulse(at, config.BOMB_RADIUS * 1.6, config.BOMB_IMPULSE)
            table.remove(bombs, i)
        end
    end
end

-- 工具 2:散弹枪——N 条散布射线,命中处开小坑
local function FireShotgun()
    player.TriggerShoot()
    local origin, aimDirection = ToolAim(60.0)
    local aimRotation = Quaternion(Vector3.FORWARD, aimDirection)
    for _ = 1, config.SHOT_PELLETS do
        local spread = Vector3(
            (math.random() - 0.5) * 2.0 * config.SHOT_SPREAD,
            (math.random() - 0.5) * 2.0 * config.SHOT_SPREAD,
            1.0)
        local dir = (aimRotation * spread):Normalized()
        local hit = world:RaycastSingle(Ray(origin, dir), 60.0)
        if hit.hit then
            world:ApplyDamageAtWorldPoint(hit.position, config.SHOT_CRATER, config.SHOT_POWER)
        end
    end
end

-- 工具 3:喷漆——把命中体素染成 MAT_PAINT,局部重网格(world 每帧预算化重建)
local function SprayPaint()
    player.TriggerShoot()
    local _, _, hit = AimRay(25.0)
    if not hit.hit or hit.volume == nil then return end
    local volume = hit.volume
    local node = volume:GetNode()
    if node == nil then return end
    local grid = volume:GetGrid()
    local voxelSize = volume.voxelSize
    local local_ = node.worldTransform:Inverse() * hit.position
    local r = config.SPRAY_RADIUS
    local x0 = math.floor((local_.x - r) / voxelSize)
    local y0 = math.floor((local_.y - r) / voxelSize)
    local z0 = math.floor((local_.z - r) / voxelSize)
    local x1 = math.floor((local_.x + r) / voxelSize)
    local y1 = math.floor((local_.y + r) / voxelSize)
    local z1 = math.floor((local_.z + r) / voxelSize)
    local rSq = (r / voxelSize) * (r / voxelSize)
    local cx = local_.x / voxelSize
    local cy = local_.y / voxelSize
    local cz = local_.z / voxelSize
    for z = z0, z1 do
        for y = y0, y1 do
            for x = x0, x1 do
                if x >= 0 and y >= 0 and z >= 0 then
                    local dx, dy, dz = x + 0.5 - cx, y + 0.5 - cy, z + 0.5 - cz
                    if dx * dx + dy * dy + dz * dz <= rSq
                        and grid:IsSolid(x, y, z) then
                        grid:SetVoxelMaterial(x, y, z, config.MAT_PAINT)
                    end
                end
            end
        end
    end
    volume:MarkRegionDirty(x0, y0, z0, x1, y1, z1)
end

-- 工具 4:喷枪——持续小球挖掘
local function DigBlast()
    player.TriggerShoot()
    local _, _, hit = AimRay(20.0)
    if hit.hit then
        world:ApplyDamageAtWorldPoint(hit.position, config.DIG_RADIUS, config.DIG_POWER)
    end
end

-- 右键推拽:引擎级抓取约束(BeginGrab/UpdateGrab/EndGrab)。力走约束求解器,
-- 同一机制拖碎块、拉铰链门、滑抽屉;冻结碎片抓取即唤醒。旧 Lua PD 力配方已废
-- (重物震荡是它的结构病,plans 待办就此销账)。滚轮调持距;拉不动/卡墙/门到
-- 限位时引擎判定脱手(UpdateGrab 返回 false)。
local function UpdateGrab(timeStep)
    if player.IsArmed() then
        if grabHandle ~= nil then
            world:EndGrab(grabHandle)
            grabHandle = nil
        end
        return
    end

    if input:GetMouseButtonDown(MOUSEB_RIGHT) then
        if grabHandle == nil then
            local _, _, hit = AimRay(config.GRAB_RANGE)
            if hit.hit and hit.volume ~= nil then
                local h = world:BeginGrab(hit.volume, hit.position)
                if h ~= 0xffffffff then
                    grabHandle = h
                    grabDist = (hit.position - player.GetCamera().worldPosition):Length()
                end
            end
        end
        if grabHandle ~= nil then
            local wheel = input.mouseMoveWheel
            if wheel ~= 0 then
                grabDist = math.max(0.8, math.min(config.GRAB_RANGE, grabDist + wheel * 0.6))
            end
            local cam = player.GetCamera()
            local target = cam.worldPosition
                + cam.worldRotation * Vector3(0.0, 0.0, 1.0) * grabDist
            if not world:UpdateGrab(grabHandle, target, timeStep) then
                grabHandle = nil
            end
        end
    elseif grabHandle ~= nil then
        world:EndGrab(grabHandle)
        grabHandle = nil
    end
end

local bootGuard = 0.5   -- 窗口获焦瞬间的鼠标残留状态会凭空掷弹,冷启动半秒内不开火

function M.Update(timeStep)
    bootGuard = bootGuard - timeStep
    if bootGuard > 0.0 then return end
    -- 驾驶中不使用手持工具
    if player.driving ~= nil then
        if grabHandle ~= nil then
            world:EndGrab(grabHandle)
            grabHandle = nil
        end
        UpdateBombs(timeStep)
        return
    end

    if input:GetKeyPress(KEY_Q) then
        SelectTool(M.current % 4 + 1)
    else
        for i = 1, 4 do
            if input:GetKeyPress(KEY_1 + i - 1) then
                SelectTool(i)
                break
            end
        end
    end

    cooldown = cooldown - timeStep
    local usePressed = input:GetMouseButtonPress(MOUSEB_LEFT)
    local useHeld = input:GetMouseButtonDown(MOUSEB_LEFT)
    if cooldown <= 0.0 then
        if M.current == 1 and usePressed then
            ThrowBomb(); cooldown = 0.6
        elseif M.current == 2 and usePressed then
            FireShotgun(); cooldown = config.SHOT_COOLDOWN
        elseif M.current == 3 and useHeld then
            SprayPaint(); cooldown = config.SPRAY_COOLDOWN
        elseif M.current == 4 and useHeld then
            DigBlast(); cooldown = config.DIG_COOLDOWN
        end
    end

    UpdateGrab(timeStep)
    UpdateBombs(timeStep)
end

return M
