-- 游戏操作激活与浏览器鼠标锁定是两件事：锁定失败不能禁用技能。
local M = {}
M.__index = M

function M.New(port)
    local self = setmetatable({}, M)
    self:init(port)
    return self
end

function M:init(port)
    self.port = port
    self.state = "free"
    self.active = false
    self.blocked = false
    self.retryAt = 0.0
    self.deadline = 0.0
    self.attackArmed = false
    self.skipLook = false
    self.primed = not port.web
    self.focusSince = -1.0
end

function M:IsCaptured() return self.state == "captured" end
function M:IsEnabled() return self.active and not self.blocked end
function M:CanAttack() return self:IsEnabled() and self.attackArmed end

function M:CanLook(dragging)
    if self.skipLook then self.skipLook = false; return false end
    return self:IsEnabled() and (self:IsCaptured() or dragging == true)
end

-- 键盘操作也能激活玩法，不必先取得浏览器锁定。
function M:Resume()
    if self.blocked or not self.port.focused() then return end
    self.active = true
end

function M:Confirm()
    if self:IsCaptured() then return end
    self.state = "captured"
    self.active = true
    self.skipLook = true
    self.port.changed(true, "captured")
end

function M:Release(reason)
    local wasActive = self.active or self.state ~= "free"
    self.state = "free"
    self.active = false
    self.attackArmed = false
    self.skipLook = true
    if self.port.web then
        self.primed = false
        self.focusSince = -1.0
    end
    self.retryAt = self.port.now() + (self.port.web and 2.0 or 0.0)
    self.port.release()
    if wasActive then self.port.changed(false, reason) end
end

function M:SetBlocked(blocked)
    if self.blocked == blocked then return end
    self.blocked = blocked
    if blocked then self:Release("panel") end
end

function M:Click(overUI)
    if self.blocked or overUI then return end
    -- 首次 Web 点击只激活新画布；不把同一次点击同时用来争抢浏览器锁定。
    if self.port.web and not self.primed then
        self.primed = true
        self.active = true
        self.skipLook = true
        self.attackArmed = false
        self.focusSince = self.port.focused() and self.port.now() or -1.0
        self.retryAt = math.max(self.retryAt, self.port.now() + 0.3)
        self.port.changed(false, "activate")
        return
    end
    if not self.port.focused() then return end
    local wasActive = self.active
    self.active = true
    if not wasActive then self.attackArmed = false; self.skipLook = true end
    if self.state ~= "free" and self.state ~= "fallback" then return end
    if self.port.now() < self.retryAt then return end
    if self.port.web and (self.focusSince < 0 or self.port.now() - self.focusSince < 0.3) then return end
    self.state = "pending"
    self.deadline = self.port.now() + 4.0
    -- 必须由真实点击触发；不在 Update 或失败回调中自动重试。
    self.port.request()
    if self.port.captured() then self:Confirm() end
end

function M:ModeChanged(relative, locked)
    local captured = self.port.web and locked or (not self.port.web and relative)
    if captured then
        if self.blocked or not self.port.focused() or not self.active then
            self.port.release()
        else
            self:Confirm()
        end
    elseif self:IsCaptured() then
        self:Release("unlocked")
    end
end

function M:Update(leftDown)
    if not self.port.focused() then
        self.focusSince = -1.0
        if self.active or self.state ~= "free" then self:Release("focus") end
        return
    end
    if self.focusSince < 0 then self.focusSince = self.port.now() end
    if self.state == "pending" then
        if self.port.captured() then
            self:Confirm()
        elseif self.port.now() >= self.deadline then
            -- 浏览器拒绝时只退出锁定请求，保留玩法激活和施法能力。
            self.state = "fallback"
            self.retryAt = self.port.now() + 2.0
            self.port.release()
            self.port.changed(false, "fallback")
        end
    elseif self:IsCaptured() and not self.port.captured() then
        self:ModeChanged(false, false)
    end
    if self:IsEnabled() and not leftDown then self.attackArmed = true end
end

return M
