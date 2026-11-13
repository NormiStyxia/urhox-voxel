-- ====================================================================
-- NomiController.lua — 遗迹里的诺米：体素物理角色控制器 + 第三人称瞄准
--
-- 移动走 VoxelCharacterController（能站在冻结碎块、桥、台阶上，被墙挡住）。
-- 相机：越肩第三人称（ThirdPersonCamera 库），鼠标控制 yaw / pitch；屏幕中心十字准星即瞄准方向。
-- 瞄准射线：从相机出发打向世界（跳过诺米自己），得到命中点；施法起点是诺米右手。
-- 骑龙时由 DragonRide 接管（本模块只负责步行状态，DragonRide.Update 的 free 模式被替换）。
-- ====================================================================

require "urhox-libs.Camera.ThirdPersonCamera"
local BlockCharacter = require("game.BlockCharacter")
local NomiVoxelData = require("game.NomiVoxelData")
local TimeObject = require("ruins.TimeObject")

local M = {}

local WALK, RUN = 4.2, 7.2
local JUMP = 6.4
local AIR_CONTROL = 0.35

local function Clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
local function WrapDeg(a)
    while a > 180 do a = a - 360 end
    while a < -180 do a = a + 360 end
    return a
end

---@class NomiController
---@field node Node
---@field nomi table
---@field cc VoxelCharacterController
---@field cam ThirdPersonCameraInstance
---@field yaw number
---@field camYaw number
---@field camPitch number
---@field aimMask integer
---@field castSocket Node
local N = {}
N.__index = N

---@param scene Scene
---@param world VoxelPhysicsWorld
function M.New(scene, world, spawn, spawnYaw)
    local self = setmetatable({}, N)
    self.scene, self.world = scene, world
    self.node = scene:CreateChild("Nomi")
    self.node.worldPosition = spawn
    self.nomi = BlockCharacter.CreateVoxel(self.node, NomiVoxelData, BlockCharacter.SLENDER)
    -- 体素模型手掌中心约 (19,33,-.75)，肩轴 (9,46,-1.5)。
    -- 按同一份 unit/修长体型变换挂在手骨上，不用肩部向下猜 0.45m。
    local socket = self.nomi.bones.arm_right:CreateChild("SpellPalm")
    local shape = BlockCharacter.SLENDER.widen
    socket.position = Vector3(10 * shape.x, -13, .75 * shape.z) * NomiVoxelData.unit
    self.castSocket = socket
    local cc = self.node:CreateComponent("VoxelCharacterController")
    cc.height = 1.65
    cc.radius = 0.32
    cc.supportRadius = 0.26
    cc.stepHeight = 0.55
    cc.maxSlopeAngle = 55
    cc.mass = 55
    cc.maxStrength = 60
    -- 非默认 mask 启用双向过滤，让飞行台阶的 mask=0 真正不阻挡角色。
    cc.collisionMask = 0xffffffff & ~2
    self.cc = cc
    self.yaw = spawnYaw or 0
    self.camYaw = spawnYaw or 0
    self.camPitch = 12
    self.speed = 0
    self.vel = Vector3(0, 0, 0)
    self.enabled = true
    self.cam = ThirdPersonCamera.Create(scene, {
        modes = {
            normal = { distance = 4.6, offset = Vector3(0.55, 1.65, 0), fov = 55.0 },
            aim = { distance = 3.0, offset = Vector3(0.75, 1.6, 0), fov = 46.0 },
            mounted = { distance = 13.0, offset = Vector3(0, 3.2, 0), fov = 55.0 },
            far = { distance = 26.0, offset = Vector3(0, 6.0, 0), fov = 55.0 },
        },
        transitionSpeed = 6.0,
        farClip = 600.0,
    })
    self.camTarget = scene:CreateChild("CamTarget")
    self.camTarget.position = spawn
    self.node.rotation = Quaternion(self.yaw, Vector3.UP)
    print(string.format("NomiController: spawn %.1f %.1f %.1f", spawn.x, spawn.y, spawn.z))
    return self
end

function N:Camera() return self.cam:GetCamera() end
function N:CameraNode() return self.cam:GetNode() end
function N:Position() return self.node.worldPosition end

-- 右手掌心位置；与骨骼动画和角色世界变换保持一致。
function N:HandPos()
    return self.castSocket.worldPosition
end

-- 单次 E/Q 也先面向目标并摆好手臂，再读取同帧掌心发射点。
---@param aim table
function N:PrepareCast(aim)
    local target = aim.hit and aim.pos or aim.far --[[@as Vector3]]
    local delta = target - self.node.worldPosition
    if delta.x * delta.x + delta.z * delta.z > .001 then
        self.yaw = math.deg(math.atan(delta.x, delta.z))
        self.node.worldRotation = Quaternion(self.yaw, Vector3.UP)
    end
    self.nomi.armed = 1
    self:Animate(0, true)
end

-- 鼠标视角
function N:Look(dx, dy, sens)
    self.camYaw = self.camYaw + dx * sens
    self.camPitch = Clamp(self.camPitch + dy * sens, -55, 70)
end

-- 移动输入（f, r ∈ [-1,1]）
function N:Move(dt, f, r, run, jump, aiming)
    local cc = self.cc
    local rad = math.rad(self.camYaw)
    local fwd = Vector3(math.sin(rad), 0, math.cos(rad))
    local right = Vector3(math.cos(rad), 0, -math.sin(rad))
    local dir = fwd * f + right * r
    local moveAmount = math.min(1,dir:Length())
    local moving = dir:LengthSquared() > 0.01
    if moving then dir = dir:Normalized() end
    local target = moving and ((run and not aiming) and RUN or (aiming and WALK * 0.6 or WALK)) or 0
    local onGround = cc.onGround
    local want = dir * target * moveAmount
    local k = onGround and (1 - math.exp(-12 * dt)) or (1 - math.exp(-12 * AIR_CONTROL * dt))
    self.vel = self.vel:Lerp(want, k)
    cc.desiredVelocity = Vector3(self.vel.x, 0, self.vel.z)
    if jump and onGround then cc:Jump(JUMP) end
    -- 朝向：瞄准时面朝相机方向；否则面朝移动方向
    local wantYaw = self.yaw
    if aiming then wantYaw = self.camYaw
    elseif moving then wantYaw = math.deg(math.atan(dir.x, dir.z)) end
    self.yaw = self.yaw + WrapDeg(wantYaw - self.yaw) * (1 - math.exp(-14 * dt))
    self.node.rotation = Quaternion(self.yaw, Vector3.UP)
    self.speed = Vector3(self.vel.x, 0, self.vel.z):Length()
    self.onGround = onGround
    -- 掉进深谷：传送回最近的安全点
    if self.node.worldPosition.y < -24 and self.safePos ~= nil then
        cc:Teleport(self.safePos)
        self.vel = Vector3(0, 0, 0)
    end
    if onGround and self.node.worldPosition.y > -5 then
        self.safeT = (self.safeT or 0) + dt
        if self.safeT > 1.0 then self.safeT = 0; self.safePos = self.node.worldPosition end
    end
end

function N:Animate(dt, casting)
    self.nomi:Update(dt, { moveSpeed = self.onGround and self.speed or 0, onGround = self.onGround, armed = casting, aiming = casting,
        aimPitch = self.camPitch })
end

function N:UpdateCamera(dt, mode, followNode)
    self.cam:SetMode(mode or "normal")
    local tgt = followNode or self.node
    -- 相机目标平滑跟随（避免台阶上颠）
    local p = tgt.worldPosition
    local cur = self.camTarget.position
    local k = 1 - math.exp(-14 * dt)
    local ny = cur.y + (p.y - cur.y) * (1 - math.exp(-8 * dt))
    self.camTarget.position = Vector3(cur.x + (p.x - cur.x) * k, ny, cur.z + (p.z - cur.z) * k)
    self.cam:Update(dt, self.camTarget, self.camYaw, self.camPitch)
    -- 体素世界里的相机防穿墙（库只查 Bullet PhysicsWorld，这里补一条体素射线）
    local cn = self.cam:GetNode()
    local aimPoint = self.camTarget.position + Quaternion(self.camYaw, Vector3.UP) * ((mode == "aim") and Vector3(0.75, 1.6, 0) or Vector3(0.55, 1.65, 0))
    if mode == "mounted" then aimPoint = self.camTarget.position + Vector3(0, 3.2, 0) end
    local d = cn.position - aimPoint
    local len = d:Length()
    if len > 0.3 then
        local hit = self.world:RaycastSingle(Ray(aimPoint, d * (1.0 / len)), len)
        if hit.hit and hit.distance < len then
            cn.position = aimPoint + d * (math.max(0.4, hit.distance - 0.3) / len)
        end
    end
end

-- 瞄准只查询实心体素，不把动态碎块的近似凸包当作可见表面。
-- 相机 ---- 中心射线 ---- 最近实心格（墙也会遮挡）
--                  \\ 半径 0.12m 容错，仅接受无遮挡的可操作目标
-- 回溯的 mask=0 体积仍可被 Grid 选中，但不会阻挡角色。
---@param ray Ray
---@param maxDist number
function N:AimRay(ray, maxDist)
    local hit = self.world:RaycastGridSingle(ray, maxDist, self.aimMask or 0xffffffff)
    local res = { hit = false, dir = ray.direction, origin = ray.origin, mask = self.aimMask or 0xffffffff,
        far = ray.origin + ray.direction * maxDist }
    local obj = hit.hit and TimeObject.FindByVolume(hit.volume) or nil
    local actionable = hit.hit and (obj ~= nil or hit.volume.destructible)
    if not actionable then
        -- 容错不得穿过中心射线上的墙；命中点还需单独检查可见性。
        local reach = hit.hit and math.min(maxDist, hit.distance + 0.12) or maxDist
        local near = self.world:SphereCast(Sphere(ray.origin, 0.12), ray.direction, reach, self.aimMask or 0xffffffff)
        if near.hit then
            local owner = TimeObject.FindByVolume(near.volume)
            if owner ~= nil or near.volume.destructible then
                local delta = near.position - ray.origin --[[@as Vector3]]
                local length = delta:Length()
                if length > 0.001 then
                    local visible = self.world:RaycastGridSingle(Ray(ray.origin, delta / length), length + 0.08, self.aimMask or 0xffffffff)
                    if visible.hit and (visible.volume == near.volume or (owner ~= nil and TimeObject.FindByVolume(visible.volume) == owner)) then
                        hit = visible
                        obj = owner
                        res.assisted = true
                    end
                end
            end
        end
    end
    if hit.hit then
        res.hit, res.pos, res.normal, res.volume = true, hit.position, hit.normal, hit.volume
        res.object = obj
        res.breakable = obj ~= nil and obj.canShatter or hit.volume.destructible
    end
    return res
end

-- 全屏中心准星对应相机的世界正前方，不依赖逆投影的深度约定。
-- 保留近裁剪面起点，不跳过相机与角色之间可见的物件。
function N:Aim(maxDist)
    local camera, node = self:Camera(), self:CameraNode()
    local direction = node.worldDirection:Normalized()
    if not self.aimLogged then
        self.aimLogged = true
        local projected = camera:GetScreenRay(.5, .5)
        print(string.format("RuinsAim: center-forward dot=%.4f viewport=%dx%d dpr=%.2f",
            projected.direction:DotProduct(direction), graphics:GetWidth(), graphics:GetHeight(), graphics:GetDPR()))
    end
    return self:AimRay(Ray(node.worldPosition + direction * camera.nearClip, direction), maxDist)
end

function N:SetVisible(v) self.node:SetDeepEnabled(v) end

return M
