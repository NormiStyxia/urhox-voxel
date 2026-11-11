-- 临时眼部回归：读取真正体素化的侧脸，确认豆豆眼和大号黑白眼；验证后删除。
local Variants = require("dragon.DragonVariants")
local Sculpt = require("dragon.DragonSculpt")

function Start()
    for _, id in ipairs({ "small", "large" }) do
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
        local black, white = 0, 0
        for _, v in pairs(visible) do
            local _, best = Sculpt.EvalField(prims, v[1] * s, (v[2] + 0.5) * s, v[3] * s)
            if best ~= nil and best.paint and best.prio == 1.0 then
                eyes[#eyes + 1] = v
                if v[4] == spec.PAL.PUPIL then black = black + 1 end
                if v[4] == (id == "small" and 57 or 56) then white = white + 1 end
            end
        end
        assert(black > 0 and white > 0, id .. ": missing eye colors")
        if id == "small" then assert(black > white, "small: bean pupil must dominate") end
        if id == "large" then
            assert(spec.PALETTE[56][1] > 0.95 and spec.PALETTE[56][3] > 0.95, "large: sclera must be white")
            assert(spec.EMISSIVE[56][4] == 0, "large: yellow emission remains")
        end
        print("EYE_GRID " .. cjson.encode({ variant = id, voxels = vox, eyes = eyes, palette = spec.PALETTE }))
        print(string.format("EYE_CHECK %s: black=%d white=%d", id, black, white))
    end
    print("EYE_CHECK complete")
end

function Stop() end
