-- 临时回归：导出真实网格与仿射变换，比较修复前后各型号、受控颈部姿态的共面外露面。
local Rig = require("dragon.DragonRig")
local Variants = require("dragon.DragonVariants")
---@type Scene
local scene_ = Scene()

local function V(v) return { v.x, v.y, v.z } end
local function Capture(rig, id, version, pose)
    local parts = {}
    for _, name in ipairs({ "chest", "neck1", "neck2", "neck3", "neck4", "head" }) do
        local node = rig.parts[name].node
        local p = node:LocalToWorld(Vector3.ZERO)
        parts[#parts + 1] = { name = name, p = V(p),
            ex = V(node:LocalToWorld(Vector3.RIGHT) - p),
            ey = V(node:LocalToWorld(Vector3.UP) - p),
            ez = V(node:LocalToWorld(Vector3.FORWARD) - p) }
    end
    print("NECK_FRAME " .. cjson.encode({ variant = id, version = version, pose = pose, parts = parts }))
end

function Start()
    scene_:CreateComponent("Octree")
    local world = scene_:CreateComponent("VoxelPhysicsWorld")
    local poses = {
        { name = "rest", pitch = 0, yaw = 0, roll = 0 },
        { name = "pitch_up", pitch = -6, yaw = 0, roll = 0 },
        { name = "pitch_down", pitch = 6, yaw = 0, roll = 0 },
        { name = "yaw_left", pitch = 0, yaw = -8, roll = 0 },
        { name = "yaw_right", pitch = 0, yaw = 8, roll = 0 },
        { name = "combined", pitch = -6, yaw = 8, roll = 2 },
    }
    for _, id in ipairs({ "small", "medium", "large" }) do
        local rig = Rig.Build(scene_, world, nil, Variants.Get(id))
        local initial = {}
        for name, part in pairs(rig.parts) do
            if part.volume ~= nil then
                local scale = part.node.scale
                local index = tonumber(name:match("^neck(%d)$"))
                if index then
                    local expected = 1.0 - 0.003 - (index - 1) * 0.006
                    assert(math.abs(scale.x - expected) < 1e-6, id .. ": neck scale")
                    ---@type Quaternion
                    local q = part.node.rotation
                    ---@type Vector3
                    local partPosition = part.node.position
                    local origin = q:Inverse() * partPosition
                    local original = Vector3(origin.x / expected, origin.y, origin.z)
                    local d = part.volume:GetGrid():GetDimensions()
                    local mid = part.node.position + q * Vector3(d.x * part.size * expected * 0.5, 0, 0)
                    assert(math.abs(mid.x) < 1e-5, id .. ": neck symmetry")
                    initial[name] = { position = part.node.position, scale = scale, original = q * original }
                else
                    assert(math.abs(scale.x - 1) < 1e-6 and math.abs(scale.y - 1) < 1e-6
                        and math.abs(scale.z - 1) < 1e-6, id .. ": unrelated part changed")
                end
            end
        end
        for _, name in ipairs({ "chest", "neck1", "neck2", "neck3", "neck4", "head" }) do
            local part = rig.parts[name]
            local grid = part.volume:GetGrid()
            local d = grid:GetDimensions()
            local voxels = {}
            for x = 0, d.x - 1 do for y = 0, d.y - 1 do for z = 0, d.z - 1 do
                if grid:IsSolid(x, y, z) then
                    voxels[#voxels + 1] = { x, y, z, grid:GetVoxelMaterial(x, y, z) }
                end
            end end end
            print("NECK_GRID " .. cjson.encode({ variant = id, name = name, size = part.size, voxels = voxels }))
        end
        for _, version in ipairs({ "before", "after" }) do
            for name, item in pairs(initial) do
                rig.parts[name].node.position = version == "before" and item.original or item.position
                rig.parts[name].node.scale = version == "before" and Vector3.ONE or item.scale
            end
            for _, pose in ipairs(poses) do
                rig:ResetPose()
                for i = 1, 4 do
                    rig:SetRot("neck" .. i, Rig.Euler(pose.pitch, pose.yaw, pose.roll))
                end
                Capture(rig, id, version, pose.name)
            end
        end
        rig:Destroy()
        print("NECK_CHECK " .. id .. ": symmetry / unrelated parts / poses OK")
    end
    print("NECK_CHECK all variants complete")
end

function Stop() end
