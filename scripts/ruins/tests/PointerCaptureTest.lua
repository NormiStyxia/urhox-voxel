-- 通过 Runtime 的 -validate-test 加载；模拟浏览器异步回报，不冒充浏览器实测。
local Capture = require("ruins.PointerCapture")
local V = _G["V"]

local function Fixture(web, softCapture)
    local env = { now = 10.0, focus = true, locked = false, requests = 0, releases = 0 }
    local capture = Capture.New({
        web = web,
        softCapture = softCapture,
        now = function() return env.now end,
        focused = function() return env.focus end,
        captured = function() return env.locked end,
        request = function()
            env.requests = env.requests + 1
            if not web then env.locked = true end
        end,
        release = function() env.releases = env.releases + 1; env.locked = false end,
        changed = function(locked, reason) env.last = reason end,
    })
    return capture, env
end

V.atFrame(5, function()
    local p, e = Fixture(true)
    p:Click(true)
    V.assert(e.requests == 0, "UI 点击不能请求捕获")
    e.focus = false
    p:Click(false)
    V.assert(e.requests == 0, "失焦点击不能请求捕获")
    e.focus = true
    p:Click(false)
    V.assert(e.requests == 1 and p.state == "pending", "有效点击发起一次异步请求")
    p:ModeChanged(true, false)
    V.assert(p.state == "pending", "Web 相对模式通知不等于浏览器已锁定")
    for i = 1, 10 do p:Click(false) end
    V.assert(e.requests == 1, "pending 期间连续点击不重复请求")
    e.now = 12.0
    p:Update(true)
    V.assert(p.state == "pending", "超过旧 1.2 秒阈值仍允许异步成功")
    e.locked = true
    p:ModeChanged(true, true)
    V.assert(p:IsCaptured(), "浏览器成功回报进入捕获状态")
    V.assert(not p:CanLook(), "重锁首帧丢弃鼠标跳变量")
    V.assert(p:CanLook(), "后续帧允许相对视角")
    p:Update(true)
    V.assert(not p:CanAttack(), "重锁点击不能蓄力施法")
    p:Update(false)
    V.assert(p:CanAttack(), "松开重锁点击后恢复施法")
    local releases = e.releases
    e.locked = false
    p:ModeChanged(false, false)
    V.assert(not p:IsCaptured(), "浏览器自主解锁同步状态")
    V.assert(e.releases == releases, "解锁通知不反向切模式造成递归")
    p:Click(false)
    V.assert(e.requests == 1, "浏览器 ESC 冷却期不重新请求")
    e.now = 14.1
    p:Click(false)
    V.assert(e.requests == 2, "冷却结束允许点击重锁")
    e.locked = true
    p:ModeChanged(true, true)
    p:SetBlocked(true)
    V.assert(not p:IsCaptured() and not e.locked, "F10 面板立即释放捕获")
    e.now = 20.0
    p:Click(false)
    V.assert(e.requests == 2, "面板内点击不会重锁")
    e.locked = true
    p:ModeChanged(true, true)
    V.assert(not e.locked and not p:IsCaptured(), "面板打开后迟到的成功回报被释放")
    p:SetBlocked(false)
    V.assert(not p:IsCaptured(), "关闭面板不会无手势自动重锁")
    p:Click(false)
    e.now = 24.1
    p:Update(false)
    V.assert(p.state == "free" and e.last == "timeout", "拒绝请求超时后安全恢复")
    local requests = e.requests
    e.now = 30.0
    p:Update(false)
    V.assert(e.requests == requests, "请求失败后不自动循环重试")
    p:Click(false)
    e.focus = false
    p:Update(false)
    V.assert(p.state == "free" and e.last == "focus", "请求中失焦也会取消")
    e.focus = true
    e.locked = true
    p:ModeChanged(true, true)
    V.assert(not e.locked and not p:IsCaptured(), "取消请求后迟到的回报不能抢回鼠标")

    local soft, se = Fixture(true, true)
    soft:Click(false)
    V.assert(soft:IsCaptured() and not se.locked, "网页兼容模式无需浏览器锁定即可继续游戏")
    V.assert(se.requests == 0, "首次点击不调用 Pointer Lock")
    soft:Update(true)
    V.assert(not soft:CanAttack(), "兼容模式首次点击不会施法")
    soft:Update(false)
    V.assert(soft:CanAttack(), "兼容模式松开后允许左键施法")
    soft:ModeChanged(false, false)
    V.assert(soft:IsCaptured(), "MM_FREE 模式通知不误清除逻辑接管")
    for i = 1, 20 do
        soft:Release("escape")
        soft:Click(false)
        V.assert(soft:IsCaptured() and se.requests == 0, "兼容模式反复继续始终零锁定请求 " .. i)
    end
    soft:SetBlocked(true)
    soft:Click(false)
    V.assert(not soft:IsCaptured() and se.requests == 0, "兼容模式调试面板阻止视角接管")
    soft:SetBlocked(false)
    se.focus = false
    soft:Click(false)
    V.assert(not soft:IsCaptured(), "兼容模式失焦不接管")
    se.focus = true
    soft:Click(false)
    se.focus = false
    soft:Update(false)
    V.assert(not soft:IsCaptured() and se.requests == 0, "兼容模式失焦释放且不请求锁定")

    local d, de = Fixture(false)
    d:Click(false)
    V.assert(d:IsCaptured(), "桌面根据相对模式立即捕获")
    d:ModeChanged(true, false)
    V.assert(d:IsCaptured(), "桌面不误用 Web 的 MouseLocked 布尔值")
    for i = 1, 12 do
        d:Release("escape")
        V.assert(not d:IsCaptured() and not de.locked, "桌面 ESC 释放循环 " .. i)
        d:Click(false)
        V.assert(d:IsCaptured(), "桌面点击恢复循环 " .. i)
    end
    de.focus = false
    d:Update(false)
    V.assert(not d:IsCaptured(), "桌面失焦释放")

    -- 实际场景接线：ESC、F10 与右键均走同一套入口。
    local function Key(key)
        local data = VariantMap()
        data["Key"] = key
        Ruins_HandleKeyDown("KeyDown", data --[[@as KeyDownEventData]])
    end
    Key(KEY_ESCAPE)
    V.assert(input.mouseMode == MM_FREE and input.mouseVisible, "场景 ESC 确实释放原生鼠标")
    local button = VariantMap()
    button["Button"] = MOUSEB_RIGHT
    Ruins_HandleMouseDown("MouseButtonDown", button --[[@as MouseButtonDownEventData]])
    V.assert(input.mouseMode == MM_FREE, "场景右键不会重新锁定")
    local scene = _G["RUINS"]
    scene.ToggleDebugPanel()
    V.assert(scene.debugOn and input.mouseMode == MM_FREE, "场景打开 F10 面板保持自由鼠标")
    scene.ToggleDebugPanel()
    V.assert(not scene.debugOn and input.mouseMode == MM_FREE, "场景关闭 F10 面板等待手势")
    if _G["POINTER_WEB_TEST"] then
        -- 场景从启动时即使用 Web 配置；任何 MM_RELATIVE 请求都会让断言失败。
        local realInput = input
        local requests = 0
        local mock = { focus = true, minimized = false, mouseMode = MM_FREE, mouseVisible = true }
        function mock:SetMouseMode(mode)
            if mode == MM_RELATIVE then
                requests = requests + 1
                error("WrongDocumentError: test document cannot grant pointer lock")
            end
            self.mouseMode = mode
        end
        function mock:SetMouseVisible(visible) self.mouseVisible = visible end
        function mock:SetMouseGrabbed(grabbed) self.mouseGrabbed = grabbed end
        function mock:IsMouseLocked() return false end
        local ok, err = pcall(function()
            _G["input"] = mock
            local left = VariantMap()
            left["Button"] = MOUSEB_LEFT
            local escape = VariantMap()
            escape["Key"] = KEY_ESCAPE
            for i = 1, 20 do
                Ruins_HandleMouseDown("MouseButtonDown", left --[[@as MouseButtonDownEventData]])
                Ruins_HandleKeyDown("KeyDown", escape --[[@as KeyDownEventData]])
            end
        end)
        _G["input"] = realInput
        V.assert(ok, "实际 Web 场景点击不会调用无效文档锁定接口：" .. tostring(err))
        V.assert(requests == 0 and mock.mouseMode == MM_FREE and mock.mouseVisible,
            "实际 Web 场景反复点击与 ESC 始终零 Pointer Lock 请求")
    end
    V.finish()
end)
