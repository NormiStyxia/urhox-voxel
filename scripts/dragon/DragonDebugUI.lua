-- ====================================================================
-- DragonDebugUI.lua — 体素巨龙测试面板（urhox-libs/UI）
--
-- 状态切换、播放速度 / 步行速度 / 振翅频率 / 动作幅度 / 飞行速度，
-- 骨架 / 碰撞体 / 翼膜薄片显示，暂停 / 单步 / 继续，部位独立测试，关节测试模式。
-- ====================================================================

local UI = require("urhox-libs/UI")
local Variants = require("dragon.DragonVariants")

local M = {}

---@type Label
local statusLabel = nil
---@type Label
local pauseLabel = nil
local jointLabels = {}
---@type Label
local hintLabel = nil
local uiReady = false

local function SectionTitle(text)
    return UI.Label { text = text, fontSize = 12, fontWeight = "bold", fontColor = { 150, 200, 255, 255 }, marginTop = 6 }
end

local function SliderRow(label, min, max, step, value, fmt, onChange)
    ---@type Label
    local valueLabel = UI.Label { text = string.format(fmt, value), fontSize = 11, width = 44, textAlign = "right",
        fontColor = { 220, 230, 245, 255 } }
    return UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 6, width = "100%",
        children = {
            UI.Label { text = label, fontSize = 11, width = 62, fontColor = { 200, 210, 230, 255 } },
            UI.Slider {
                value = value, min = min, max = max, step = step, flexGrow = 1, flexShrink = 1,
                onChange = function(self, v)
                    valueLabel:SetText(string.format(fmt, v))
                    onChange(v)
                end,
            },
            valueLabel,
        },
    }
end

local function Btn(text, onClick, variant)
    return UI.Button { text = text, fontSize = 12, height = 28, flexShrink = 1, minWidth = 0, variant = variant or "secondary", onClick = onClick }
end

local function Check(label, checked, onChange)
    return UI.Checkbox { label = label, checked = checked, size = 16, onChange = function(self, v) onChange(v) end }
end

---@param ctrl DragonAnimationController
---@param T table DragonTest 模块（显示开关、相机）
function M.Build(ctrl, T)
    if not uiReady then
        UI.Init({ theme = "default-dark", scale = UI.Scale.DEFAULT })
        uiReady = true
    end
    jointLabels = {}

    -- 型号切换：当前型号用主色按钮
    local variantButtons = {}
    for _, id in ipairs(Variants.ORDER) do
        variantButtons[#variantButtons + 1] = Btn(Variants.Name(id), function()
            if id ~= T.variant then T.RequestVariant(id) end
        end, (id == T.variant) and "primary" or "secondary")
    end

    local states = {
        { "待机 / 收翼", "IDLE" }, { "行走", "WALK" }, { "左转 90°", "TURN", -90 }, { "右转 90°", "TURN", 90 },
        { "展翼", "SPREAD_WINGS" }, { "咆哮", "ROAR" }, { "起飞", "TAKEOFF" }, { "飞行", "FLY" },
        { "滑翔", "GLIDE" }, { "降落", "LAND" },
    }
    local stateButtons = {}
    for _, s in ipairs(states) do
        stateButtons[#stateButtons + 1] = Btn(s[1], function()
            ctrl.demo = nil
            if s[2] == "TAKEOFF" then ctrl:Request("FLY") else ctrl:Request(s[2], s[3]) end
        end)
    end

    statusLabel = UI.Label { text = "", fontSize = 11, whiteSpace = "normal", width = "100%", fontColor = { 235, 240, 250, 255 } }
    pauseLabel = UI.Label { text = "播放中", fontSize = 11, fontColor = { 160, 255, 170, 255 } }

    -- 关节测试：可测关节列表
    local jointOptions = {}
    for _, name in ipairs(ctrl.rig.order) do
        if name:sub(1, 2) ~= "wm" and name ~= "body" then
            jointOptions[#jointOptions + 1] = { value = name, label = name }
        end
    end
    local jt = ctrl.jointTest
    local axisSliders = {}
    local function JointSlider(axis, idx)
        local fmt = "%.0f°"
        ---@type Label
        local vl = UI.Label { text = "0°", fontSize = 11, width = 40, textAlign = "right" }
        jointLabels[idx] = vl
        local sl = UI.Slider {
            value = 0, min = -150, max = 150, step = 1, flexGrow = 1, flexShrink = 1,
            onChange = function(self, v)
                jt[axis] = v
                vl:SetText(string.format(fmt, v))
            end,
        }
        axisSliders[idx] = sl
        return UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, width = "100%", children = {
            UI.Label { text = "旋转 " .. string.upper(axis), fontSize = 11, width = 48 }, sl, vl } }
    end

    local panel = UI.Panel {
        position = "absolute", left = 10, top = 10, width = 318, height = "96%",
        backgroundColor = { 18, 24, 36, 215 }, borderRadius = 8, padding = 10,
        borderColor = { 90, 130, 200, 120 }, borderWidth = 1,
        children = {
            UI.Label { text = "体素巨龙 · 动画测试", fontSize = 15, fontWeight = "bold", fontColor = { 200, 230, 255, 255 } },
            statusLabel,
            UI.ScrollView {
                width = "100%", flexGrow = 1, flexShrink = 1, flexBasis = 0, minHeight = 200, scrollY = true,
                children = {
                    UI.Panel { width = "100%", gap = 4, paddingRight = 6, children = {
                        SectionTitle("型号"),
                        UI.SimpleGrid { columns = 3, gap = 4, children = variantButtons },
                        UI.Label { whiteSpace = "normal", width = "100%", fontSize = 10, fontColor = { 170, 185, 210, 255 },
                            text = "小号：宠物幼龙，不能骑，会跟着诺米  中号：原版巨龙  大号：古龙体型，趾爪可动" },
                        SectionTitle("动作状态"),
                        UI.SimpleGrid { columns = 2, gap = 4, children = stateButtons },
                        Btn("▶ 完整演示序列", function() ctrl:StartDemo() end, "primary"),
                        Btn((T.breath ~= nil and T.breath:Available()) and ("龙息 · " .. T.breath.cfg.name .. "（B）") or "龙息（仅中号 / 大号）",
                            function() if T.breath ~= nil then T.breath:Trigger() end end, "primary"),

                        SectionTitle("播放控制"),
                        UI.Panel { flexDirection = "row", gap = 4, alignItems = "center", children = {
                            Btn("暂停 / 继续", function()
                                ctrl.paused = not ctrl.paused
                                pauseLabel:SetText(ctrl.paused and "已暂停" or "播放中")
                            end),
                            Btn("单步", function()
                                ctrl.paused = true
                                ctrl.stepFrames = ctrl.stepFrames + 1
                                pauseLabel:SetText("已暂停（单步）")
                            end),
                            pauseLabel,
                        } },
                        SliderRow("播放速度", 0.05, 2.0, 0.05, ctrl.params.playback, "%.2fx", function(v) ctrl.params.playback = v end),
                        SliderRow("步行速度", 0.4, 3.5, 0.1, ctrl.params.walkSpeed, "%.1f", function(v) ctrl.params.walkSpeed = v end),
                        SliderRow("振翅频率", 0.4, 2.0, 0.05, ctrl.params.flapHz, "%.2f", function(v) ctrl.params.flapHz = v end),
                        SliderRow("动作幅度", 0.3, 1.5, 0.05, ctrl.params.amp, "%.2f", function(v) ctrl.params.amp = v end),
                        SliderRow("飞行速度", 3.0, 16.0, 0.5, ctrl.params.flySpeed, "%.1f", function(v) ctrl.params.flySpeed = v end),
                        SliderRow("转身速度", 15, 120, 5, ctrl.params.turnRate, "%.0f", function(v) ctrl.params.turnRate = v end),

                        SectionTitle("显示"),
                        UI.SimpleGrid { columns = 2, gap = 4, children = {
                            Check("骨架 / 关节", T.showSkeleton, function(v) T.showSkeleton = v end),
                            Check("碰撞 / 命中区", T.showHitZones, function(v) T.showHitZones = v end),
                            Check("翼膜控制网", T.showStrips, function(v) T.showStrips = v end),
                            Check("相机跟随", T.cam.follow, function(v) T.cam.follow = v end),
                            Check("落足点", T.showFeet, function(v) T.showFeet = v end),
                            Check("诺米（体型对比）", T.showNomi, function(v) T.showNomi = v end),
                            Check("玩法模式（诺米骑龙）", T.playMode, function(v) T.SetPlayMode(v) end),
                        } },

                        SectionTitle("部位独立测试"),
                        UI.Dropdown {
                            options = {
                                { value = "all", label = "全部部位" }, { value = "wings", label = "只动翅膀" },
                                { value = "neck", label = "只动头颈" }, { value = "legs", label = "只动四肢" },
                                { value = "tail", label = "只动尾巴" },
                            },
                            value = "all", maxVisibleItems = 6,
                            onChange = function(self, v) ctrl.mask = v end,
                        },

                        SectionTitle("关节测试模式（纯 FK，冻结状态机）"),
                        Check("启用关节测试", false, function(v) jt.enabled = v end),
                        UI.Dropdown {
                            options = jointOptions, value = jt.joint, maxVisibleItems = 10,
                            onChange = function(self, v)
                                jt.joint = v
                                jt.x, jt.y, jt.z = 0, 0, 0
                                for i, sl in ipairs(axisSliders) do sl:SetValue(0); jointLabels[i]:SetText("0°") end
                            end,
                        },
                        JointSlider("x", 1), JointSlider("y", 2), JointSlider("z", 3),
                        Btn("归零", function()
                            jt.x, jt.y, jt.z = 0, 0, 0
                            for i, sl in ipairs(axisSliders) do sl:SetValue(0); jointLabels[i]:SetText("0°") end
                        end),

                        SectionTitle("键盘"),
                        UI.Label { whiteSpace = "normal", width = "100%", fontSize = 10, fontColor = { 170, 185, 210, 255 },
                            text = "【玩法模式】WASD 移动诺米  Space 跳  Shift 奔跑  靠近龙按 F 骑乘（骑乘时 W 前进 A/D 转向 S 刹车 Shift 空中冲刺 Space 起飞/上升 C 下降 L 降落 G 滑翔 F 下龙）\n【调试模式】W/S 加减速  A/D 转向  Q/E 原地转身  Space 起飞/爬升  C 下降\n" ..
                                "G 滑翔  L 降落  R 咆哮  B 龙息  T 展翼/收翼  P 暂停  N 单步\n" ..
                                "鼠标右键/左键拖动旋转  滚轮缩放  中键或 Shift+左键平移\n1/2/3/4 正/侧/背/斜视角  F 跟随" },
                    } },
                },
            },
        },
    }
    hintLabel = UI.Label { text = "", fontSize = 18, fontWeight = "bold", fontColor = { 255, 255, 255, 255 }, textAlign = "center" }
    local hintBar = UI.Panel {
        position = "absolute", left = 0, right = 0, bottom = 28, alignItems = "center", pointerEvents = "none",
        children = { UI.Panel { backgroundColor = { 10, 16, 28, 190 }, borderRadius = 8, paddingTop = 8, paddingBottom = 8,
            paddingLeft = 16, paddingRight = 16, children = { hintLabel } } },
    }
    UI.SetRoot(UI.Panel { width = "100%", height = "100%", pointerEvents = "box-none", children = { panel, hintBar } })
end

function M.Update(ctrl, fps)
    if statusLabel ~= nil then
        statusLabel:SetText(ctrl:Status() .. (fps and string.format("  FPS %.0f", fps) or ""))
    end
end

function M.SetHint(text)
    if hintLabel ~= nil then hintLabel:SetText(text or "") end
end

function M.IsPointerOverUI()
    return UI.IsPointerOverUI()
end

return M
