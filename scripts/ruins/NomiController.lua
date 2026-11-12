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
    local cc = self.node:CreateComponent("VoxelCharacterController")
    cc.height = 1.65
    cc.radius = 0.32
    cc.supportRadius = 0.26
    cc.stepHeight = 0.55
    cc.maxSlopeAngle = 55
    cc.mass = 55
    cc.maxStrength = 60
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

-- 右手位置（施法起点）
function N:HandPos()
    local arm = self.nomi.bones.arm_right
    if arm ~= nil then return arm.worldPosition + arm.worldRotation * Vector3(0, -0.45, 0) end
    return self.node.worldPosition + Vector3(0, 1.2, 0)
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
    local moving = dir:LengthSquared() > 0.01
    if moving then dir = dir:Normalized() end
    local target = moving and ((run and not aiming) and RUN or (aiming and WALK * 0.6 or WALK)) or 0
    local onGround = cc.onGround
    local want = dir * target
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
        aimPitch = -self.camPitch })
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

-- 屏幕中心瞄准：返回 { hit, pos, normal, volume, dir, far }
function N:Aim(maxDist)
    local cam = self:Camera()
    local ray = cam:GetScreenRay(0.5, 0.5)
    -- 射线起点挪到诺米身前（避免命中诺米与相机之间的东西）
    local toNomi = (self.node.worldPosition + Vector3(0, 1.2, 0) - ray.origin):DotProduct(ray.direction)
    local start = ray.origin + ray.direction * math.max(0, toNomi)
    local hit = self.world:RaycastSingle(Ray(start, ray.direction), maxDist)
    local res = { hit = false, dir = ray.direction, far = start + ray.direction * maxDist }
    if hit.hit then
        res.hit = true
        res.pos = hit.position
        res.normal = hit.normal
        res.volume = hit.volume
    end
    return res
end

function N:SetVisible(v) self.node:SetDeepEnabled(v) end

return M
