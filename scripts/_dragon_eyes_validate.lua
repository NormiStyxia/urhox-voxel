-- 临时测试：检查三型号实际头部体素，导出侧面眼睛像素；测试后删除。
local Variants = require("dragon.DragonVariants")
local Sculpt = require("dragon.DragonSculpt")

function Start()
    for _, id in ipairs({ "small", "medium", "large" }) do
        local spec = Variants.Get(id)
        local prims = spec.Expand()
        local s = spec.VoxelSizeOf("head")
        local vox = Sculpt.VoxelizePart(prims, "head", s, { -0.5 * s, 0, -0.5 * s }, { overlap = false })
        local visible = {}
        for _, v in ipairs(vox) do
            local key = v[2] .. ":" .. v[3]
            local old = visible[key]
            if old == nil or v[1] > old[1] then visible[key] = v end
        end
        local eyes = {}
        local black, white, gold = 0, 0, 0
        for _, v in pairs(visible) do
            local x, y, z = v[1] * s, (v[2] + 0.5) * s, v[3] * s
            local _, best = Sculpt.EvalField(prims, x, y, z)
            if best ~= nil and best.paint and best.prio == 1.0 then
                eyes[#eyes + 1] = v
                if v[4] == spec.PAL.PUPIL then black = black + 1 end
                if v[4] == 57 then white = white + 1 end
                if v[4] == 56 then gold = gold + 1 end
            end
        end
        if id == "small" then
            assert(black > 0 and white > black, "small: eye must be mostly white with black inner strip")
            for _, v in ipairs(eyes) do assert(v[4] == 57 or v[4] == spec.PAL.PUPIL, "small: unexpected eye color") end
            assert(spec.EMISSIVE[56][4] == 0 and spec.EMISSIVE[57][4] == 0, "small: eye emission")
        elseif id == "large" then
            assert(black > 0 and gold > 0, "large: missing black inner strip or gold outer area")
        end
        print("EYE_GRID " .. cjson.encode({ variant = id, size = s, voxels = vox, eyes = eyes, palette = spec.PALETTE }))
        print(string.format("EYE_CHECK %s: %d head voxels, eye visible black=%d white=%d gold=%d", id, #vox, black, white, gold))
    end
    print("EYE_CHECK complete")
end

function Stop() end
