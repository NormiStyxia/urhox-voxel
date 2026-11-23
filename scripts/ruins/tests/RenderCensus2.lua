-- 只由 -validate-test 加载：按场景根节点名统计 drawable 与批次贡献。
-- 南门机位，正午。每步只隐藏一类根节点，读 4 帧平均批次/三角形，再恢复。
local V = _G["V"]
local game
local groups, order = {}, {}
local stepIndex, wait = 0, 0
local base
local steps = {}

local function Collect()
    for _, child in ipairs(game.scene:GetChildren()) do
        local name = child.name ~= "" and child.name or "(unnamed)"
        local g = groups[name]
        if not g then
            g = { nodes = {}, drawables = 0, casters = 0, tris = 0 }
            groups[name] = g
            order[#order + 1] = name
        end
        g.nodes[#g.nodes + 1] = child
        for _, t in ipairs({ "CustomGeometry", "StaticModel", "AnimatedModel", "BillboardSet" }) do
            for _, c in ipairs(child:GetComponents(t, true)) do
                local d = c --[[@as Drawable]]
                g.drawables = g.drawables + 1
                if d.castShadows then g.casters = g.casters + 1 end
            end
        end
    end
    table.sort(order, function(a, b) return groups[a].drawables > groups[b].drawables end)
    for _, name in ipairs(order) do
        local g = groups[name]
        print(string.format("Census2: group %-28s roots=%4d drawables=%5d casters=%5d", name, #g.nodes, g.drawables, g.casters))
    end
    steps[#steps + 1] = { name = "baseline" }
    for i = 1, math.min(14, #order) do
        local name = order[i]
        steps[#steps + 1] = {
            name = "hide:" .. name,
            fn = function() for _, n in ipairs(groups[name].nodes) do n.enabled = false end end,
            undo = function() for _, n in ipairs(groups[name].nodes) do n.enabled = true end end,
        }
    end
    steps[#steps + 1] = { name = "baseline2" }
end

function Census2_PostUpdate(eventType, eventData)
    Ruins_HandlePostUpdate(eventType, eventData)
    local cn = game.nomiCtl:CameraNode()
    cn.worldPosition = Vector3(4, 8.3, -74)
    cn:LookAt(Vector3(0, 7.1, -40), Vector3.UP)
    if wait > 0 then
        wait = wait - 1
        if wait == 0 then
            local s = steps[stepIndex]
            s.b, s.p, s.k = (s.b or 0) + renderer:GetNumBatches(), (s.p or 0) + renderer:GetNumPrimitives(), (s.k or 0) + 1
            if s.k < 3 then wait = 1; return end
            local b, p = s.b / s.k, s.p / s.k
            if not base then base = { b = b, p = p } end
            print(string.format("Census2: step %-34s batches=%6.0f (%+6.0f) primitives=%8.0f (%+8.0f)", s.name, b, b - base.b, p, p - base.p))
            if s.undo then s.undo() end
        end
        return
    end
    stepIndex = stepIndex + 1
    local s = steps[stepIndex]
    if not s then return end
    if s.fn then s.fn() end
    wait = stepIndex == 1 and 30 or 4
end

V.atFrame(4, function()
    game = _G["RUINS"]
    local Settings = require("ruins.GameSettings")
    Settings.Set("quality", "high")
    Settings.Set("volumetric", false)
    game.dayNight.lockHour = 12
    game.dayNight:SetHour(12)
    game.nomiCtl.node:SetDeepEnabled(false)
    Collect()
    SubscribeToEvent("PostUpdate", "Census2_PostUpdate")
end)
