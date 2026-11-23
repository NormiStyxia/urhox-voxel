-- 真实 solver 回归：破坏支柱后，上部必须下落并停在地面，不依赖爆炸冲量。
local V = _G["V"]
local Puzzles = require("ruins.RuinsPuzzles")
local Damage = require("ruins.VoxelDamage")

V.atFrame(5, function()
    local world = _G["RUINS"].world
    local automatic = world:IsUpdateEnabled()
    world:SetUpdateEnabled(false)
    local created = {}
    local function Volume(nx, ny, nz, origin)
        local volume = world:CreateVolume(nx, ny, nz, .25, origin)
        volume.destructible, volume.evictable = true, false
        created[#created + 1] = volume
        return volume
    end
    local oldNoise, oldSpall = world.damageNoise, world.spallChunkVoxels
    world.damageNoise, world.spallChunkVoxels = 0, 0
    local ok, err = pcall(function()
        V.assert(world.gravity.y < -9, "场景使用向下的正常重力")
        V.assert(world.stressBreakFactor > 0, "场景启用结构应力断裂")
        for case = 1, 3 do
            local x = 200 + case * 20
            local floor = Volume(48, 4, 48, Vector3(x - 5, -1, 195))
            floor.destructible = false
            floor:GetGrid():FillBox(0, 0, 0, 47, 3, 47, true)
            world:FinalizeVolume(floor)
            local pillar = Volume(8, 20, 8, Vector3(x, 0, 200))
            local grid = pillar:GetGrid()
            grid:FillBox(3, 0, 3, 4, 11, 4, true)
            grid:FillBox(0, 12, 0, 7, 19, 7, true)
            world:FinalizeVolume(pillar)
            local before = world:GetVolumeCount()
            -- 横切中部 / 整段底座全毁 / 只削去边角而仍有支撑。
            local center = case == 3 and Vector3(x + .125, 4, 200.125)
                or Vector3(x + 1, case == 1 and 1.5 or 1.0, 201)
            Damage.Volume(world, pillar, center, case == 1 and .8 or (case == 2 and 2.05 or .3), 100)
            Puzzles.UpdateStructuralSupport() -- 与正式玩法使用同一个伤害后支撑检查。
            local pieces = {}
            for i = 0, world:GetVolumeCount() - 1 do
                local volume = world:GetVolume(i)
                if volume and volume ~= floor then
                    local at = volume:GetNode().worldPosition
                    if math.abs(at.x - x) < 4 and math.abs(at.z - 200) < 4 and volume:GetSolidCount() > 4 then
                        local bottom = math.huge
                        local cells = volume:GetGrid()
                        local dims = cells:GetDimensions()
                        for gx = 0, dims.x - 1 do for gy = 0, dims.y - 1 do for gz = 0, dims.z - 1 do
                            if cells:IsSolid(gx, gy, gz) then bottom = math.min(bottom, gy * volume.voxelSize) end
                        end end end
                        pieces[#pieces + 1] = {volume = volume, start = at, bottom = bottom, dynamic = not volume:IsStatic()}
                        if volume ~= pillar then created[#created + 1] = volume end
                        print(string.format("SupportTest case=%d id=%d static=%s start=%s solid=%d before=%d", case, volume.volumeId, tostring(volume:IsStatic()), tostring(at), volume:GetSolidCount(), before))
                    end
                end
            end
            V.assert(#pieces > 0, "底座破坏后保留真实上部体素")
            for step = 1, 360 do world:Update(1 / 60) end
            local fallen = false
            for _, piece in ipairs(pieces) do
                local at = piece.volume:GetNode().worldPosition
                print(string.format("SupportTest case=%d id=%d end=%s static=%s speed=%.4f", case, piece.volume.volumeId, tostring(at), tostring(piece.volume:IsStatic()), piece.volume.linearVelocity:Length()))
                if case == 3 then
                    local delta = at - piece.start --[[@as Vector3]]
                    V.assert(piece.volume:IsStatic() and delta:Length() < .01, "底座仍有支撑时不误坍塌")
                elseif piece.dynamic then
                    V.assert(at.y < piece.start.y - .5, "失去底座的上部必须真实下落")
                    V.assert(at.y + piece.bottom > -.3 and at.y + piece.bottom < 1, "实心下表面落在地面而非悬空或穿透")
                    V.assert(piece.volume.linearVelocity:Length() < .2, "落地后稳定停止")
                    fallen = true
                end
            end
            V.assert(case == 3 or fallen, "检测到失去支撑的上部碎块")
        end
        V.assert(Puzzles.lastSevered ~= nil, "谜题接收到结构断裂事件")
    end)
    for _, volume in ipairs(created) do
        local node = volume:GetNode()
        world:RemoveVolume(volume)
        volume:Dispose()
        if node then node:Dispose() end
    end
    world.damageNoise, world.spallChunkVoxels = oldNoise, oldSpall
    world:SetUpdateEnabled(automatic)
    if not ok then error(err) end
end)
