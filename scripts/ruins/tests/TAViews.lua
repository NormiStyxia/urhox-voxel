-- 只由 -validate-test 加载：技术美术巡检用的固定机位截图与渲染统计。
-- 正常主循环继续运行（昼夜、天空捕获、云），只在 PostUpdate 之后覆盖相机，
-- 每个机位锁定时刻并等待环境捕获（分帧约 9 帧）完成，再由脚本读回后备缓冲。
-- -ta-set=ruins|home|all 选择机位组；-ta-out=<前缀> 指定输出文件名前缀（写入存档根目录）。
-- Web 不启用真实体积雾，这里同样关闭，让桌面软件渲染的画面接近 Web。
local V = _G["V"]
local set, out = "ruins", "ta_"
for _, a in ipairs(GetArguments()) do
    local s = a:match("^%-ta%-set=(.+)$"); if s then set = s end
    local o = a:match("^%-ta%-out=(.+)$"); if o then out = o end
end
local R = 6.1 -- RING_Y 附近
local HX, HB = 720, 6
local VIEWS = {
    ruins = {
        { name = "gate_noon", hour = 12, pos = Vector3(4, R + 2.2, -74), look = Vector3(0, R + 1, -40) },
        { name = "overview_noon", hour = 11, pos = Vector3(55, 42, -85), look = Vector3(0, 0, 0) },
        { name = "court_noon", hour = 12, pos = Vector3(-12, R + 3.5, -24), look = Vector3(0, 1.5, 4) },
        { name = "colonnade_dusk", hour = 17.6, pos = Vector3(18, R + 1.8, -18), look = Vector3(-5, R + 2, 12) },
        { name = "overview_dusk", hour = 17.9, pos = Vector3(-60, 30, -70), look = Vector3(0, 0, 0) },
        { name = "court_night", hour = 22, pos = Vector3(-12, R + 3.5, -24), look = Vector3(0, 1.5, 4) },
        { name = "cliff_noon", hour = 13, pos = Vector3(70, -4, -95), look = Vector3(0, -6, -20) },
        { name = "ground_close", hour = 15, pos = Vector3(3, R + 1.2, -66), look = Vector3(1.5, R, -61) },
        { name = "wall_foot", hour = 10, pos = Vector3(-14, R + 1.4, -58), look = Vector3(-9.5, R + 0.8, -50) },
    },
    rim = {
        { name = "overview_noon", hour = 11, pos = Vector3(55, 42, -85), look = Vector3(0, 0, 0) },
        { name = "rim_close", hour = 14, pos = Vector3(-62, R + 6, -48), look = Vector3(-48, R - 1, -30) },
        { name = "cliff_noon", hour = 13, pos = Vector3(70, -4, -95), look = Vector3(0, -6, -20) },
    },
    r3 = {
        { name = "overview_noon", hour = 11, pos = Vector3(55, 42, -85), look = Vector3(0, 0, 0) },
        { name = "court_night", hour = 22, pos = Vector3(-12, R + 3.5, -24), look = Vector3(0, 1.5, 4) },
        { name = "home_night", hour = 21.5, pos = Vector3(HX + 5, HB + 2.2, -13), look = Vector3(HX - 2, HB + 2, 6) },
    },
    detail = {
        { name = "wall_foot", hour = 10, pos = Vector3(-14, R + 1.4, -58), look = Vector3(-9.5, R + 0.8, -50) },
        { name = "ground_close", hour = 15, pos = Vector3(3, R + 1.2, -66), look = Vector3(1.5, R, -61) },
        { name = "gate_noon", hour = 12, pos = Vector3(4, R + 2.2, -74), look = Vector3(0, R + 1, -40) },
        { name = "overview_noon", hour = 11, pos = Vector3(55, 42, -85), look = Vector3(0, 0, 0) },
        { name = "court_noon", hour = 12, pos = Vector3(-12, R + 3.5, -24), look = Vector3(0, 1.5, 4) },
    },
    night = {
        { name = "n_court_night", hour = 22, pos = Vector3(-12, R + 3.5, -24), look = Vector3(0, 1.5, 4) },
        { name = "n_court_night2", hour = 22.01, pos = Vector3(-12, R + 3.5, -24), look = Vector3(0, 1.5, 4) },
        { name = "n_court_noon", hour = 12, pos = Vector3(-12, R + 3.5, -24), look = Vector3(0, 1.5, 4) },
    },
    home = {
        { name = "home_overview", hour = 11, pos = Vector3(HX + 28, HB + 20, -36), look = Vector3(HX, HB, 0) },
        { name = "home_house", hour = 15, pos = Vector3(HX + 5, HB + 2.2, -13), look = Vector3(HX - 2, HB + 2, 6) },
        { name = "home_pond_dusk", hour = 17.8, pos = Vector3(HX - 2, HB + 1.8, -16), look = Vector3(HX - 9, HB, -2) },
        { name = "home_night", hour = 21.5, pos = Vector3(HX + 5, HB + 2.2, -13), look = Vector3(HX - 2, HB + 2, 6) },
    },
    house = {
        { name = "house_aerial", stage = 3, hour = 15, pos = Vector3(HX + 16, HB + 15, -24), look = Vector3(HX - 3, HB + 4, 6) },
        { name = "house_front", stage = 3, hour = 15, pos = Vector3(HX - 8.5, HB + 4, -12), look = Vector3(HX - 8.5, HB + 6, 10) },
        { name = "house_front2", stage = 2, hour = 15, pos = Vector3(HX - 8.5, HB + 4, -12), look = Vector3(HX - 8.5, HB + 6, 10) },
        { name = "house_corner", stage = 3, hour = 10, pos = Vector3(HX + 7, HB + 3.5, -8), look = Vector3(HX - 8, HB + 6, 10) },
        { name = "house_back", stage = 3, hour = 15, pos = Vector3(HX + 4, HB + 9, 26), look = Vector3(HX - 8, HB + 5, 10) },
        { name = "house_stair", stage = 3, hour = 15, pos = Vector3(HX + 9, HB + 7, 23), look = Vector3(HX - 3, HB + 5, 13) },
        { name = "house_glass", stage = 3, hour = 16, pos = Vector3(HX - 11, HB + 2.2, 2.5), look = Vector3(HX - 13, HB + 2.4, 10) },
        { name = "house_night", stage = 3, hour = 21.5, pos = Vector3(HX - 8.5, HB + 4, -12), look = Vector3(HX - 8.5, HB + 6, 10) },
        { name = "house_front1", stage = 1, hour = 15, pos = Vector3(HX + 7, HB + 3.5, -8), look = Vector3(HX - 8, HB + 4, 10) },
        { name = "house_inside", stage = 3, hour = 15, pos = Vector3(HX - 1.9, HB + 2.6, 14), look = Vector3(HX - 15, HB + 1.6, 8) },
    },
}
local views = VIEWS[set]
if set == "all" then
    views = {}
    for _, v in ipairs(VIEWS.ruins) do views[#views + 1] = v end
    for _, v in ipairs(VIEWS.home) do views[#views + 1] = v end
end
views = views or VIEWS.ruins
local WAIT = 14
for _, a in ipairs(GetArguments()) do local w = a:match("^%-ta%-wait=(%d+)$"); if w then WAIT = math.tointeger(tonumber(w)) or 14 end end
local index, wait, pendingName = 0, 0, nil
local frame = 0
local homeBuilt = false
local game

local function Apply(v)
    local cn = game.nomiCtl:CameraNode()
    cn.worldPosition = v.pos
    cn:LookAt(v.look, Vector3.UP)
end

local function BuildHome()
    if homeBuilt then return end
    local Home = require("ruins.HomeIsland")
    local Terrain = require("ruins.RuinsTerrain")
    local job = Home.BeginBuild(game.world, game.scene, game.dayNight)
    local done, err = false, nil
    for _ = 1, 100000 do
        done, err = job:Step()
        if done or err then break end
    end
    print("TAViews: home built " .. tostring(done) .. " " .. tostring(err))
    Terrain.home = Home
    require("ruins.RenderBudget").Apply(game.scene)
    game.region = "home"
    homeBuilt = true
    -- 主循环用诺米位置驱动家园更新与云跟随；把隐藏的诺米放到家园中央。
    game.nomiCtl.cc:Teleport(Vector3(HX + 5, HB + 0.2, -12))
end

function TAViews_PostUpdate(eventType, eventData)
    Ruins_HandlePostUpdate(eventType, eventData)
    frame = frame + 1
    if pendingName then
        local dn = game.dayNight
        local c = dn.sun.color
        local info = string.format("TAViews: light %s sun=(%.2f,%.2f,%.2f) x%.2f nightK=%.2f diff=%.2f capReady=%s batches=%d primitives=%d",
            pendingName, c.r, c.g, c.b, dn.sun.brightness, dn.nightK or -1, dn.zone.envTextureDiffIntensity,
            tostring(dn.capture.ready), renderer:GetNumBatches(), renderer:GetNumPrimitives())
        local image = Image()
        local ok = graphics:TakeScreenShot(image) and image:SavePNG(out .. pendingName .. ".png")
        print(info .. " saved=" .. tostring(ok))
        pendingName = nil
    end
    local v = views[index]
    if v == nil or wait <= 0 then
        index = index + 1
        v = views[index]
        if v == nil then return end
        if v.name:find("^home") or v.name:find("^house") then BuildHome() end
        wait = WAIT
        game.dayNight.lockHour = v.hour
        game.dayNight:SetHour(v.hour)
        if v.stage then print("TAViews: stage", require("ruins.HomeIsland").SetHouseStage(v.stage)) end
        print(string.format("TAViews: view %s hour %.1f frame %d", v.name, v.hour, frame))
    end
    Apply(v)
    wait = wait - 1
    if wait == 0 then pendingName = v.name end
end

V.atFrame(4, function()
    game = _G["RUINS"]
    local Settings = require("ruins.GameSettings")
    Settings.Set("quality", "high")
    Settings.Set("volumetric", false)
    -- 隐藏诺米，避免挡住近景机位
    game.nomiCtl.node:SetDeepEnabled(false)
    local UI = require("urhox-libs/UI")
    local root = UI.GetRoot and UI.GetRoot()
    if root and root.SetVisible then root:SetVisible(false) end
    SubscribeToEvent("PostUpdate", "TAViews_PostUpdate")
    print("TAViews: armed set=" .. set .. " views=" .. #views)
end)
