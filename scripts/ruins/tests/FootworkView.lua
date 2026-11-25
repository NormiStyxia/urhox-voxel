-- 只由 -validate-test=ruins/tests/FootworkView.lua 加载：从侧面看五段普攻的步法。
-- 镜头转到角色右侧、压低，逐两帧截图 footwork_<帧>.png（写入当前工作目录），
-- 并打印每只脚的落点 / 是否在迈步 / 胯下沉，便于对照。运行器读的是 dist，改完先构建。
local V = _G["V"]
local frame = 0
-- 第一刀从背剑出手（先拔剑），之后在可取消点接下一段
local ATTACKS = { [40] = true, [96] = true, [120] = true, [146] = true, [176] = true }
local SHOTS = {}
for f = 60, 260, 2 do SHOTS[f] = true end
local pending = nil
---@type Vector3[]|nil
local eyeAt = nil
V.atFrame(8, function()
    local game = _G["RUINS"]
    local moves, state = game.combat.moves, game.combat.state
    state.SetBusy(false)
    state.FinishTransition()
    if state.GetWeapon() ~= "sword" then state.SetWeapon("sword"); state.FinishTransition() end
    state.Enter("footwork-view")
    state.Activity(true)
    local update = moves.Update
    ---@param self any
    moves.Update = function(self, dt, controls)
        frame = frame + 1
        local nomi = game.nomiCtl
        -- 固定的侧面机位：在起手位置的右侧，相机每帧被游戏重新摆放后再挪过来
        if frame == 30 then
            -- 朝起手时的身后打：默认相机就在那边，是开阔地面，突进不会被台阶挡住
            local f = -nomi.node.worldDirection
            -- 不吸附训练木桩、不跟随相机朝向：五段都朝起手时的正前方打，侧面机位才一直是侧面
            local facing = Vector3(f.x, 0, f.z):Normalized()
            moves.o.assist = nil
            moves.o.intent = function() return facing end
            -- headless 没有输入焦点，场景会把突进位移清零；测试里把招式算出的位移照常交给角色
            local move = nomi.Move
            ---@param n any
            nomi.Move = function(n, mdt, mf, mr, run, jump, aiming, options)
                local m = moves.motion
                if options and m and (m.x ~= 0 or m.z ~= 0) then options.motion = m end
                return move(n, mdt, mf, mr, run, jump, aiming, options)
            end
        end
        -- 第一刀开始后角色朝向已定：另开一台相机放在它的右侧，固定不动。
        -- 不改游戏相机——战斗朝向会跟着游戏相机转，挪它会把角色也转过来。
        if frame == 59 then
            local p = nomi.node.worldPosition
            local d = nomi.nomi.root.worldRotation * Vector3(0, 0, 1)
            d = Vector3(d.x, 0, d.z):Normalized()
            local right = Vector3(d.z, 0, -d.x)
            local camNode = game.scene:CreateChild("FootworkCamera")
            local cam = camNode:CreateComponent("Camera") --[[@as Camera]]
            cam.fov = 38
            camNode.worldPosition = p + right * 4.6 + d * 1.0 + Vector3(0, 0.6, 0)
            camNode:LookAt(p + d * 1.0 + Vector3(0, 0.62, 0))
            renderer:GetViewport(0):SetCamera(cam)
            eyeAt = { camNode.worldPosition, d }
        end
        if pending ~= nil then
            local image = Image()
            if graphics:TakeScreenShot(image) then image:SavePNG("footwork_" .. pending .. ".png") end
            pending = nil
        end
        if controls then
            controls.allowed = true
            controls.attack = ATTACKS[frame] == true
            controls.attackTap = ATTACKS[frame] == true
        end
        local plant = game.footPlant
        if plant and frame >= 40 and frame <= 260 then
            local legs = plant:Debug()
            local r, l = legs[1], legs[2]
            local np = nomi.node.worldPosition
            print(string.format("FOOT %d %s w=%.2f drop=%.3f body(%.2f,%.2f) R(%.2f,%.2f,%.2f%s h%.2f) L(%.2f,%.2f,%.2f%s h%.2f)",
                frame, tostring(self.clip), plant.weight, plant.drop, np.x, np.z,
                r.x, r.y, r.z, r.swing and "*" or "", r.heel, l.x, l.y, l.z, l.swing and "*" or "", l.heel))
        end
        if SHOTS[frame] then pending = frame end
        local result = update(self, dt, controls)
        if frame >= 58 and frame <= 76 then
            local m = self.motion or Vector3.ZERO
            print(string.format("MOTION %d onGround=%s motion=(%.3f,%.3f) debt=%.3f scale=%.2f", frame,
                tostring(nomi.cc.onGround), m.x, m.z, self.motionDebt or 0, self.motionScale or -1))
        end
        return result
    end
    print("FootworkView: armed")
end)
