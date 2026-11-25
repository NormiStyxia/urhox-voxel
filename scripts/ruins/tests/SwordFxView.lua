-- 只由 -validate-test=ruins/tests/SwordFxView.lua 加载：真实主循环下拔剑连斩，再直接触发
-- 命中 / 落地波前 / 蓄力，并在固定帧截图（swordfx_<帧>.png，写入当前工作目录）。
-- headless 无输入焦点，故在固定帧注入攻击。运行器读的是 dist，改完脚本要先构建。
local V = _G["V"]
local frame = 0
local ATTACKS = { [40] = true, [120] = true, [144] = true, [168] = true, [194] = true, [222] = true, [254] = true }
-- 第一段挥完后推摇杆：走游戏自己的“移动取消”路径，月牙不应被抹掉
local MOVE_FROM, MOVE_TO = 62, 100
local SHOTS = {}
for f = 44, 110, 2 do SHOTS[f] = true end -- 第一段：背后常规机位（和旧版直接对比）
for f = 118, 200, 2 do SHOTS[f] = true end -- 压低机位：近平视挥砍平面
for f = 202, 228, 1 do SHOTS[f] = true end -- 第 3 段逐帧：扭转关(208-213) → 开(214起)
for f = 202, 296, 2 do SHOTS[f] = true end -- 五段连击
for f = 272, 296, 1 do SHOTS[f] = true end -- 第五段：腾空抬手（扭转关）
local pending = nil
V.atFrame(8, function()
    local game = _G["RUINS"]
    local moves, state = game.combat.moves, game.combat.state
    state.SetBusy(false)
    state.FinishTransition()
    if state.GetWeapon() ~= "sword" then state.SetWeapon("sword"); state.FinishTransition() end
    state.Enter("sword-fx-view")
    state.Activity(true)
    local update = moves.Update
    ---@param self any
    moves.Update = function(self, dt, controls)
        frame = frame + 1
        local nomi = game.nomiCtl
        if frame == 60 then nomi.camYaw = nomi.yaw + 20; nomi.camPitch = 22 end
        -- 压低到近平视：刀光面片几乎正侧对镜头，是“薄薄一片”最明显的角度
        if frame == 118 then nomi.camYaw = nomi.yaw + 20; nomi.camPitch = 6 end
        -- 常规游玩机位：第三段之后回到接近实机的俯角看一次
        if frame == 232 then nomi.camYaw = nomi.yaw + 20; nomi.camPitch = 14 end
        if pending ~= nil then
            -- 上一帧已呈现：此时读回的后备缓冲就是攻击后的那一帧
            local image = Image()
            if graphics:TakeScreenShot(image) then image:SavePNG("swordfx_" .. pending .. ".png") end
            pending = nil
        end
        if controls then
            controls.allowed = true
            controls.attack = ATTACKS[frame] == true
            controls.attackTap = ATTACKS[frame] == true
            if frame >= MOVE_FROM and frame <= MOVE_TO then controls.axis = self.o.forward() end
        end
        local rig = self.rig
        local fx = rig.swordVfx
        if fx then
            local position, forward = self.o.position(), self.o.forward()
            -- 同一低机位、同一刀（第 3 段）中途切换扭转：前半关、后半开，逐帧对照
            if frame == 208 then fx.twist = 0 end
            if frame == 214 then fx.twist = .72 end
            if frame == 263 then fx:GroundWave(position, forward) end
            if frame >= 40 and frame <= 340 then
                print(string.format("BLADE %d %s visual=%s stroke=%s arc=%d", frame, tostring(self.clip),
                    tostring(rig.visualActive), tostring(fx.stroke), fx:Count("arc")))
            end
        end
        if ATTACKS[frame] or SHOTS[frame] then
            print(string.format("SwordFxView: frame %d clip=%s combo=%s visual=%s arc=%d hit=%d wave=%d charge=%d vertices=%d",
                frame, tostring(self.clip), tostring(self.combo), tostring(rig.visualActive),
                fx and fx:Count("arc") or -1, fx and fx:Count("hit") or -1, fx and fx:Count("wave") or -1,
                fx and fx:Count("charge") or -1, fx and fx.vertices or -1))
        end
        if SHOTS[frame] then pending = frame end
        return update(self, dt, controls)
    end
    print("SwordFxView: armed")
end)
