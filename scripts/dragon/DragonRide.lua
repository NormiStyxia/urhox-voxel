-- ====================================================================
-- DragonRide.lua — 玩法模式：操作诺米移动 / 跳跃，靠近龙按 F 骑上去，骑乘时操作龙；
-- 不在龙背上时龙自己在场地里溜达（先不起飞）。
--
-- 诺米：简化的运动学控制器（地面 y=0，重力 + 跳跃，不走物理世界），与龙身体做 2D 圆形推开。
-- 龙 AI：待机 ↔ 走向随机目标点（偶尔咆哮），玩家靠近或骑乘时停下。
-- 骑乘：诺米挂在龙的 saddle 挂点（胸骨背上），坐姿覆盖腿 / 臂骨骼；W 前进 A/D 转向 S 停下，
-- Space 起飞 / 上升，C 下降，F 下龙。
-- 型号：距离 / 碰撞圆按龙的尺度缩放；小号幼龙（spec.rideable = false）不能骑，
-- 无人操作时像宠物一样跟在诺米身边。
-- ====================================================================

---@class DragonRideModule
---@field fake table|nil
---@field fakePress table|nil
local M = {}

local MOUNT_RANGE = 3.6      -- 离龙胸口多远内可以骑乘（米）
local MOUNT_TIME = 0.75      -- 上龙动画时长
local WALK_SPEED, RUN_SPEED = 4.2, 7.0
local JUMP_V, GRAVITY = 7.2, 22.0
local ARENA = 62.0           -- 场地半宽（地面 140m 见方）
local RIDE_WALK_K = 1.25     -- 骑乘时龙的步行速度 = 型号默认步行速度 × 1.25（中号 2.0，W 全速约 3.2 m/s）

-- 龙身体的 2D 碰撞圆（骨骼名, 半径）：诺米不能穿过龙
local BODY_CIRCLES = {
    { "pelvis", 1.0 }, { "waist", 0.95 }, { "chest", 1.0 }, { "neck2", 0.55 }, { "head", 0.75 },
    { "tail1", 0.6 }, { "tail3", 0.5 }, { "tail5", 0.4 }, { "tail7", 0.3 },
}

-- 键盘读取（M.fake 供自动化测试 / 截图脚本注入按键；正常游戏为 nil）
local function Down(key)
    if M.fake ~= nil and M.fake[key] ~= nil then return M.fake[key] end
    return input:GetKeyDown(key)
end
local function Press(key)
    if M.fakePress ~= nil and M.fakePress[key] then M.fakePress[key] = nil return true end
    return input:GetKeyPress(key)
end

local function WrapDeg(a)
    while a > 180 do a = a - 360 end
    while a < -180 do a = a + 360 end
    return a
end
local function Clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
local function Damp(x, target, k, dt) return x + (target - x) * (1 - math.exp(-k * dt)) end
local function Smooth(t) t = Clamp(t, 0, 1) return t * t * (3 - 2 * t) end
local function LerpAngle(a, b, t) return a + WrapDeg(b - a) * t end

---@class DragonRide
---@field onMount fun()|nil
---@field onDismount fun(pos: Vector3, right: Vector3)|nil
---@field wander table|nil
---@field external boolean|nil
---@field externalGround boolean|nil
---@field aiOff boolean|nil
---@field locked boolean|nil
---@field lockedHint string|nil
local R = {}
R.__index = R

---@param T table DragonTest 模块（cam、nomi、nomiNode、rig、ctrl）
function M.New(T)
    local self = setmetatable({}, R)
    self.T = T
    self.ctrl = T.ctrl
    self.rig = T.rig
    self:BindDragon(T)
    self.nomi = T.nomi
    self.node = T.nomiNode
    self.pos = Vector3(4.5, 0, 3.0)
    self.yaw = 200.0
    self.vy = 0.0
    self.speed = 0.0
    self.onGround = true
    self.mode = "free"        -- free / mounting / mounted
    self.mountT = 0.0
    self.mountFrom = Vector3(0, 0, 0)
    self.noCollideT = 0.0
    self.hint = ""
    self.savedWalkSpeed = self.ctrl.params.walkSpeed
    -- 诺米髋高（坐姿时让髋对准鞍座）
    local hp = self.node:WorldToLocal(self.nomi.bones.leg_right.worldPosition)
    self.hipY = hp.y
    -- 龙 AI
    self.ai = { mode = "idle", timer = 2.5, target = Vector3(0, 0, 0) }
    self.node.position = self.pos
    self.node.rotation = Quaternion(self.yaw, Vector3.UP)
    return self
end

-- 换型号后重新绑定龙（保留诺米的位置与状态）
function R:BindDragon(T)
    self.ctrl = T.ctrl
    self.rig = T.rig
    local spec = self.rig.spec
    self.size = self.rig.size or 1.0
    self.rideable = spec == nil or spec.rideable ~= false
    self.pet = spec ~= nil and spec.pet == true
    self.savedWalkSpeed = self.ctrl.params.walkSpeed
    self.ai = { mode = "idle", timer = 2.5, target = Vector3(0, 0, 0) }
end

-- ---------------------------------------------------------------- 工具
function R:SaddleNode()
    return self.rig.sockets.saddle
end

function R:DragonPos()
    return self.ctrl.loco.pos
end

local function Flat(v) return Vector3(v.x, 0, v.z) end

function R:NearDragon()
    local c = self.rig.bones.chest.worldPosition
    if self.ctrl.loco.airborne or math.abs(self.pos.y-self.rig.root.worldPosition.y)>2.5 then return math.huge end
    return (Flat(c) - Flat(self.pos)):Length()
end

-- ---------------------------------------------------------------- 诺米（地面）
function R:UpdateFree(dt, camYaw)
        local f = (Down(KEY_W) and 1 or 0) - (Down(KEY_S) and 1 or 0)
    local r = (Down(KEY_D) and 1 or 0) - (Down(KEY_A) and 1 or 0)
    local rad = math.rad(camYaw)
    local fwd = Vector3(math.sin(rad), 0, math.cos(rad))
    local right = Vector3(math.cos(rad), 0, -math.sin(rad))
    local dir = fwd * f + right * r
    local moving = dir:LengthSquared() > 0.01
    local maxSpeed = Down(KEY_SHIFT) and RUN_SPEED or WALK_SPEED
    local targetSpeed = moving and maxSpeed or 0.0
    self.speed = Damp(self.speed, targetSpeed, moving and 10.0 or 12.0, dt)
    if moving then
        dir = dir:Normalized()
        local want = math.deg(math.atan(dir.x, dir.z))
        self.yaw = LerpAngle(self.yaw, want, 1 - math.exp(-14.0 * dt))
        self.moveDir = dir
    end
    local md = self.moveDir or Vector3(0, 0, 0)
    local vel = md * self.speed
    -- 跳跃
    if self.onGround and Press(KEY_SPACE) then
        self.vy = JUMP_V
        self.onGround = false
    end
    if not self.onGround then
        -- 空中保留水平速度（不再瞬间改向，可少量空中控制）
        if moving then vel = vel * 0.0 + dir * math.max(self.speed, 2.0) end
        self.vy = self.vy - GRAVITY * dt
    end
    self.pos = self.pos + Vector3(vel.x, 0, vel.z) * dt
    local y = self.pos.y + self.vy * dt
    if y <= 0 then
        y = 0
        if not self.onGround then self.onGround = true end
        self.vy = 0
    end
    self.pos = Vector3(self.pos.x, y, self.pos.z)
    -- 场地边界
    self.pos = Vector3(Clamp(self.pos.x, -ARENA, ARENA), self.pos.y, Clamp(self.pos.z, -ARENA, ARENA))
    -- 与龙身体推开
    if self.noCollideT > 0 then
        self.noCollideT = self.noCollideT - dt
    elseif self.pos.y < 3.0 then
        for _, cdef in ipairs(BODY_CIRCLES) do
            local node = self.rig.bones[cdef[1]]
            if node ~= nil then
                local c = node.worldPosition
                local dx, dz = self.pos.x - c.x, self.pos.z - c.z
                local d = math.sqrt(dx * dx + dz * dz)
                local rad2 = cdef[2] * (self.size or 1.0) + 0.3
                if d < rad2 then
                    if d < 1e-4 then dx, dz, d = 0, 1, 1 end
                    self.pos = Vector3(c.x + dx / d * rad2, self.pos.y, c.z + dz / d * rad2)
                end
            end
        end
    end
    self.node.position = self.pos
    self.node.rotation = Quaternion(self.yaw, Vector3.UP)
    self.nomi:Update(dt, { moveSpeed = self.onGround and self.speed or 0.0, onGround = self.onGround })
end

-- ---------------------------------------------------------------- 骑乘
function R:Mount()
    if self.onMount ~= nil then self.onMount() end
    self.mode = "mounting"
    self.mountT = 0.0
    self.mountFrom = self.pos
    self.mountYawFrom = self.yaw
    self.vy = 0
    self.speed = 0
    self.onGround = true
    local c = self.ctrl
    self.savedWalkSpeed = c.params.walkSpeed
    c.input.move, c.input.turn, c.input.climb, c.input.sprint = 0, 0, 0, false
    c:Request("IDLE")
end

function R:Dismount()
    local safe
    if self.resolveDismount then
        local reason
        safe,reason=self.resolveDismount()
        if not safe then
            if self.onNotice then self.onNotice(reason) end
            return false
        end
    end
    local saddle = self:SaddleNode()
    local chest = self.rig.bones.chest
    local right = chest.worldRotation * Vector3.RIGHT
    right = Vector3(right.x, 0, right.z):Normalized()
    local c = self.ctrl
    c.input.move, c.input.turn, c.input.climb, c.input.sprint = 0, 0, 0, false
    c.params.walkSpeed = self.savedWalkSpeed
    c:Request("IDLE")
    self.mode = "free"
    self.pos = safe or saddle.worldPosition
    self.yaw = c.loco.yaw
    self.vy = 4.5
    self.speed = 3.2
    self.moveDir = right
    self.onGround = false
    self.noCollideT = 0.6
    self.node.position = self.pos
    self.node.rotation = Quaternion(self.yaw, Vector3.UP)
    if self.onDismount ~= nil then self.onDismount(self.pos, right) end
end

-- 坐姿：覆盖腿 / 臂骨骼
function R:SeatPose()
    local n = self.nomi
    n:SetBone("leg_right", -58, 0, 22)
    n:SetBone("leg_left", -58, 0, -22)
    local L = self.ctrl.loco
    local wind, pull = L.wind or 0, L.pull or 0
    local hair, coat, hem = L.hairWind or 0, L.coatWind or 0, L.hemWind or 0
    local flow = L.flowYaw or 0
    -- Hips remain attached to the saddle: only the torso yields, then braces.
    n:SetBone("body", 4 + 16 * wind - 12 * pull, 0, 0)
    n:SetBone("head", -8 * wind + 4 * pull, 0, 0)
    n:SetBone("arm_right", -42 - 16 * wind + 8 * pull, 0, 8)
    n:SetBone("arm_left", -42 - 16 * wind + 8 * pull, 0, -8)
    n:SetBone("hair_back", 2 + 30 * hair, flow * .65 * hair, 0)
    n:SetBone("hair_locks", 12 * hair, flow * .4 * hair, 0)
    n:SetBone("coat_upper", 2 + 7 * coat, 0, 0)
    n:SetBone("coat_lower", 3 + 24 * hem, flow * .45 * hem, 0)
    -- These hang from coat_lower; use only a small additional local bend.
    for _, name in ipairs({"cloak_strip_r", "cloak_strip_l", "cloak_strip_b"}) do
        n:SetBone(name, 8 * hem, 0, 0)
    end
end

function R:AttachToSaddle()
    local saddle = self:SaddleNode()
    local rot = saddle.worldRotation
    self.node.worldRotation = rot
    self.node.worldPosition = saddle.worldPosition - rot * Vector3(0, self.hipY, 0)
end

function R:UpdateMount(dt)
    self.mountT = self.mountT + dt
    local s = Smooth(self.mountT / MOUNT_TIME)
    local saddle = self:SaddleNode()
    local target = saddle.worldPosition - saddle.worldRotation * Vector3(0, self.hipY, 0)
    local p = self.mountFrom:Lerp(target, s)
    p = Vector3(p.x, p.y + math.max(1.6, 0.4 * target.y) * math.sin(math.pi * s), p.z)
    self.node.worldPosition = p
    local dyaw = self.ctrl.loco.yaw
    self.yaw = LerpAngle(self.mountYawFrom, dyaw, s)
    self.node.worldRotation = Quaternion(self.yaw, Vector3.UP):Slerp(saddle.worldRotation, s)
    self.nomi:Update(dt, { moveSpeed = 0, onGround = false })
    if self.mountT >= MOUNT_TIME then
        self.mode = "mounted"
        self.ctrl.params.walkSpeed = self.savedWalkSpeed * RIDE_WALK_K
    end
end

function R:UpdateMounted(dt)
    -- F takes priority: the same frame must not also issue a flight/jump command.
    if Press(KEY_F) then self:Dismount(); return end
    local c = self.ctrl
    local L = c.loco
    c.demo = nil
    local w, stop = Down(KEY_W), Down(KEY_S)
    local a, d = Down(KEY_A), Down(KEY_D)
    c.input.move = stop and (L.airborne and -1 or 0) or (w and 1 or 0)
    c.input.turn = (d and 1 or 0) - (a and 1 or 0)
    c.input.free = true
    c.input.sprint = L.airborne and Down(KEY_SHIFT) and not stop and (c.state == "FLY" or c.state == "GLIDE")
    if c.input.sprint and c.state == "GLIDE" then c:Request("FLY") end
    c.input.climb = (Down(KEY_SPACE) and 1 or 0) - (Down(KEY_C) and 1 or 0)
    if Press(KEY_SPACE) and (not L.airborne or c.state == "GLIDE") then c:Request("FLY") end
    if Press(KEY_L) and L.airborne then c:Request("LAND") end
    if Press(KEY_G) and L.airborne then c:Request("GLIDE") end
    if Press(KEY_B) and self.T.breath ~= nil then
        if not self.T.breath:Trigger() and self.onNotice then
            self.onNotice(L.airborne and "吐息需落地施放：按 L 降落" or "吐息正在准备或收招")
        end
    end
    local busy = (c.state == "ROAR" or c.state == "TURN" or c.state == "BREATH")
    if not busy then
        if (c.input.move > 0 or c.input.turn ~= 0) then
            if c.state == "IDLE" then c:Request("WALK") end
        elseif c.state == "WALK" then
            c:Request("IDLE")
        end
    end
    -- 场地边界：走到边缘就停
    if not L.airborne and (math.abs(L.pos.x) > ARENA - 2 or math.abs(L.pos.z) > ARENA - 2) then
        L.pos = Vector3(Clamp(L.pos.x, -ARENA + 2, ARENA - 2), L.pos.y, Clamp(L.pos.z, -ARENA + 2, ARENA - 2))
    end
    self.nomi:Update(dt, { moveSpeed = 0, onGround = true })
    self:SeatPose()
    self:AttachToSaddle()
    self.pos = self.node.worldPosition
end

-- ---------------------------------------------------------------- 宠物 AI（小号幼龙）
-- 跟在诺米身边：离远了小跑追上，靠近了停下、转头看诺米，偶尔叫一声
function R:UpdatePet(dt)
    local c, ai = self.ctrl, self.ai
    local L = c.loco
    c.input.move, c.input.turn, c.input.climb, c.input.sprint, c.input.free = 0, 0, 0, false, true
    if c.demo ~= nil or L.airborne or c.state == "TAKEOFF" or c.state == "LAND" then return end
    c.params.walkSpeed = self.savedWalkSpeed
    local to = Flat(self.pos) - Flat(L.pos)
    local dist = to:Length()
    local diff = WrapDeg(math.deg(math.atan(to.x, to.z)) - L.yaw)
    -- 头一直朝诺米看
    c.look.tyaw, c.look.tpitch, c.look.timer = Clamp(diff, -50, 50), -6, 1.0
    if c.state == "ROAR" or c.state == "TURN" or c.state == "SPREAD_WINGS" then return end
    if ai.mode == "follow" then
        if dist < 1.9 then
            ai.mode, ai.timer = "idle", 1.5 + math.random() * 2.5
            c:Request("IDLE")
            return
        end
        if c.state == "IDLE" then
            if math.abs(diff) > 75 then c:Request("TURN", Clamp(diff, -135, 135)) else c:Request("WALK") end
        elseif c.state == "WALK" then
            c.input.turn = Clamp(diff / 25.0, -1, 1)
            c.input.move = (dist > 5.0) and 1 or 0 -- 离远了小跑
        end
    else
        if c.state == "WALK" then c:Request("IDLE") end
        ai.timer = ai.timer - dt
        if dist > 3.2 then
            ai.mode = "follow"
        elseif ai.timer <= 0 then
            ai.timer = 3.0 + math.random() * 4.0
            if math.abs(diff) > 60 then
                c:Request("TURN", Clamp(diff, -135, 135))
            elseif math.random() < 0.3 then
                c:Request(math.random() < 0.5 and "ROAR" or "SPREAD_WINGS")
            end
        end
    end
end

-- ---------------------------------------------------------------- 龙 AI（无人骑乘时）
function R:UpdateAI(dt)
    if self.pet then return self:UpdatePet(dt) end
    local c, ai = self.ctrl, self.ai
    local L = c.loco
    c.input.move, c.input.turn, c.input.climb, c.input.sprint, c.input.free = 0, 0, 0, false, false
    if c.demo ~= nil or L.airborne or c.state == "TAKEOFF" or c.state == "LAND" then return end
    c.params.walkSpeed = self.savedWalkSpeed
    local near = (Flat(self.pos) - Flat(L.pos)):Length() < 7.0 * math.max(1.0, self.size or 1.0)
    if near then
        -- 玩家靠近：停下来站着，方便骑乘
        if c.state == "WALK" then c:Request("IDLE") end
        ai.mode, ai.timer = "idle", math.max(ai.timer, 1.5)
        return
    end
    if c.state == "ROAR" or c.state == "TURN" or c.state == "SPREAD_WINGS" or c.state == "BREATH" then return end
    if ai.mode == "idle" then
        ai.timer = ai.timer - dt
        if ai.timer <= 0 then
            local ang = math.random() * math.pi * 2
            local wr = self.wander or { center = Vector3(0, 0, 0), min = 5, max = 13 }
            local r = wr.min + math.random() * (wr.max - wr.min)
            ai.target = wr.center + Vector3(math.sin(ang) * r, 0, math.cos(ang) * r)
            ai.mode, ai.timer = "walk", 25.0
        end
    else
        ai.timer = ai.timer - dt
        local to = ai.target - Flat(L.pos)
        local dist = to:Length()
        if dist < 2.0 or ai.timer <= 0 then
            ai.mode, ai.timer = "idle", 2.0 + math.random() * 3.5
            c:Request("IDLE")
            local r = math.random()
            local br = self.T.breath
            if r < 0.15 and br ~= nil and br:Available() then br:Trigger()
            elseif r < 0.3 then c:Request("ROAR") end
            return
        end
        local want = math.deg(math.atan(to.x, to.z))
        local diff = WrapDeg(want - L.yaw)
        if c.state == "IDLE" then
            if math.abs(diff) > 70 then
                c:Request("TURN", Clamp(diff, -135, 135))
            else
                c:Request("WALK")
            end
        elseif c.state == "WALK" then
            c.input.turn = Clamp(diff / 20.0, -1, 1)
            c.input.move = 0
        end
    end
end

-- ---------------------------------------------------------------- 总更新
function R:Update(dt, camYaw)
    if self.controlsEnabled and not self.controlsEnabled() then
        local c=self.ctrl
        c.input.move,c.input.turn,c.input.climb,c.input.sprint=0,0,0,false
        if c.state=="WALK" then c:Request("IDLE") end
        if self.mode=="mounting" then self:UpdateMount(dt) end
        return
    end
    if self.mode == "free" then
        -- external：步行由外部控制器（遗迹场景的 NomiController）负责，这里只读位置
        if self.external then
            self.pos = self.node.worldPosition
            self.onGround = self.externalGround ~= false
        else
            self:UpdateFree(dt, camYaw)
        end
        if not self.aiOff then self:UpdateAI(dt) end
        if self.locked then
            self.hint = self.lockedHint or ""
            return
        end
        local size = self.size or 1.0
        if self:NearDragon() < MOUNT_RANGE * math.max(0.6, size) and self.onGround then
            if self.rideable then
                self.hint = "按 F 骑上龙背"
                if Press(KEY_F) then self:Mount() end
            else
                self.hint = "幼龙还太小，骑不了——它会一直跟着你"
            end
        else
            local br = self.T.breath
            local bh = (br ~= nil and br:Available()) and ("   B 让龙" .. br.cfg.name) or ""
            self.hint = "WASD 移动   Space 跳跃   Shift 奔跑   靠近龙按 F 骑乘" .. bh
        end
    elseif self.mode == "mounting" then
        self.ctrl.input.move, self.ctrl.input.turn, self.ctrl.input.climb, self.ctrl.input.sprint = 0, 0, 0, false
        self:UpdateMount(dt)
        self.hint = ""
    else
        self:UpdateMounted(dt)
        local br = self.T.breath
        local bh = (br ~= nil and br:Available()) and ("  B " .. br.cfg.name) or ""
        self.hint = "骑乘中：W 前进  A/D 转向  S 刹车  Shift 空中冲刺  Space 起飞/上升  C 下降  L 降落  G 滑翔  F 落稳后下龙" .. bh
    end
end

-- 相机跟随目标
function R:CameraTarget()
    if self.mode == "free" then return self.pos + Vector3(0, 1.1, 0) end
    return self.rig.bones.chest.worldPosition + Vector3(0, 1.2, 0)
end

-- 关闭玩法模式时调用：下龙并还原参数
function R:Release()
    if self.mode ~= "free" then
        self.ctrl.params.walkSpeed = self.savedWalkSpeed
        self.ctrl.input.move, self.ctrl.input.turn, self.ctrl.input.climb, self.ctrl.input.sprint = 0, 0, 0, false
        self.mode = "free"
        self.pos = Vector3(self.ctrl.loco.pos.x + 3.0, 0, self.ctrl.loco.pos.z)
        self.vy, self.onGround = 0, true
    end
end

return M
