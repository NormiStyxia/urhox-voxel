-- -validate-test=ruins/tests/StairFeelProbe.lua 随真实遗迹运行：对比上楼顺滑度方案（只打印数据）。
local V = _G["V"]
local Terrain = require("ruins.RuinsTerrain")
local Build = require("ruins.RuinsBuild")

local function Probe(game)
    local world = game.world
    local cc = game.nomiCtl.cc
    local wasEnabled, auto = cc.enabled, world.updateEnabled
    cc.enabled, world.updateEnabled = false, false
    local node = game.scene:CreateChild("StairFeelWalker")
    local walker = node:CreateComponent("VoxelCharacterController")
    local function Reset()
        walker.height, walker.radius, walker.supportRadius = cc.height, cc.radius, cc.supportRadius
        walker.stepHeight, walker.maxSlopeAngle = cc.stepHeight, cc.maxSlopeAngle
        walker.enhancedInternalEdgeRemoval = cc.enhancedInternalEdgeRemoval
        walker.collisionLayer, walker.collisionMask = cc.collisionLayer, cc.collisionMask
        walker.stickToFloorDistance = cc.stickToFloorDistance
    end
    local function Settle(p)
        walker:Teleport(p)
        walker.linearVelocity, walker.desiredVelocity = Vector3.ZERO, Vector3.ZERO
        for i = 1, 30 do world:Update(1 / 60, 1) end
    end
    local function Walk(name, ascending, speed, extraY)
        local start, finish = ascending and 19.5 or 34.25, ascending and 34.25 or 19.5
        Settle(Vector3(0, ascending and .1 or 6.1, start))
        local dir = ascending and 1 or -1
        local minSpeed, slow, pop, frames, sum, n = math.huge, 0, 0, 0, 0, 0
        local last = node.worldPosition
        local reached = false
        for i = 1, 600 do
            local y = 0
            if extraY and Terrain.InStair(0, node.worldPosition.z) and walker.onGround then y = extraY end
            walker.desiredVelocity = Vector3(0, y, dir * speed)
            world:Update(1 / 60, 1)
            local p = node.worldPosition
            local d = p.z
            local onStair = d > 20.6 and d < 32.4
            if i > 10 and onStair then
                local s = Vector3(p.x - last.x, 0, p.z - last.z):Length() * 60
                minSpeed = math.min(minSpeed, s); sum, n = sum + s, n + 1
                if s < speed * .6 then slow = slow + 1 end
                pop = math.max(pop, math.abs(p.y - last.y))
            end
            last, frames = p, i
            if (ascending and d >= finish) or (not ascending and d <= finish) then reached = true; break end
        end
        walker.desiredVelocity = Vector3.ZERO
        for i = 1, 15 do world:Update(1 / 60, 1) end
        print(string.format("StairFeel %-10s %s v=%.1f reached=%s frames=%d avg=%.2f min=%.2f slow=%d pop=%.3f endY=%.2f",
            name, ascending and "up  " or "down", speed, tostring(reached), frames, n > 0 and sum / n or 0, minSpeed, slow, pop,
            node.worldPosition.y))
    end
    local function Both(name, extraY)
        for _, v in ipairs({ 4.2, 7.2 }) do Walk(name, true, v, extraY); Walk(name, false, v) end
    end
    local ok, err = pcall(function()
        Reset(); Both("base")
        Reset(); Both("upY", 4.2 * .5)
        Reset(); walker.supportRadius = .12; Both("support12")
        Reset(); walker.radius, walker.supportRadius = .25, .2; Both("radius25")
        Reset(); walker.stepHeight = .3; Both("step30")
        Reset(); walker.enhancedInternalEdgeRemoval = false; Both("noEdge")
        Reset(); walker.enhancedInternalEdgeRemoval = false; walker.supportRadius = .12; Both("noEdge+s12")
        Reset(); walker.enhancedInternalEdgeRemoval = false; Both("noEdge+upY", 4.2 * .5)
        -- 隐形斜坡：踏面中线 y=(d-20.5)*0.5，北侧；只让 walker 忽略石阶体积。
        local stairs = Build.stairVolumes
        local saved = {}
        for i, v in ipairs(stairs) do saved[i] = { v.collisionLayer, v.collisionMask }; v.collisionLayer = 8; v.collisionMask = 0xffffffff end
        local theta = math.atan(.5)
        local rot = Quaternion(-math.deg(theta), Vector3.RIGHT)
        print("StairFeel ramp forward=" .. tostring(rot * Vector3.FORWARD))
        local L = math.sqrt(12 * 12 + 6 * 6)
        local up = rot * Vector3.UP
        local topCenter = Vector3(0, 3, 26.5)
        local center = topCenter - up * .5
        local origin = Vector3(-.125, -3, 26.375)
        local ramp = world:CreateVolume(1, 1, 1, .25, origin)
        ramp:GetGrid():FillBox(0, 0, 0, 0, 0, 0, true)
        world:FinalizeVolume(ramp)
        ramp:SetCollisionBox(Vector3(7, 1, L), center - (origin + Vector3(.125, .125, .125)), rot)
        Reset(); walker.collisionMask = cc.collisionMask & ~8; Both("ramp")
        Reset(); walker.collisionMask = cc.collisionMask & ~8; walker.stepHeight = .3; Both("ramp+s30")
        ramp:GetNode():Remove()
        for i, v in ipairs(stairs) do v.collisionLayer, v.collisionMask = saved[i][1], saved[i][2] end
        -- 前沿上方斜坡：石阶照常碰撞，斜坡面 y=(d-20.25)*0.5+0.01 架在所有前沿棱上方。
        local function Above(lift)
            local top2 = Vector3(0, 3 + lift, 26.25)
            local c2 = top2 - up * .5
            local o2 = Vector3(-.125, -3, 26.125)
            local r2 = world:CreateVolume(1, 1, 1, .25, o2)
            r2:GetGrid():FillBox(0, 0, 0, 0, 0, 0, true)
            world:FinalizeVolume(r2)
            r2:SetCollisionBox(Vector3(7, 1, L), c2 - (o2 + Vector3(.125, .125, .125)), rot)
            return r2
        end
        local r2 = Above(.01)
        Reset(); Both("above")
        for _, x in ipairs({ -2.9, 2.9 }) do
            Settle(Vector3(x, .1, 19.5))
            for i = 1, 300 do walker.desiredVelocity = Vector3(0, 0, 4.2); world:Update(1 / 60, 1) end
            print(string.format("StairFeel above lane=%.1f end=%s", x, tostring(node.worldPosition)))
        end
        -- 扶墙仍挡：从斜坡中段横向冲墙
        Settle(Vector3(2.9, 2.6, 25.25))
        for i = 1, 90 do walker.desiredVelocity = Vector3(4.2, 0, 0); world:Update(1 / 60, 1) end
        print("StairFeel above wall=" .. tostring(node.worldPosition))
        r2:GetNode():Remove()
    end)
    node:Remove()
    cc.enabled, world.updateEnabled = wasEnabled, auto
    if not ok then print("StairFeel ERROR " .. tostring(err)); V.fail(tostring(err)) end
end

V.atFrame(8, function() Probe(_G["RUINS"]) end)
