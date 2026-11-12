-- 游戏独占鼠标捕获状态；平台 API 和时钟由宿主传入，便于模拟浏览器异步回报。
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
    self.blocked = false
    self.retryAt = 0.0
    self.deadline = 0.0
    self.attackArmed = false
    self.skipLook = false
end

function M:IsCaptured() return self.state == "captured" end
function M:CanAttack() return self:IsCaptured() and self.attackArmed end

function M:CanLook()
    if self.skipLook then
        self.skipLook = false
        return false
    end
    return self:IsCaptured()
end

function M:Confirm()
    if self:IsCaptured() then return end
    self.state = "captured"
    self.attackArmed = false
    self.skipLook = true
    self.port.changed(true, "captured")
end

-- 先更新状态，再调用平台释放，避免同步 MouseModeChanged 重入。
function M:Release(reason)
    local wasActive = self.state ~= "free"
    self.state = "free"
    self.attackArmed = false
    self.skipLook = true
    self.retryAt = self.port.now() + (self.port.web and not self.port.softCapture and 2.0 or 0.0)
    self.port.release()
    if wasActive then self.port.changed(false, reason) end
end

function M:SetBlocked(blocked)
    if self.blocked == blocked then return end
    self.blocked = blocked
    if blocked then self:Release("panel") end
end

function M:Click(overUI)
    if self.blocked or overUI or not self.port.focused() then return end
    if self.state ~= "free" or self.port.now() < self.retryAt then return end
    -- Web 文档不支持 Pointer Lock 时采用逻辑接管，绝不先请求再捕获异常。
    if self.port.softCapture then
        self.port.release()
        self:Confirm()
        return
    end
    -- MM_RELATIVE 的模式回报可能早于浏览器真正授予 Pointer Lock。
    self.state = "pending"
    self.deadline = self.port.now() + 4.0
    self.attackArmed = false
    self.port.request()
    if self.port.captured() then self:Confirm() end
end

function M:ModeChanged(relative, locked)
    if self.port.softCapture then return end
    local captured = self.port.web and locked or (not self.port.web and relative)
    if captured then
        if self.blocked or not self.port.focused() or self.state == "free" then
            -- 面板打开、失焦或请求已撤销后才到达的成功回报不能重新接管鼠标。
            self.port.release()
        else
            self:Confirm()
        end
    elseif self:IsCaptured() then
        -- 这里只同步状态；不在通知回调里再写模式，避免事件递归。
        self.state = "free"
        self.attackArmed = false
        self.skipLook = true
        self.retryAt = self.port.now() + (self.port.web and not self.port.softCapture and 2.0 or 0.0)
        self.port.changed(false, "unlocked")
    end
end

function M:Update(leftDown)
    if not self.port.focused() then
        if self.state ~= "free" then self:Release("focus") end
        return
    end
    if self.state == "pending" then
        if self.port.captured() then
            self:Confirm()
        elseif self.port.now() >= self.deadline then
            self:Release("timeout")
        end
    elseif self:IsCaptured() and not self.port.softCapture and not self.port.captured() then
        self:ModeChanged(false, false)
    end
    -- 恢复锁定的那次点击只负责恢复；松开后下一次点击才能施法。
    if self:IsCaptured() and not leftDown then self.attackArmed = true end
end

return M
