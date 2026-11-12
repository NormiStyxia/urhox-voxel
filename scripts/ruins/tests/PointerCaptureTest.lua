-- 单元测试 + 实际场景输入回归；不使用 M.fake 绕过施法门禁。
local Capture = require("ruins.PointerCapture")
local V = _G["V"]

local function Fixture(web)
    local env = { now = 10.0, focus = true, locked = false, requests = 0 }
    local p = Capture.New({
        web = web,
        now = function() return env.now end,
        focused = function() return env.focus end,
        captured = function() return env.locked end,
        request = function() env.requests = env.requests + 1 end,
        release = function() env.locked = false end,
        changed = function(locked, reason) env.last = reason end,
    })
    return p, env
end

V.atFrame(5, function()
    local p, e = Fixture(true)
    p:Click(true)
    V.assert(e.requests == 0, "UI 不请求锁定")
    p:Click(false)
    V.assert(e.requests == 0 and p:IsEnabled(), "Web 首次点击只激活新画布")
    e.now = 10.1
    p:Click(false)
    V.assert(e.requests == 0, "焦点尚未稳定不请求锁定")
    e.now = 10.4
    p:Update(false)
    p:Click(false)
    V.assert(e.requests == 1 and p.state == "pending", "焦点稳定后的真实点击请求锁定")
    V.assert(p:IsEnabled(), "等待浏览器时玩法已经激活")
    p:Update(false)
    V.assert(p:CanAttack(), "等待锁定时仍可施法")
    p:ModeChanged(true, false)
    V.assert(p.state == "pending", "仅相对模式不冒充浏览器锁定成功")
    for i = 1, 10 do p:Click(false) end
    V.assert(e.requests == 1, "pending 不重复请求")
    e.now = 14.5
    p:Update(false)
    V.assert(p.state == "fallback" and p:CanAttack(), "超时兼容模式仍允许技能")
    V.assert(e.requests == 1, "失败不自动重试")
    e.now = 16.6
    p:Click(false)
    V.assert(e.requests == 2, "后续真实点击可以重试")
    e.locked = true
    p:ModeChanged(true, true)
    V.assert(p:IsCaptured() and p:IsEnabled(), "成功回报进入真正锁定")
    p:Release("escape")
    V.assert(not p:IsCaptured() and not p:IsEnabled(), "ESC 释放并暂停玩法输入")
    p:Resume()
    p:Update(false)
    V.assert(p:CanAttack() and e.requests == 2, "键盘恢复技能不需要再次申请锁定")
    p:SetBlocked(true)
    p:Resume()
    p:Click(false)
    V.assert(not p:IsEnabled() and e.requests == 2, "面板阻止输入与锁定")
    p:SetBlocked(false)
    e.focus = false
    p:Resume()
    V.assert(not p:IsEnabled(), "失焦不恢复玩法")
    local d, de = Fixture(false)
    d:Click(false)
    de.locked = true
    d:ModeChanged(true, false)
    V.assert(d:IsCaptured(), "桌面根据 relative 模式锁定")

    local realInput = input
    local scene = _G["RUINS"]
    local held, pressed = {}, {}
    local mock = { focus = true, minimized = false, mouseMode = MM_FREE, mouseVisible = true,
        mouseMove = IntVector2(0, 0), mousePosition = IntVector2(400, 300), left = false, locked = false, requests = 0 }
    function mock:SetMouseMode(mode)
        self.mouseMode = mode
        if mode == MM_RELATIVE then self.requests = self.requests + 1 end
        if mode == MM_FREE then self.locked = false end
    end
    function mock:SetMouseVisible(v) self.mouseVisible = v end
    function mock:SetMouseGrabbed(v) self.mouseGrabbed = v end
    function mock:IsMouseLocked() return self.locked end
    function mock:GetMouseButtonDown(button) return button == MOUSEB_LEFT and self.left end
    function mock:GetKeyDown(key) return held[key] == true end
    function mock:GetKeyPress(key)
        local value = pressed[key] == true
        pressed[key] = nil
        return value
    end
    local function Key(key)
        local data = VariantMap()
        data["Key"] = key
        pressed[key] = true
        Ruins_HandleKeyDown("KeyDown", data --[[@as KeyDownEventData]])
    end
    local dt = VariantMap()
    dt["TimeStep"] = 0.05
    local function Tick()
        Ruins_HandleUpdate("Update", dt --[[@as UpdateEventData]])
    end
    local ok, err = pcall(function()
        _G["input"] = mock
        local left = VariantMap()
        left["Button"] = MOUSEB_LEFT
        Ruins_HandleMouseDown("MouseButtonDown", left --[[@as MouseButtonDownEventData]])
        V.assert(mock.requests == 0, "按下鼠标不切换模式破坏拖动")
        local up = VariantMap()
        up["Button"] = MOUSEB_LEFT
        up["X"], up["Y"] = 130, 110
        up["Buttons"], up["Qualifiers"] = 0, 0
        Ruins_HandleMouseUp("MouseButtonUp", up --[[@as MouseButtonUpEventData]])
        if _G["POINTER_WEB_TEST"] then
            V.assert(mock.requests == 0, "Web 纯点击先激活")
        else
            V.assert(mock.requests == 1, "桌面纯点击松开时请求锁定")
        end
        Key(KEY_ESCAPE)
        mock.requests = 0
        -- 尚无浏览器锁定，直接按 E、Q 也必须进入真实 Cast。
        scene.caster.cool.freeze, scene.caster.cool.rewind = 0, 0
        Key(KEY_E)
        Tick()
        V.assert(scene.caster.lastCast == "freeze", "真实输入 E 在未锁定时施放冻结")
        Key(KEY_Q)
        Tick()
        V.assert(scene.caster.lastCast == "rewind", "真实输入 Q 在未锁定时施放回溯")
        V.assert(mock.requests == 0, "键盘施法无需浏览器锁定")
        scene.caster.cool.shatter = 0
        mock.left = true
        Tick()
        V.assert(scene.caster.charging, "真实左键开始碎时蓄力")
        Tick()
        V.assert(scene.caster.charge > 0, "真实输入推进蓄力")
        mock.left = false
        Tick()
        V.assert(scene.caster.lastCast == "shatter" and not scene.caster.charging, "松开左键实际释放碎时")
        -- 保持帧级 mouseMove=0，只发送真实形状的鼠标事件，覆盖此前 mock 掩盖的问题。
        mock.mouseMove = IntVector2(0, 0)
        local move = VariantMap()
        move["X"], move["Y"] = 130, 110
        move["DX"], move["DY"] = 0, 0
        local yaw = scene.nomiCtl.camYaw
        SendEvent("MouseMove", move)
        V.assert(scene.nomiCtl.camYaw == yaw, "无按下事件时不转视角")
        left["X"], left["Y"] = 100, 100
        left["Buttons"], left["Qualifiers"] = 0, 0
        SendEvent("MouseButtonDown", left)
        SendEvent("MouseMove", move)
        V.assert(math.abs(scene.nomiCtl.camYaw - yaw - 3.6) < 0.001, "相对位移和轮询按键均为零时，绝对坐标拖动仍转视角")
        V.assert(mock.requests == 0, "拖动期间没有锁定请求")
        yaw = scene.nomiCtl.camYaw
        SendEvent("MouseButtonUp", up)
        move["X"] = 150
        SendEvent("MouseMove", move)
        Tick()
        V.assert(scene.nomiCtl.camYaw == yaw, "松开事件后停止转视角且不重复应用位移")
        mock.focus = false
        SendEvent("MouseButtonDown", left)
        move["X"] = 140
        SendEvent("MouseMove", move)
        V.assert(scene.nomiCtl.camYaw ~= yaw, "引擎焦点标志滞后不阻塞已到达的拖动事件")
        local focus = VariantMap()
        focus["Focus"], focus["Minimized"] = false, false
        SendEvent("InputFocus", focus)
        yaw = scene.nomiCtl.camYaw
        move["X"] = 160
        SendEvent("MouseMove", move)
        V.assert(scene.nomiCtl.camYaw == yaw, "真正失焦事件取消拖动")
        mock.focus = true

        scene.ToggleDebugPanel()
        scene.caster.cool.freeze = 0
        scene.caster.lastCast = "shatter"
        Key(KEY_E)
        Tick()
        V.assert(scene.caster.lastCast == "shatter", "F10 面板内 E 不误施法")
        scene.ToggleDebugPanel()
        Key(KEY_E)
        Tick()
        V.assert(scene.caster.lastCast == "freeze", "关闭面板后 E 可直接恢复施法")
        Key(KEY_ESCAPE)
        V.assert(mock.mouseMode == MM_FREE and mock.mouseVisible, "实际场景 ESC 释放鼠标")
    end)
    _G["input"] = realInput
    V.assert(ok, "真实场景输入回归没有异常：" .. tostring(err))
    V.finish()
end)
