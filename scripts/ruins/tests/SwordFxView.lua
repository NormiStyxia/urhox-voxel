-- 只由 -validate-test=ruins/tests/SwordFxView.lua 加载：真实主循环下拔剑连斩，再直接触发
-- 命中 / 落地波前 / 蓄力，并在固定帧截图（swordfx_<帧>.png，写入当前工作目录）。
-- headless 无输入焦点，故在固定帧注入攻击。运行器读的是 dist，改完脚本要先构建。
local V = _G["V"]
local frame = 0
local ATTACKS = { [40] = true, [64] = true, [88] = true }
local SHOTS = {}
for _, f in ipairs({ 72, 74, 76, 78, 80, 84, 88, 104, 106, 108, 112, 116,
    131, 133, 135, 138, 141, 146, 149, 152, 155, 158, 162, 175, 185, 195, 205, 215, 225, 235, 244,
    247, 249, 251, 253, 255, 258, 261, 265 }) do SHOTS[f] = true end
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
        if frame == 60 then nomi.camYaw = nomi.yaw + 35 end
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
        end
        local rig = self.rig
        local fx = rig.swordVfx
        if fx then
            local position, forward = self.o.position(), self.o.forward()
            local right = Vector3.UP:CrossProduct(forward)
            if frame == 130 then fx:Contact(position + forward * .6 + right * 1.1 + Vector3(0, 1.2, 0), true) end
            if frame == 145 then fx:GroundWave(position, forward) end
            local pivot = rig.entries.sword.pivot
            local root, tip = pivot:LocalToWorld(rig.bladeRoot), pivot:LocalToWorld(rig.bladeTip)
            if frame >= 165 and frame < 245 then fx:Charge(root, tip, (frame - 165) / 80, dt) end
            if frame == 245 then fx:ChargeBurst(root, tip) end
        end
        if ATTACKS[frame] or SHOTS[frame] then
            print(string.format("SwordFxView: frame %d clip=%s combo=%s visual=%s arc=%d hit=%d wave=%d charge=%d free=%d",
                frame, tostring(self.clip), tostring(self.combo), tostring(rig.visualActive),
                fx and fx.world:Count("arc") or -1, fx and fx.world:Count("hit") or -1, fx and fx.world:Count("wave") or -1,
                fx and fx.blade:Count("charge") or -1, fx and #fx.world.free or -1))
        end
        if SHOTS[frame] then pending = frame end
        return update(self, dt, controls)
    end
    print("SwordFxView: armed")
end)
