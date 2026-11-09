-- ====================================================================
-- player.lua - 第三人称角色(CharacterComponent + VoxelCharacterController)
--
-- 外观换成体素角色「诺米」(game/BlockCharacter + game/NomiVoxelData)，
-- 动画由 BlockCharacter 程序化驱动，不再使用 AnimatedModel / 武器 FSM。
-- 物理控制器使用 Jolt-backed VoxelCharacterController；驾驶时沿用
-- VoxelTown 的载具追尾相机。
-- ====================================================================

local config = require("config")
local StateMachine = require("game.StateMachine") -- 只用 WeaponType 常量
local BlockCharacter = require("game.BlockCharacter")
local NomiVoxelData = require("game.NomiVoxelData")
local vehicles = require("vehicles")

local M = {}
M.WeaponType = StateMachine.WeaponType

local world
local scene
local cameraNode
local characterNode
local modelNode
local characterController
local character
local nomi = nil
local weaponType = StateMachine.WeaponType.NORMAL

local yaw, pitch = 0.0, 5.0
local mouseGuard = 0.5
local promptRoot = nil
local promptLabel = nil
local isArmed = false
local isAiming = false
local isCrouching = false
local swimVelocity = Vector3.ZERO

local CAMERA_MIN_DISTANCE = 0.5
local EYE_HEIGHT = 1.55
local TOOL_ORIGIN_OFFSET = Vector3(0.35, 1.25, 0.55)
local CAMERA = {
    normal = {
        distance = 5.0,
        offset = Vector3(0.0, 1.7, 0.0),
        fov = 45.0,
    },
    armed = {
        distance = 4.0,
        offset = Vector3(0.6, 1.6, 0.0),
        fov = 45.0,
    },
    aiming = {
        distance = 2.0,
        offset = Vector3(0.4, 1.5, 0.0),
        fov = 32.0,
    },
    transitionSpeed = 8.0,
}
local currentCameraDistance = CAMERA.normal.distance
local currentCameraOffset = CAMERA.normal.offset
local currentCameraFov = CAMERA.normal.fov
local WEAPON_NAMES = {
    [StateMachine.WeaponType.NORMAL] = "普通",
    [StateMachine.WeaponType.RIFLE] = "步枪",
    [StateMachine.WeaponType.PISTOL] = "手枪",
    [StateMachine.WeaponType.DAGGER] = "匕首",
}

-- 视觉回归测试 hook：资源文件 water_test_cam.txt（一行
-- "x,y,z,yaw,pitch[,keepVehicles[,autoAssemblyCrash]]"）固定出生点与视角。正常游戏始终使用
-- 第三人称；hook 模式保留原第一人称固定机位，避免水面回归基线被角色遮挡。
local camOverride = nil
do
    pcall(function()
        if not cache:Exists("water_test_cam.txt") then return end
        local file = cache:GetFile("water_test_cam.txt")
        if file ~= nil then
            local line = file:ReadLine()
            file:Close()
            local values = {}
            for number in string.gmatch(tostring(line), "[-%d%.]+") do
                table.insert(values, tonumber(number))
            end
            if #values >= 5 then
                camOverride = values
                yaw, pitch = values[4], values[5]
            end
        end
    end)
end

M.driving = nil
-- 镜头绕角色的额外偏航（度），给截图验证看正面用；正常游戏保持 0
M.cameraYawOffset = 0.0

function M.GetCamOverride()
    return camOverride
end

local function CreatePrompt()
    local font = cache:GetResource("Font", "Fonts/Anonymous Pro.ttf")
    promptRoot = ui.root:CreateChild("UIElement")
    promptRoot:SetSize(160, 40)
    promptRoot:SetPosition(graphics.width / 2 - 72, graphics.height / 2 + 56)
    promptRoot.visible = false

    local keycap = promptRoot:CreateChild("BorderImage")
    keycap:SetFixedSize(34, 34)
    keycap.color = Color(0.06, 0.06, 0.08)
    keycap.opacity = 0.88
    keycap.blendMode = BLEND_ALPHA

    local keyText = keycap:CreateChild("Text")
    keyText:SetFont(font, 20)
    keyText.text = "F"
    keyText.color = Color(1.0, 1.0, 1.0)
    keyText:SetAlignment(HA_CENTER, VA_CENTER)

    promptLabel = promptRoot:CreateChild("Text")
    promptLabel:SetFont(font, 16)
    promptLabel:SetPosition(42, 8)
    promptLabel.color = Color(1.0, 1.0, 1.0)
end

local function UpdatePrompt(entry)
    if promptRoot == nil then return end
    if entry == nil then
        promptRoot.visible = false
        return
    end
    promptRoot.visible = true
    promptLabel.text = "驾驶 " .. (entry.name or "")
end

local function UpdateWeaponState()
    isArmed = weaponType ~= StateMachine.WeaponType.NORMAL
    isAiming = false
    -- 空手时朝移动方向转身（方块角色只有前后摆腿，侧移会很怪）；持械时朝镜头
    character.autoRotateToMoveDir = not isArmed
    character.rotationSpeed = 1440.0
    if isArmed then
        characterNode.worldRotation = Quaternion(0.0, yaw, 0.0)
    end
end

--- 显示 / 隐藏角色外观。几何挂在一层层骨骼子节点上，Node:SetEnabled 只管单个
--- 节点，必须递归。仅创建修长版。
local function ApplyModelVisibility(visible)
    if modelNode == nil then return end
    modelNode:SetDeepEnabled(visible)
end

local function CreateCharacter(spawn)
    characterNode = scene:CreateChild("Player")
    characterNode.worldPosition = spawn

    modelNode = characterNode:CreateChild("ModelNode")
    nomi = BlockCharacter.CreateVoxel(modelNode, NomiVoxelData, BlockCharacter.SLENDER)
    ApplyModelVisibility(true)

    characterController = characterNode:CreateComponent("VoxelCharacterController")
    characterController:SetHeight(config.PLAYER_HEIGHT)
    characterController:SetRadius(config.PLAYER_RADIUS)
    characterController:SetJumpSpeed(config.JUMP_SPEED)
    characterController:SetGravityFactor(1.0)

    character = characterNode:CreateComponent("CharacterComponent")
    character:SetWalkSpeed(config.WALK_SPEED)
    character:SetRunSpeed(config.RUN_SPEED)
    character:SetEnableWalkMode(true)
    character:SetAirControlFactor(0.6)
    character.controls.yaw = yaw
    character.controls.pitch = pitch
    UpdateWeaponState()

    -- CharacterComponent先订阅同一世界的 PhysicsPreStep；这个回调后订阅，只在
    -- 游泳时覆盖三维速度，让通用角色逻辑继续负责陆地移动和动画状态。
    SubscribeToEvent(world, "PhysicsPreStep", "VoxelTownPlayerPhysicsPreStep")

    if camOverride ~= nil then
        ApplyModelVisibility(false)
    end
end

local function SetCharacterActive(active, position)
    if active then
        if position ~= nil then
            characterNode.worldPosition = position
        end
        characterNode.worldRotation = Quaternion(0.0, yaw, 0.0)
        characterController:SetEnabled(true)
        characterController:SetLinearVelocity(Vector3.ZERO)
        character:SetEnabled(true)
        if camOverride == nil then
            ApplyModelVisibility(true)
        end
    else
        character:SetEnabled(false)
        characterController:SetDesiredVelocity(Vector3.ZERO)
        characterController:SetLinearVelocity(Vector3.ZERO)
        characterController:SetEnabled(false)
        ApplyModelVisibility(false)
    end
end

local function EnterVehicle(entry)
    M.driving = entry
    isAiming = false
    vehicles.SetHeadlights(entry, true)
    UpdatePrompt(nil)
    SetCharacterActive(false)
end

local function ExitVehicle(entry)
    local exitPosition = characterNode.worldPosition
    if entry ~= nil and entry.chassis ~= nil then
        local node = entry.chassis:GetNode()
        if node ~= nil then
            exitPosition = node.worldPosition
                + node.worldRotation * Vector3(entry.length * 0.5, 0.5, -1.5)
            exitPosition.y = math.max(exitPosition.y, 1.2)
        end
        vehicles.Park(entry)
    end
    M.driving = nil
    SetCharacterActive(true, exitPosition)
end

local function UpdateMouseLook(timeStep)
    mouseGuard = mouseGuard - timeStep
    if mouseGuard <= 0.0 then
        yaw = yaw + input.mouseMoveX * YAW_SENSITIVITY
        pitch = Clamp(pitch + input.mouseMoveY * YAW_SENSITIVITY, -80.0, 80.0)
    end
    character.controls.yaw = yaw
    character.controls.pitch = pitch
end

local function ReadMoveInput()
    local move = Vector3.ZERO
    if input:GetKeyDown(KEY_W) then move = move + Vector3.FORWARD end
    if input:GetKeyDown(KEY_S) then move = move + Vector3.BACK end
    if input:GetKeyDown(KEY_A) then move = move + Vector3.LEFT end
    if input:GetKeyDown(KEY_D) then move = move + Vector3.RIGHT end
    if move:LengthSquared() > 1.0 then move = move:Normalized() end
    return move
end

local function UpdateOnFoot(timeStep)
    UpdateMouseLook(timeStep)

    local controls = character.controls
    controls:Set(CTRL_FORWARD + CTRL_BACK + CTRL_LEFT + CTRL_RIGHT + CTRL_JUMP + CTRL_RUN, false)
    local swimming = characterController:IsSwimming()
    local move = ReadMoveInput()

    if swimming then
        swimVelocity = Quaternion(pitch, yaw, 0.0) * move * config.SWIM_SPEED
        local vertical = swimVelocity.y
        if input:GetKeyDown(KEY_SPACE) then vertical = config.SWIM_SPEED end
        if input:GetKeyDown(KEY_C) or input:GetKeyDown(KEY_LCTRL) then
            vertical = -config.SWIM_SPEED
        end
        swimVelocity = Vector3(swimVelocity.x, vertical, swimVelocity.z)
    else
        swimVelocity = Vector3.ZERO
        if input:GetKeyDown(KEY_W) then controls:Set(CTRL_FORWARD, true) end
        if input:GetKeyDown(KEY_S) then controls:Set(CTRL_BACK, true) end
        if input:GetKeyDown(KEY_A) then controls:Set(CTRL_LEFT, true) end
        if input:GetKeyDown(KEY_D) then controls:Set(CTRL_RIGHT, true) end
        if input:GetKeyDown(KEY_SPACE) then controls:Set(CTRL_JUMP, true) end
        if input:GetKeyDown(KEY_SHIFT) and not nomi:IsUsing() then
            controls:Set(CTRL_RUN, true)
        end
    end

    if not swimming and input:GetKeyPress(KEY_C) then
        isCrouching = not isCrouching
    end
    isAiming = isArmed and input:GetMouseButtonDown(MOUSEB_RIGHT)

    local nearby = vehicles.FindNearest(characterNode.worldPosition, config.ENTER_RANGE)
    UpdatePrompt(nearby)
    if input:GetKeyPress(KEY_F) and nearby ~= nil then
        EnterVehicle(nearby)
    end
end

local function UpdateDriving(timeStep)
    local entry = M.driving
    if not vehicles.Drive(entry, timeStep) then
        ExitVehicle(entry)
        return
    end

    yaw = yaw + input.mouseMoveX * YAW_SENSITIVITY
    pitch = Clamp(pitch + input.mouseMoveY * YAW_SENSITIVITY, -20.0, 60.0)
    if input:GetKeyPress(KEY_F) then
        ExitVehicle(entry)
    end
end

local function UpdateAnimation(timeStep)
    if nomi == nil or M.driving ~= nil then return end

    nomi:Update(timeStep, {
        moveSpeed = character:GetMoveSpeed(),
        onGround = character:IsOnGround() or characterController:IsSwimming(),
        armed = isArmed,
        aiming = isAiming,
        crouching = isCrouching,
        aimPitch = pitch,
    })
end

local function UpdateOnFootCamera(timeStep)
    local swimming = characterController:IsSwimming()
    if camOverride ~= nil then
        cameraNode.worldPosition = characterNode.worldPosition
            + Vector3(0.0, EYE_HEIGHT + (swimming and 0.3 or 0.0), 0.0)
        cameraNode.worldRotation = Quaternion(pitch, yaw, 0.0)
        return
    end

    local target
    if isAiming then
        target = CAMERA.aiming
    elseif isArmed then
        target = CAMERA.armed
    else
        target = CAMERA.normal
    end

    local factor = 1.0 - math.exp(-CAMERA.transitionSpeed * timeStep)
    currentCameraDistance = Lerp(currentCameraDistance, target.distance, factor)
    currentCameraOffset = currentCameraOffset:Lerp(target.offset, factor)
    currentCameraFov = Lerp(currentCameraFov, target.fov, factor)

    local camera = cameraNode:GetComponent("Camera")
    camera.fov = currentCameraFov

    local yawRotation = Quaternion(yaw + M.cameraYawOffset, Vector3.UP)
    local cameraRotation = yawRotation * Quaternion(pitch, Vector3.RIGHT)
    local aimPoint = characterNode.worldPosition + yawRotation * currentCameraOffset
    local rayDirection = cameraRotation * Vector3.BACK
    local rayDistance = currentCameraDistance
    local hit = world:RaycastSingle(Ray(aimPoint, rayDirection), rayDistance)
    if hit.hit then
        rayDistance = math.min(rayDistance, math.max(CAMERA_MIN_DISTANCE, hit.distance - 0.15))
    end

    cameraNode.worldPosition = aimPoint + rayDirection * rayDistance
    cameraNode.worldRotation = cameraRotation
end

local function UpdateDrivingCamera()
    local entry = M.driving
    if entry == nil or entry.chassis == nil then return end
    local node = entry.chassis:GetNode()
    if node == nil then return end

    local target = node.worldPosition + Vector3(0.0, 1.2, 0.0)
    local cameraRotation = Quaternion(pitch, yaw, 0.0)
    cameraNode.worldPosition = target
        - cameraRotation * Vector3(0.0, 0.0, 9.0 + entry.length)
    cameraNode.worldRotation = cameraRotation
end

function M.Init(worldRef, sceneRef, spawn)
    world = worldRef
    scene = sceneRef
    CreateCharacter(spawn)

    cameraNode = scene:CreateChild("Camera")
    local camera = cameraNode:CreateComponent("Camera")
    camera.farClip = 400.0
    renderer:SetViewport(0, Viewport:new(scene, camera))

    CreatePrompt()
    input.mouseVisible = false
end

function M.Update(timeStep)
    if M.driving ~= nil then
        UpdatePrompt(nil)
        UpdateDriving(timeStep)
    else
        UpdateOnFoot(timeStep)
    end
end

function M.PostUpdate(timeStep)
    UpdateAnimation(timeStep)
    if M.driving ~= nil then
        UpdateDrivingCamera()
    else
        UpdateOnFootCamera(timeStep)
    end
end

function M.GetCamera()
    return cameraNode
end

function M.GetFeet()
    return characterNode ~= nil and characterNode.worldPosition or Vector3.ZERO
end

function M.GetToolOrigin()
    if characterNode == nil then return Vector3.ZERO end
    return characterNode.worldPosition
        + characterNode.worldRotation * TOOL_ORIGIN_OFFSET
end

function M.IsSwimming()
    return characterController ~= nil
        and characterController.enabledEffective
        and characterController:IsSwimming()
end

function M.IsArmed()
    return isArmed
end

function M.SetWeaponType(newType)
    weaponType = newType
    if character ~= nil then UpdateWeaponState() end
end

function M.TriggerShoot()
    if nomi == nil then return end
    nomi:TriggerUse()
end

--- 校验用：当前实际可见的角色数量（只实例化一个模型）。
function M.DebugVisibleModels()
    return nomi ~= nil and nomi.root.enabled and nomi.bones.body.enabled and 1 or 0
end

function M.GetWeaponName()
    return WEAPON_NAMES[weaponType] or "未知"
end

-- 后订阅的游泳适配：覆盖 CharacterComponent 的平面移动意图，但不绕开
-- VoxelCharacterController 或 VoxelPhysicsWorld。
function VoxelTownPlayerPhysicsPreStep(eventType, eventData)
    if M.driving == nil and characterController ~= nil
        and characterController.enabledEffective and characterController:IsSwimming() then
        characterController:SetDesiredVelocity(swimVelocity)
    end
end

return M
