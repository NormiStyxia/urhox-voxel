-- 只由 -validate-test=ruins/tests/SwordFxView.lua 加载：真实主循环下拔剑并连斩，
-- 在注入攻击后的若干帧由脚本自行截图（swordfx_<帧>.png，写入沙箱存档目录），
-- 供检查水晶剑刃、刀光、蓝色残影和前倾动作。headless 无输入焦点，故在固定帧注入攻击。
local V = _G["V"]
local frame = 0
local ATTACKS = { [40] = true, [64] = true, [88] = true, [112] = true }
local SHOTS = { [66] = true, [68] = true, [69] = true, [71] = true, [73] = true, [75] = true, [77] = true, [96] = true, [98] = true, [100] = true, [120] = true, [123] = true, [126] = true }
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
            -- 侧后方机位，拉近看剑刃与刀光
            local nomi = game.nomiCtl
            nomi.camYaw = nomi.yaw + 35
            print("SwordFxView: camera yaw " .. nomi.camYaw .. " body yaw " .. nomi.yaw)
        end
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
            controls.allowed = true
            controls.attack = ATTACKS[frame] == true
            controls.attackTap = ATTACKS[frame] == true
        end
        if ATTACKS[frame] or SHOTS[frame] then
            local rig = self.rig
            local fx = rig and rig.combatFx
            local arcs, edges, ghosts = 0, 0, 0
            if fx then
                for _, a in ipairs(fx.arcs) do if a.active then arcs = arcs + 1 end end
                for _, a in ipairs(fx.edges or {}) do if a.active then edges = edges + 1 end end
                for _, a in ipairs(fx.ghosts or {}) do if a.active then ghosts = ghosts + 1 end end
            end
            print(string.format("SwordFxView: frame %d dt=%.3f clip=%s trail=%s visual=%s slash=%s arcs=%d edges=%d ghosts=%d glow=%.2f hitOpen=%s",
                frame, dt, tostring(self.clip), tostring(rig and rig.trailEnabled), tostring(rig and rig.visualActive),
                tostring(fx and fx.slash), arcs, edges, ghosts, rig and rig.wingGlow or -1, tostring(self.hitOpen)))
        end
        if SHOTS[frame - 1] then pending = frame - 1 end
        return update(self, dt, controls)
    end
    print("SwordFxView: armed")
end)
