-- 只由 -validate-test=ruins/tests/SwordFxView.lua 加载：真实主循环下拔剑并连斩，供截图检查
-- 水晶剑刃、刀光、蓝色残影和前倾动作。攻击在固定帧注入（headless 无输入焦点）。
local V = _G["V"]
local frame = 0
local ATTACKS = { [60] = true, [76] = true, [92] = true, [108] = true, [124] = true }
V.atFrame(8, function()
    local game = _G["RUINS"]
    local moves, state = game.combat.moves, game.combat.state
    state.SetBusy(false)
    state.FinishTransition()
    if state.GetWeapon() ~= "sword" then state.SetWeapon("sword"); state.FinishTransition() end
    state.Enter("sword-fx-view")
    state.Activity(true)
    local nomi = game.nomiCtl
    nomi.cc:Teleport(Vector3(0, 6.1, 40))
    if game.dayNight then game.dayNight.lockHour = 15; game.dayNight:SetHour(15) end
    local update = moves.Update
    moves.Update = function(self, dt, controls)
        frame = frame + 1
        if controls then
            controls.attack = ATTACKS[frame] == true
            controls.attackTap = ATTACKS[frame] == true
            if ATTACKS[frame] then print(string.format("SwordFxView: attack at frame %d t=%.3f", frame, time:GetElapsedTime())) end
        end
        return update(self, dt, controls)
    end
    print("SwordFxView: armed")
end)
