-- ============================================================================
-- StateMachine.lua - Animation State Machine Management (Unified FSM)
-- ============================================================================

local StateMachine = {}

local UNIFIED_FSM = "FSM/Unified.fsm"

-- Weapon types (matches weaponType parameter in Unified.fsm)
StateMachine.WeaponType = {
    NORMAL = 0,
    RIFLE = 1,
    PISTOL = 2,
    DAGGER = 3,
}

StateMachine.SHOOT_RECOVERY_TIME = 0.35

-- Create FSM manager for a character
function StateMachine.Create(modelNode)
    local manager = {
        modelNode = modelNode,
        fsm = nil,
        aimOffset = nil,
        weaponType = StateMachine.WeaponType.NORMAL,
        -- Shoot state tracking
        wasShooting = false,
        shootRecoveryTimer = 0,
        -- Turn state tracking
        lastYaw = 0,
    }

    -- Ensure AnimationController exists
    modelNode:GetOrCreateComponent("AnimationController")

    -- Create AnimationStateMachine
    manager.fsm = modelNode:CreateComponent("AnimationStateMachine")

    -- Load unified FSM
    local unifiedFile = cache:GetResource("JSONFile", UNIFIED_FSM)
    if unifiedFile == nil then
        print("ERROR: Unified FSM not found: " .. UNIFIED_FSM)
    else
        manager.fsm:LoadFromJSONFile(unifiedFile)
        manager.fsm:Start()
    end

    -- Create AimOffset component
    manager.aimOffset = modelNode:CreateComponent("AimOffset")
    manager.aimOffset:AddBone("Bip001 Spine", 0.40, 0.40)
    manager.aimOffset:AddBone("Bip001 Spine1", 0.35, 0.35)
    manager.aimOffset:AddBone("Bip001 Spine2", 0.25, 0.25)
    manager.aimOffset:SetMaxPitch(50)
    manager.aimOffset:SetMaxYaw(30)
    manager.aimOffset:SetSmoothSpeed(12)
    manager.aimOffset:SetYawCompensation(0)
    manager.aimOffset:SetEnabled(false)

    return manager
end

-- Set weapon type (0=normal, 1=rifle, ...)
function StateMachine.SetWeaponType(manager, weaponType)
    if manager.weaponType == weaponType then return end

    manager.weaponType = weaponType

    if manager.fsm then
        manager.fsm:SetInt("weaponType", weaponType)
    end

    -- Enable AimOffset only when armed
    local isArmed = (weaponType ~= StateMachine.WeaponType.NORMAL)
    if manager.aimOffset then
        manager.aimOffset:SetEnabled(isArmed)
    end
end

-- Get current weapon type
function StateMachine.GetWeaponType(manager)
    return manager.weaponType
end

-- Cycle to next weapon type (Normal -> Rifle -> Pistol -> Dagger -> Normal)
function StateMachine.CycleWeapon(manager)
    if manager.weaponType == StateMachine.WeaponType.NORMAL then
        StateMachine.SetWeaponType(manager, StateMachine.WeaponType.RIFLE)
    elseif manager.weaponType == StateMachine.WeaponType.RIFLE then
        StateMachine.SetWeaponType(manager, StateMachine.WeaponType.PISTOL)
    elseif manager.weaponType == StateMachine.WeaponType.PISTOL then
        StateMachine.SetWeaponType(manager, StateMachine.WeaponType.DAGGER)
    else
        StateMachine.SetWeaponType(manager, StateMachine.WeaponType.NORMAL)
    end
end

-- Update FSM parameters from CharacterComponent
-- characterYaw: optional, pass character's Y rotation for turn detection
function StateMachine.UpdateFromCharacter(manager, character, characterYaw)
    if manager.fsm == nil or character == nil then return end

    local moveSpeed = character:GetMoveSpeed()
    local direction = character:GetMoveDirection()
    local isGrounded = character:IsOnGround()
    local isJumping = character:IsJumping()

    -- Trigger jump animation
    if character:IsJumpStarted() then
        manager.fsm:SetTrigger("jump")
    end

    -- When isJumping is true and not yet airborne, force isGrounded to false
    local effectiveGrounded = isGrounded and not isJumping

    -- Detect turning (idle rotation) using character yaw
    if characterYaw then
        local yawDelta = characterYaw - manager.lastYaw
        -- Handle -180/180 wrap
        if yawDelta > 180 then yawDelta = yawDelta - 360 end
        if yawDelta < -180 then yawDelta = yawDelta + 360 end

        local isTurning = moveSpeed < 0.1 and math.abs(yawDelta) > 0.5
        manager.fsm:SetBool("isTurning", isTurning)
        manager.lastYaw = characterYaw
    end

    manager.fsm:SetFloat("moveSpeed", moveSpeed)
    manager.fsm:SetFloat("direction", direction)
    manager.fsm:SetBool("isGrounded", effectiveGrounded)
end

-- Set crouching state
function StateMachine.SetCrouching(manager, isCrouching)
    if manager.fsm then
        manager.fsm:SetBool("isCrouching", isCrouching)
    end
end

-- Set turning state (for idle turn animation)
function StateMachine.SetTurning(manager, isTurning)
    if manager.fsm then
        manager.fsm:SetBool("isTurning", isTurning)
    end
end

-- Trigger actions
function StateMachine.TriggerShoot(manager)
    if manager.fsm then
        manager.fsm:SetTrigger("shoot")
    end
end

function StateMachine.TriggerReload(manager)
    if manager.fsm then
        manager.fsm:SetTrigger("reload")
    end
end

function StateMachine.TriggerDance(manager)
    if manager.fsm then
        manager.fsm:SetTrigger("dance")
    end
end

function StateMachine.TriggerSad(manager)
    if manager.fsm then
        manager.fsm:SetTrigger("sad")
    end
end

function StateMachine.TriggerDie(manager)
    if manager.fsm then
        manager.fsm:SetTrigger("die")
    end
end

-- Update AimOffset
function StateMachine.UpdateAimOffset(manager, pitch, yaw, characterYaw)
    if manager.aimOffset == nil or not manager.aimOffset.enabled then return end

    manager.aimOffset:SetTargetPitch(pitch)

    local relativeYaw = yaw - characterYaw
    while relativeYaw > 180 do relativeYaw = relativeYaw - 360 end
    while relativeYaw < -180 do relativeYaw = relativeYaw + 360 end
    manager.aimOffset:SetTargetYaw(relativeYaw)
end

-- Check if armed (any weapon equipped)
function StateMachine.IsArmedMode(manager)
    return manager.weaponType ~= StateMachine.WeaponType.NORMAL
end

-- Check if in Rifle mode
function StateMachine.IsRifleMode(manager)
    return manager.weaponType == StateMachine.WeaponType.RIFLE
end

-- Check if in Pistol mode
function StateMachine.IsPistolMode(manager)
    return manager.weaponType == StateMachine.WeaponType.PISTOL
end

-- Check if in Dagger mode
function StateMachine.IsDaggerMode(manager)
    return manager.weaponType == StateMachine.WeaponType.DAGGER
end

-- Get current state name
function StateMachine.GetCurrentState(manager, layerIndex)
    if manager.fsm then
        return manager.fsm:GetCurrentState(layerIndex or 0)
    end
    return ""
end

-- Check if UpperBody layer is currently in a shoot animation state (rifle/pistol)
-- Unified.fsm: Base=0, LowerBody=1, UpperBody=2, FullBody=3
-- Note: DaggerAttack is excluded - dagger can attack while moving
function StateMachine.IsInShootAnimation(manager)
    if manager.fsm == nil then return false end

    local upperBodyState = manager.fsm:GetCurrentState(2)

    -- Check if in rifle or pistol shooting state (dagger attack allows movement)
    return upperBodyState == "RifleShoot" or
           upperBodyState == "RifleCrouchShoot" or
           upperBodyState == "PistolShoot" or
           upperBodyState == "PistolCrouchShoot"
end

-- Update shoot state and recovery timer (call this every frame)
function StateMachine.UpdateShootState(manager, dt)
    local currentlyShooting = StateMachine.IsInShootAnimation(manager)

    -- Detect shoot animation end -> start recovery timer
    if manager.wasShooting and not currentlyShooting then
        manager.shootRecoveryTimer = StateMachine.SHOOT_RECOVERY_TIME
    end

    manager.wasShooting = currentlyShooting

    -- Count down recovery timer
    if manager.shootRecoveryTimer > 0 then
        manager.shootRecoveryTimer = manager.shootRecoveryTimer - dt
    end
end

-- Check if currently shooting OR in post-shoot recovery (should disable running)
function StateMachine.IsShooting(manager)
    -- In shoot animation
    if StateMachine.IsInShootAnimation(manager) then
        return true
    end

    -- In post-shoot recovery
    if manager.shootRecoveryTimer > 0 then
        return true
    end

    return false
end

return StateMachine
