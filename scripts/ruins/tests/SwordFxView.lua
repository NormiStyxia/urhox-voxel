-- 只由 -validate-test=ruins/tests/SwordFxView.lua 加载：真实主循环下拔剑并连斩，
-- 在注入攻击后的若干帧由脚本自行截图（swordfx_<帧>.png，写入当前工作目录），
-- 供检查体素刀光、命中与落地波前。headless 无输入焦点，故在固定帧注入攻击。
local V = _G["V"]
local frame = 0
local ATTACKS = { [40] = true, [64] = true, [88] = true, [112] = true, [136] = true, [160] = true }
local SHOT_FROM, SHOT_TO, SHOT_EVERY = 66, 215, 2
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
    moves.Update = function(self, dt, controls)
        frame = frame + 1
        if frame == 60 then
            local nomi = game.nomiCtl
            nomi.camYaw = nomi.yaw + 35
        end
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
        local shot = frame >= SHOT_FROM and frame <= SHOT_TO and (frame - SHOT_FROM) % SHOT_EVERY == 0
        if ATTACKS[frame] or shot then
            local rig = self.rig
            local fx = rig and rig.swordVfx
            print(string.format("SwordFxView: frame %d dt=%.3f clip=%s combo=%s visual=%s hitOpen=%s arc=%d hit=%d wave=%d charge=%d free=%d",
                frame, dt, tostring(self.clip), tostring(self.combo), tostring(rig and rig.visualActive), tostring(self.hitOpen),
                fx and fx.world:Count("arc") or -1, fx and fx.world:Count("hit") or -1, fx and fx.world:Count("wave") or -1,
                fx and fx.blade:Count("charge") or -1, fx and #fx.world.free or -1))
        end
        if shot then pending = frame end
        return update(self, dt, controls)
    end
    print("SwordFxView: armed")
end)
