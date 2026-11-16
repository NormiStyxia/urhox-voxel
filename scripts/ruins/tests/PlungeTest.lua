-- 只由 -validate-test=ruins/tests/PlungeTest.lua 加载，使用真实遗迹、战斗输入端口和体素角色。
-- 固定步长覆盖 30 / 60 / 120 FPS；传送只用于用例起点，攻击开始后不修正位置。
-- 碰撞区域（单位 m）：
--           诺米胶囊：height=1.65，radius=.32
--           脚底起点 y=6+高度（.8 / 2 / 8）
--                     ↓ 起手 .10s 后以 6→12m/s 下落
--   ================== 内环平台 y=6（x=22，z=0）
-- 只认可真实 cc.onGround；空中不提前触发落地，撞地只播放一次落地片段。
-- 不调用 Action/StartPlunge 伪造攻击；与 F11 一样向 Update 注入按钮意图。

local V = _G["V"]
local Moves = require("combat.CombatMoves")
local Terrain = require("ruins.RuinsTerrain")
local checks = 0

local function Check(condition, message)
    checks = checks + 1
    V.assert(condition, message)
    if not condition then error(message) end
end

---@param game table
local function Run(game)
    Check(game ~= nil and game.combat ~= nil, "真实遗迹战斗系统已初始化")
    local controller, world = game.nomiCtl, game.world
    local moves, state, anim = game.combat.moves, game.combat.state, game.combat.anim
    local start = Vector3(22, Terrain.GroundHeight(22, 0) or 6, 0)
    local saved = { position = controller:Position(), automatic = world.updateEnabled,
        observer = moves.observe, weapon = state.GetWeapon(), selection = state.GetSelection() }
    local starts = {}
    local minVelocity = 0.0
    local peakAge = 0.0
    moves.observe = function(kind, event)
        if kind == "start" then starts[event.clip] = (starts[event.clip] or 0) + 1 end
    end

    -- 顺序与 Ruins_HandleSceneUpdate 相同：测量上一物理步→按钮意图→战斗→移动→物理→姿态。
    -- headless 没有窗口焦点，因此测试直接驱动已有战斗输入端口，不伪造操作系统焦点。
    local function Tick(dt, attack, blocked)
        controller:MeasureMotion(dt)
        moves:Update(dt, { allowed = not blocked, axis = Vector3.ZERO, attack = attack == true,
            onGround = controller.cc.onGround, actualSpeed = controller.actualSpeed,
            travel = controller.frameTravel, motionSampleDt = controller.actualDt, normalSpeed = 5 })
        controller:Move(dt, 0, 0, false, false, false, { scale = moves:MoveScale(), motion = moves.motion,
            baseSpeed = 5, facing = moves:Facing(), motionChecked = moves.motionChecked,
            plungeVelocity = moves.plunging and moves.plungeVelocity or nil })
        world:Update(dt, 1)
        controller:Animate(moves.hitstop > 0 and 0 or dt, moves:WeaponInHand())
        anim:Apply()
        controller:GroundFeet(game.foot, dt, moves.clip == "plunge_land")
        local velocity = controller.cc:GetLinearVelocity()
        minVelocity = math.min(minVelocity, velocity.y)
        peakAge = math.max(peakAge, moves.plungeAge or 0)
    end

    local function Prepare(height, dt)
        moves:Cancel("plunge-test-prepare")
        state.SetBusy(false)
        state.FinishTransition()
        if state.GetWeapon() ~= "sword" then
            Check(state.SetWeapon("sword"), "切换测试长剑")
            state.FinishTransition()
        end
        state.Enter("plunge-test")
        state.Activity(true)
        controller.cc:Teleport(start + Vector3(0, .04, 0))
        controller.cc:SetLinearVelocity(Vector3.ZERO)
        controller.cc.desiredVelocity, controller.vel = Vector3.ZERO, Vector3.ZERO
        for _ = 1, 30 do Tick(dt) end
        Check(controller.cc.onGround and math.abs(controller:Position().y - start.y) < .15,
            "测试平台是真实可站立地面")
        controller.cc:Teleport(start + Vector3(0, height, 0))
        controller.cc:SetLinearVelocity(Vector3.ZERO)
        controller.cc.desiredVelocity, controller.vel = Vector3.ZERO, Vector3.ZERO
        world:Update(dt, 1)
        Check(not controller.cc.onGround, "攻击输入前确实离地")
        starts = {}
        minVelocity, peakAge = 0.0, 0.0
        Tick(dt, true)
        Check(moves.plunging and moves.clip == "plunge_start", "空中攻击输入进入下落攻击")
    end

    local function Landing(height, dt)
        Prepare(height, dt)
        local landed, recovered, descentChecked = false, false, false
        for _ = 1, math.ceil(3 / dt) do
            Tick(dt)
            if moves.plunging and moves.plungeAge > Moves.PLUNGE.hover + dt then
                if not descentChecked then
                    Check(moves.plungeSpeed > 0 and moves.plungeVelocity.y < -5,
                        "起手后持久保存的向量包含真实负向下落速度")
                    Check(math.abs(moves.plungeVelocity.y + moves.plungeSpeed) < 1e-6,
                        "速度向量与下落曲线一致，不能只修改Vector3副本")
                    descentChecked = true
                end
                Check(not moves.plungeLanded, "空中不提前标记落地")
            end
            if moves.plungeLanded then
                landed = true
                Check(controller.cc.onGround, "落地动作仅在物理实际接触地面后触发")
                if moves.clip == nil then recovered = true; break end
            end
        end
        print(string.format("PlungeTest: height=%.2f fps=%.0f feet=%.4f minVy=%.3f age=%.3f land=%d recovered=%s",
            height, 1 / dt, controller:Position().y, minVelocity, peakAge,
            starts.plunge_land or 0, tostring(recovered)))
        Check(descentChecked and minVelocity < -5, "实际物理速度向下，未悬停或异常缓降")
        Check(landed and recovered and not moves.plunging, "有限时间内落地并完成恢复")
        Check((starts.plunge_land or 0) == 1, "一次下落只播放一次落地片段")
        Check(math.abs(controller:Position().y - start.y) < .15, "落地后脚底不悬空或陷地")
        Check(moves:MoveScale() == 1 and moves:CanCancel(), "落地结束后解除移动和动作锁")
    end

    local function Cancel(dt)
        Prepare(2, dt)
        Tick(dt, false, true)
        Check(not moves.plunging and moves.clip == nil, "输入中断取消下落攻击")
        local cancelledY = controller:Position().y
        for _ = 1, math.ceil(1.5 / dt) do Tick(dt) end
        Check(controller.cc.onGround and controller:Position().y < cancelledY - .5,
            "取消后恢复正常重力并落地，不残留悬停")
        Check((starts.plunge_land or 0) == 0 and moves:MoveScale() == 1,
            "取消不伪造攻击落地或留下移动锁")
    end

    world.updateEnabled = false
    local ok, err = pcall(function()
        for _, fps in ipairs({ 30, 60, 120 }) do
            for _, height in ipairs({ .8, 2, 8 }) do Landing(height, 1 / fps) end
        end
        Cancel(1 / 60)
    end)
    moves:Cancel("plunge-test-cleanup")
    moves.observe = saved.observer
    state.SetBusy(false)
    state.FinishTransition()
    if state.GetWeapon() ~= saved.weapon then state.SetWeapon(saved.weapon); state.FinishTransition() end
    if saved.selection == "time" then state.Exit("plunge-test-cleanup") end
    controller.cc:Teleport(saved.position)
    controller.cc:SetLinearVelocity(Vector3.ZERO)
    controller.cc.desiredVelocity, controller.vel = Vector3.ZERO, Vector3.ZERO
    world.updateEnabled = saved.automatic
    if not ok then error(err) end
    print(string.format("PlungeTest: PASS checks=%d; real input/controller/landing recovery", checks))
end

if V ~= nil then V.atFrame(8, function() Run(_G["RUINS"]) end) end
