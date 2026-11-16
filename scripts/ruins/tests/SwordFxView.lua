-- 只由 -validate-test=ruins/tests/SwordFxView.lua 加载：真实主循环下拔剑并连斩，
-- 在注入攻击后的若干帧由脚本自行截图（swordfx_<帧>.png，写入沙箱存档目录），
-- 供检查水晶剑刃、刀光、蓝色残影和前倾动作。headless 无输入焦点，故在固定帧注入攻击。
local V = _G["V"]
local frame = 0
local ATTACKS = { [40] = true, [52] = true, [64] = true }
local SHOTS = { [42] = true, [43] = true, [44] = true, [54] = true, [55] = true, [66] = true, [67] = true }
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
        if pending ~= nil then
            -- 上一帧已呈现：此时读回的后备缓冲就是攻击后的那一帧
            local image = Image()
            if graphics:TakeScreenShot(image) then
                local name = "swordfx_" .. pending .. ".png"
                print("SwordFxView: saved " .. name .. " " .. tostring(image:SavePNG(name)))
            end
            pending = nil
        end
        if controls then
            if ATTACKS[frame] then controls.allowed = true end
            controls.attack = ATTACKS[frame] == true
            controls.attackTap = ATTACKS[frame] == true
        end
        if ATTACKS[frame] or SHOTS[frame] then
            print(string.format("SwordFxView: frame %d dt=%.3f clip=%s", frame, dt, tostring(self.clip)))
        end
        if SHOTS[frame - 1] then pending = frame - 1 end
        return update(self, dt, controls)
    end
    print("SwordFxView: armed")
end)
