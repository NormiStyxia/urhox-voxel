-- Lua 5.4 offline File/cjson contract doubles; no local Runtime.
package.path = "scripts/?.lua;" .. package.path
local Store = require("combat.WeaponStore")
local Parts = require("combat.WeaponParts")
local function Copy(value)
    if type(value)~="table" then return value end
    local result={}
    for k,v in pairs(value) do result[k]=Copy(v) end
    return result
end
local disk, payloads, serial = {}, {}, 0
local closed, opened, fault = 0, 0, ""
_G.FILE_READ, _G.FILE_WRITE = 0, 1
_G.cjson = {
    encode=function(data)
        if fault=="encode" then error("encode failed") end
        serial=serial+1
        local key="json:"..serial
        payloads[key]=Copy(data)
        return key
    end,
    decode=function(raw)
        if not payloads[raw] then error("bad JSON") end
        return Copy(payloads[raw])
    end,
}
_G.File=function(path,mode)
    if fault=="constructor" then error("no filesystem") end
    if fault=="nil" then return nil end
    opened=opened+1
    return {
        IsOpen=function() return fault~="open" and (mode==FILE_WRITE or disk[path]~=nil) end,
        GetSize=function() return fault=="oversize" and 20000 or #(disk[path] or "") end,
        ReadString=function() if fault=="read" then error("read failed") end; return disk[path] end,
        WriteString=function(_,raw)
            if fault=="write" then return false end
            disk[path]=raw
            return true
        end,
        Close=function() closed=closed+1 end,
    }
end
local function Default(config)
    assert(config.active=="sword" and config.version==1)
    assert(config.sword.parts.blade=="blade_straight")
    assert(Parts.ValidateWeapon("sword",config.sword) and Parts.ValidateWeapon("bow",config.bow))
end
Default(Store.Load())
local config=Store.Default()
config.active="bow"
config.sword.parts.blade="blade_broad"
config.bow.colors.accent=6
assert(Store.Save(config))
config.sword.parts.blade="blade_rapier"
local loaded=Store.Load()
assert(loaded.active=="bow" and loaded.sword.parts.blade=="blade_broad" and loaded.bow.colors.accent==6)
loaded.bow.colors.accent=1
assert(Store.Load().bow.colors.accent==6,"load must not share tables")
local validRaw=disk["weapons-v1.json"]
for _, kind in ipairs({"nil","constructor","open","read","oversize"}) do
    fault=kind; Default(Store.Load())
end
for _, kind in ipairs({"nil","constructor","open","write","encode"}) do
    fault=kind; assert(not Store.Save(config))
end
fault=""
assert(disk["weapons-v1.json"]==validRaw)
for _, change in ipairs({
    function(c) c.version=2 end,
    function(c) c.active="axe" end,
    function(c) c.sword.parts.blade="removed_id" end,
    function(c) c.bow.parts.grip="sword_grip_leather" end,
    function(c) c.sword.colors.primary=1.5 end,
    function(c) c.bow.colors=false end,
    function(c) c.sword=nil end,
}) do
    local bad=Store.Default(); change(bad)
    assert(not Store.Save(bad))
    disk["weapons-v1.json"]=cjson.encode(bad)
    Default(Store.Load())
end
for _, malformed in ipairs({false,17,"text"}) do
    disk["weapons-v1.json"]=cjson.encode(malformed); Default(Store.Load())
end
disk["weapons-v1.json"]="broken"; Default(Store.Load())
local defaults=Store.Default(); defaults.sword.colors.primary=6
assert(Store.Default().sword.colors.primary==3)
for _,weapon in ipairs({'sword','bow'}) do for _,preset in ipairs(Parts.Presets) do
    local loadout=Store.Default();loadout[weapon]=Store.Preset(weapon,preset.id)
    assert(Store.Save(loadout))
    local roundTrip=Store.Load()
    for slot,id in pairs(loadout[weapon].parts) do assert(roundTrip[weapon].parts[slot]==id) end
end end
assert(opened==closed,"file handles must close on every exit")
print("weapon_store: PASS (round trip, isolation, 7 invalid schemas, I/O failures, closed handles)")
