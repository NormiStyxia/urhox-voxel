-- 只由 -validate-test=ruins/tests/HitFxView.lua 加载：命中特效从三个角度各截一组。
-- 先出一刀拿到真实的挥砍方向，再在正前方触发命中；三个机位分别是背后、侧面、俯视。
-- 运行器读的是 dist，改完脚本要先构建。
local V = _G["V"]
local frame = 0
local CAMERAS = {
    { at = 34, pitch = 10, yaw = 20 },
    { at = 94, pitch = 10, yaw = 110 },
    { at = 154, pitch = 62, yaw = 20 },
}
local HITS = { [40] = true, [100] = true, [160] = true }
local SHOTS = {}
for _, hit in ipairs({ 40, 100, 160 }) do
    for f = hit, hit + 10 do SHOTS[f] = true end
end
local pending = nil
V.atFrame(8, function()
    local game = _G["RUINS"]
    local moves, state = game.combat.moves, game.combat.state
    state.SetBusy(false)
    state.FinishTransition()
    if state.GetWeapon() ~= "sword" then state.SetWeapon("sword"); state.FinishTransition() end
    state.Enter("hit-fx-view")
    state.Activity(true)
    local update = moves.Update
    ---@param self any
    moves.Update = function(self, dt, controls)
        frame = frame + 1
        local nomi = game.nomiCtl
        for _, cam in ipairs(CAMERAS) do
            if frame == cam.at then
                nomi.camYaw = nomi.yaw + cam.yaw
                nomi.camPitch = cam.pitch
            end
        end
        if pending ~= nil then
            local image = Image()
            if graphics:TakeScreenShot(image) then image:SavePNG("hitfx_" .. pending .. ".png") end
            pending = nil
        end
        if controls then
            controls.allowed = true
            controls.attack = frame == 30 or frame == 90 or frame == 150
            controls.attackTap = controls.attack
        end
        local rig = self.rig
        local fx = rig.swordVfx
        if fx and HITS[frame] then
            local p, fwd = self.o.position(), self.o.forward()
            local pos = Vector3(p.x + fwd.x * 1.15 + fwd.z * .3, p.y + 1.05, p.z + fwd.z * 1.15 - fwd.x * .3)
            fx:Contact(pos, true)
            print(string.format("HitFxView: contact at frame %d swung=%s", frame, tostring(fx.tx * fx.tx + fx.tz * fx.tz > .5)))
        end
        if SHOTS[frame] then
            print(string.format("HitFxView: frame %d hit=%d vertices=%d", frame,
                fx and fx:Count("hit") or -1, fx and fx.vertices or -1))
        end
        if SHOTS[frame] then pending = frame end
        return update(self, dt, controls)
    end
    print("HitFxView: armed")
end)
