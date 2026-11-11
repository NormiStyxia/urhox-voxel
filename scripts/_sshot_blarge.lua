-- 临时截图：龙外皮
local VARIANT = "large"
local YAW, PITCH, DIST, TY, TZ, SKIN = -90, 8, 6.5, 1.0, -3.2, true
SHOT_OUT = "_shot_b1.png"
ANIM = false
local frame = 0
local cfg = { noUI = true, noInput = true }
cfg.setup = function(T)
    local R = require('dragon.DragonRig'); R.TAIL_ALIGN = SKIN; R.LIMB_ALIGN = SKIN
    if not SKIN or VARIANT ~= T.variant then
        local want = VARIANT
        if want == T.variant then T.SetVariant(want == "medium" and "small" or "medium") end
        T.SetVariant(want)
    end
    T.externalDrive = not ANIM
    if not ANIM then T.rig:ResetPose() end
    T.SetPlayMode(false)
    T.showNomi = false
    T.cam.follow = false
    local S = T.rig.size or 1.0
    T.cam.yaw, T.cam.pitch, T.cam.dist = 180 + YAW, PITCH, DIST * S
    T.cam.target = Vector3(0, TY * S, TZ * S)
end
cfg.update = function(T, dt)
    frame = frame + 1
    local S = T.rig.size or 1.0
    T.cam.follow = false
    T.cam.yaw, T.cam.pitch, T.cam.dist = 180 + YAW, PITCH, DIST * S
    T.cam.target = Vector3(0, TY * S, TZ * S)
    if frame == (ANIM and 150 or 38) then
        -- 导出尾巴体素（局部格坐标 + 体积节点的世界变换），离线渲染用
        for name, part in pairs(T.rig.parts) do
            if part.wing or part.volume == nil then part = nil end
            if part ~= nil then
                local g = part.volume:GetGrid()
                local d = g:GetDimensions()
                local n = part.node
                local p, q = n.worldPosition, n.worldRotation
                local ex, ey, ez = q * Vector3.RIGHT, q * Vector3.UP, q * Vector3.FORWARD
                local parts = {}
                for x = 0, d.x - 1 do for y = 0, d.y - 1 do for z = 0, d.z - 1 do
                    if g:IsSolid(x, y, z) then parts[#parts + 1] = x .. "," .. y .. "," .. z .. "," .. g:GetVoxelMaterial(x, y, z) end
                end end end
                print(string.format("SHOT tv %s %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f ", name, part.size,
                    p.x, p.y, p.z, ex.x, ex.y, ex.z, ey.x, ey.y, ey.z, ez.x, ez.y, ez.z) .. table.concat(parts, ";"))
            end
        end
    end
    if frame == (ANIM and 152 or 40) then
        local img = Image()
        graphics:TakeScreenShot(img)
        img:SavePNG(SHOT_OUT)
        print("SHOT saved", SHOT_OUT)
        engine:Exit()
    end
end
BREATH_SHOT_CFG = cfg
local DragonTest = require("dragon.DragonTest")
function Start() DragonTest.Start() end
function Stop() DragonTest.Stop() end
