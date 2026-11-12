-- ====================================================================
-- RuinsHUD.lua — 遗迹场景 HUD（urhox-libs/UI）
--   左上：当前目标 / 进度        底部中央：三个法术槽（蓝金配色，冷却遮罩）
--   屏幕中心：准星（瞄准时之物件时变成金色）   底部：提示条 / 法术反馈
-- ====================================================================

local UI = require("urhox-libs/UI")

local M = {}

local BLUE = { 70, 130, 255, 255 }
local VIOLET = { 120, 100, 255, 255 }
local GOLD = { 255, 196, 90, 255 }
local INK = { 10, 16, 34, 200 }

---@type Label
local objLabel = nil
---@type Label
local objSub = nil
---@type Label
local hintLabel = nil
---@type Label
local msgLabel = nil
---@type Label
local targetLabel = nil
---@type Panel
local crossPanel = nil
---@type Panel
local msgPanel = nil
---@type Label
local clockLabel = nil
local lastClock = nil
local slots = {}
local ready = false

local function Slot(sp, keyText)
    local cdMask = UI.Panel { position = "absolute", left = 0, right = 0, bottom = 0, height = 0,
        backgroundColor = { 0, 0, 0, 150 }, borderRadius = 10, pointerEvents = "none" }
    local col = { math.floor(sp.color.r * 255), math.floor(sp.color.g * 255), math.floor(sp.color.b * 255), 255 }
    local frame = UI.Panel {
        width = 64, height = 64, borderRadius = 12, borderWidth = 2, borderColor = { col[1], col[2], col[3], 200 },
        backgroundGradient = { direction = "to-bottom", from = { 22, 34, 72, 230 }, to = { 10, 14, 34, 230 } },
        alignItems = "center", justifyContent = "center",
        children = {
            UI.Label { text = sp.icon, fontSize = 24, fontColor = col, flexShrink = 1 },
            UI.Label { text = sp.name, fontSize = 11, fontColor = { 220, 230, 255, 255 }, marginTop = 0, flexShrink = 1 },
            UI.Panel { position = "absolute", top = -16, left = 0, right = 0, alignItems = "center", children = {
                UI.Label { text = keyText, fontSize = 11, fontColor = GOLD } } },
            cdMask,
        },
    }
    slots[sp.id] = { frame = frame, mask = cdMask, col = col, cd = sp.cooldown }
    return frame
end

---@param spells table[]
function M.Build(spells)
    if not ready then
        UI.Init({ theme = "default-dark", scale = UI.Scale.DEFAULT })
        ready = true
    end
    slots = {}
    objLabel = UI.Label { text = "", fontSize = 16, fontWeight = "bold", fontColor = GOLD }
    objSub = UI.Label { text = "", fontSize = 12, fontColor = { 200, 215, 245, 255 }, whiteSpace = "normal", width = 300 }
    local objPanel = UI.Panel {
        position = "absolute", top = 16, left = 16, paddingTop = 10, paddingBottom = 10, paddingLeft = 14, paddingRight = 14,
        backgroundColor = INK, borderRadius = 10, borderWidth = { left = 3 }, borderColor = BLUE, pointerEvents = "none",
        children = {
            UI.Label { text = "时之遗迹", fontSize = 11, fontColor = { 140, 170, 255, 255 } },
            objLabel, objSub,
        },
    }
    local keys = { shatter = "左键", freeze = "E", rewind = "Q" }
    local slotRow = {}
    for _, sp in ipairs(spells) do slotRow[#slotRow + 1] = Slot(sp, keys[sp.id] or "") end
    local slotBar = UI.Panel {
        position = "absolute", left = 0, right = 0, bottom = 18, alignItems = "center", pointerEvents = "none",
        children = { UI.Panel { flexDirection = "row", gap = 10, children = slotRow } },
    }
    hintLabel = UI.Label { text = "", fontSize = 13, fontColor = { 225, 232, 250, 255 }, textAlign = "center" }
    local hintBar = UI.Panel {
        position = "absolute", left = 0, right = 0, bottom = 112, alignItems = "center", pointerEvents = "none",
        children = { UI.Panel { backgroundColor = INK, borderRadius = 8, paddingTop = 5, paddingBottom = 5, paddingLeft = 12, paddingRight = 12,
            children = { hintLabel } } },
    }
    msgLabel = UI.Label { text = "", fontSize = 17, fontWeight = "bold", fontColor = { 255, 236, 190, 255 }, textAlign = "center" }
    msgPanel = UI.Panel { backgroundColor = { 20, 26, 60, 210 }, borderRadius = 10, borderWidth = 1, borderColor = GOLD,
        paddingTop = 8, paddingBottom = 8, paddingLeft = 18, paddingRight = 18, children = { msgLabel } }
    local msgBar = UI.Panel { position = "absolute", left = 0, right = 0, top = "22%", alignItems = "center", pointerEvents = "none",
        children = { msgPanel } }
    -- 准星：中心点 + 四段短线
    local function Tick(w, h, l, t)
        return UI.Panel { position = "absolute", width = w, height = h, left = l, top = t, backgroundColor = { 255, 255, 255, 230 }, borderRadius = 1 }
    end
    crossPanel = UI.Panel { width = 26, height = 26, pointerEvents = "none", children = {
        Tick(4, 4, 11, 11), Tick(2, 7, 12, 0), Tick(2, 7, 12, 19), Tick(7, 2, 0, 12), Tick(7, 2, 19, 12),
    } }
    targetLabel = UI.Label { text = "", fontSize = 12, fontColor = GOLD, marginTop = 6 }
    local cross = UI.Panel { position = "absolute", left = 0, right = 0, top = 0, bottom = 0, alignItems = "center", justifyContent = "center",
        pointerEvents = "none", children = { UI.Panel { alignItems = "center", marginTop = 34, children = { crossPanel, targetLabel } } } }
    -- 按 H 显示的操作说明
    local help = UI.Panel {
        position = "absolute", top = 16, right = 16, paddingTop = 8, paddingBottom = 8, paddingLeft = 12, paddingRight = 12,
        backgroundColor = INK, borderRadius = 8, pointerEvents = "none",
        children = { UI.Label { whiteSpace = "normal", width = 230, fontSize = 11, fontColor = { 190, 205, 240, 255 },
            text = "WASD 移动  Space 跳  Shift 跑\n鼠标 视角  左键 碎时（按住蓄力）\nE 冻结  Q 回溯\nF 骑龙 / 下龙（龙苏醒后）\nTab 切换远景  按住 T 时间快进\nEsc 释放鼠标" ..
                (GetPlatform() == "Web" and "\n未锁定时按住鼠标拖动视角\n首次点击激活，再点击请求锁定" or "") } },
    }
    clockLabel = UI.Label { text = "", fontSize = 12, fontColor = { 255, 226, 170, 255 } }
    local clock = UI.Panel {
        position = "absolute", top = 16, left = 0, right = 0, alignItems = "center", pointerEvents = "none",
        children = { UI.Panel { backgroundColor = INK, borderRadius = 8, paddingTop = 4, paddingBottom = 4, paddingLeft = 12, paddingRight = 12,
            children = { clockLabel } } },
    }
    M.root = UI.Panel { width = "100%", height = "100%", pointerEvents = "none",
        children = { objPanel, help, clock, cross, msgBar, hintBar, slotBar } }
    UI.SetRoot(M.root)
    msgPanel:SetVisible(false)
end

function M.SetObjective(title, sub)
    if objLabel ~= nil then objLabel:SetText(title or "") end
    if objSub ~= nil then objSub:SetText(sub or "") end
end

function M.SetClock(text)
    if clockLabel ~= nil and text ~= lastClock then
        lastClock = text
        clockLabel:SetText(text or "")
    end
end

function M.SetHint(text) if hintLabel ~= nil then hintLabel:SetText(text or "") end end

function M.SetMessage(text)
    if msgLabel == nil then return end
    msgLabel:SetText(text or "")
    msgPanel:SetVisible(text ~= nil and text ~= "")
end

function M.SetTarget(text, timeObj)
    if targetLabel ~= nil then targetLabel:SetText(text or "") end
end

function M.SetCrossVisible(v) if crossPanel ~= nil then crossPanel:SetVisible(v) end end

-- cools: { id → 剩余秒 }，charge 0..1
function M.UpdateSlots(cools, charge)
    for id, s in pairs(slots) do
        local left = cools[id] or 0
        local k = (s.cd > 0) and math.min(1, left / s.cd) or 0
        s.mask:SetStyle({ height = math.floor(64 * k) })
        if id == "shatter" and charge > 0.05 then
            s.frame:SetStyle({ borderColor = { 255, math.floor(196 + 59 * charge), 90, 255 }, borderWidth = 2 + math.floor(charge * 2) })
        else
            s.frame:SetStyle({ borderColor = { s.col[1], s.col[2], s.col[3], 200 }, borderWidth = 2 })
        end
    end
end

function M.IsPointerOverUI() return UI.IsPointerOverUI() end

return M
