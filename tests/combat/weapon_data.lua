-- Run with Lua 5.4 from the project root, no engine required.
package.path = "scripts/?.lua;" .. package.path
local Parts = require("combat.WeaponParts")
local seen = {}
assert(Parts.VOXEL_SIZE==0.03)
assert(#Parts.All==19)
for _, part in ipairs(Parts.All) do
    assert(not seen[part.id], "duplicate id")
    seen[part.id] = true
    assert(Parts.Get(part.id)==part)
    assert(#part.name>0 and #part.desc>0)
    local width, depth, count, colors = #part.voxels[1][1], #part.voxels[1], 0, {}
    for _, layer in ipairs(part.voxels) do
        assert(#layer==depth, part.id.." depth")
        for _, row in ipairs(layer) do
            assert(type(row)=="string" and #row==width,part.id.." row width")
            for char in row:gmatch(".") do
                assert(char=="." or part.palette[char], part.id.." channel")
                if char~="." then count=count+1; colors[char]=true end
            end
        end
    end
    assert(count>0 and count<=4000,part.id.." budget")
    local colorCount=0
    for _ in pairs(colors) do colorCount=colorCount+1 end
    assert(colorCount>=2,part.id.." flat shading")
    for _, vec in pairs(part.sockets) do
        assert(#vec==3)
        for _, value in ipairs(vec) do assert(math.type(value)=="integer") end
    end
    for _, value in ipairs(part.origin) do assert(math.type(value)=="integer") end
    local good,bad=false,false
    local lowerBetter={charge=true,draw=true,spread=true,chargeMultiplier=true,drawMultiplier=true,spreadMultiplier=true}
    for key,value in pairs(part.stats) do
        assert(type(value)=="number" and value==value)
        local delta=value-((key:find('Multiplier') and key~='crystalDamageMultiplier') and 1 or 0)
        if lowerBetter[key] then delta=-delta end
        good=good or delta>0;bad=bad or delta<0
    end
    assert(good and bad,part.id..' must have both a benefit and a cost')
end
for weapon, slots in pairs(Parts.Slots) do
    assert(#Parts.Presets==3)
    for _,preset in ipairs(Parts.Presets) do
        local first=assert(Parts.Preset(weapon,preset.id))
        assert(Parts.ValidateWeapon(weapon,first))
        first.colors.primary=6
        assert(Parts.Preset(weapon,preset.id).colors.primary~=6,'presets must be independent')
    end
    local config = Parts.DefaultWeapon(weapon)
    assert(Parts.ValidateWeapon(weapon,config))
    for _, slot in ipairs(slots) do
        local options=Parts.GetOptions(weapon,slot)
        assert(#options>=2 and #options<=3)
        for _, part in ipairs(options) do
            config.parts[slot]=part.id
            assert(Parts.ValidateWeapon(weapon,config))
        end
    end
    config.colors.accent=7
    assert(not Parts.ValidateWeapon(weapon,config))
    config.colors.accent=0/0
    assert(not Parts.ValidateWeapon(weapon,config))
end
assert(Parts.Preset('axe','fast')==nil and Parts.Preset('sword','missing')==nil)
local wrong = Parts.DefaultWeapon("sword")
wrong.parts.grip = "bow_grip_leather"
assert(not Parts.ValidateWeapon("sword",wrong))
assert(not Parts.ValidateWeapon("sword",false))
-- A single-voxel straight string spans the full limb height.
for _, part in ipairs(Parts.GetOptions("bow","limbs")) do
    for _, layer in ipairs(part.voxels) do
        local stringRow = assert(layer[1]) -- -Z, not -X
        assert(stringRow:sub(2,2)~=".")
    end
end
print("weapon_data: PASS (19 parts, 7 slots, channels/sockets/strings/validation)")
