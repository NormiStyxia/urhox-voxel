-- Lua 5.4 offline File/cjson contract doubles; no local Runtime.
package.path = "scripts/?.lua;" .. package.path
local Store = require("combat.WeaponStore")
local Parts = require("combat.WeaponCatalog")
local function Copy(value)
    if type(value)~="table" then return value end
    local result={}
    for k,v in pairs(value) do result[k]=Copy(v) end
    return result
end
local disk, payloads, serial = {}, {}, 0
local closed, opened, fault = 0, 0, ""
_G.FILE_READ, _G.FILE_WRITE = 0, 1
_G.fileSystem={
    FileExists=function(_,path) return disk[path]~=nil end,
    Delete=function(_,path) disk[path]=nil;return true end,
    Rename=function(_,src,dst)
        if not disk[src] or disk[dst] or (fault=='publish' and src:match('%.tmp$')) then return false end
        disk[dst],disk[src]=disk[src],nil
        return true
    end,
}
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
    assert(config.active=="sword" and config.version==3)
    assert(config.sword.appearance=="wing" and config.sword.parts==nil)
    assert(Parts.ValidateWeapon("sword",config.sword) and Parts.ValidateWeapon("bow",config.bow))
end
Default(Store.Load())
local config=Store.Default()
config.active="bow"
config.sword.colors.primary=4
config.bow.colors.accent=6
assert(Store.Save(config))
config.sword.colors.primary=6
local loaded=Store.Load()
assert(loaded.active=="bow" and loaded.sword.colors.primary==4 and loaded.bow.colors.accent==2)
loaded.bow.colors.accent=1
assert(Store.Load().bow.colors.accent==2,"load must not share tables")
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
    function(c) c.version=4 end,
    function(c) c.active="axe" end,
    function(c) c.sword.appearance="removed_id" end,
    function(c) c.bow.appearance="wing" end,
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
local legacy=Store.Default();legacy.version=1;legacy.active='bow'
legacy.sword.appearance=nil;legacy.sword.parts={blade='blade_broad'};legacy.sword.colors.primary=6
legacy.bow.appearance=nil;legacy.bow.parts={tip='tip_crystal'};legacy.bow.colors.accent=6
disk['weapons-v1.json']=cjson.encode(legacy)
local migrated=Store.Load()
assert(migrated.version==3 and migrated.active=='bow' and migrated.sword.colors.primary==6)
assert(migrated.sword.parts==nil and migrated.bow.parts==nil and migrated.bow.colors.accent==2)
assert(Store.Save(migrated))
assert(payloads[disk['weapons-v1.json']].version==3)
assert(opened==closed,"file handles must close on every exit")
print("weapon_store: PASS (round trip, isolation, 7 invalid schemas, I/O failures, closed handles)")

local v2={version=2,active='bow',sword=Parts.DefaultWeapon('sword'),bow=Parts.DefaultWeapon('bow')}
v2.sword.colors.primary=6
disk['weapons-v1.json']=cjson.encode(v2)
local old=Store.Load()
assert(old.active=='bow' and old.sword.colors.primary==6)
assert(old.progress.slots.sword.weapon=='wing' and old.progress.slots.bow.weapon=='thorn')
local rig={config=Store.Default()}
assert(rig.config.progress.ore==999 and rig.config.progress.sand==0)
rig.config.progress.ore=0 -- exercise the insufficient-ore path
local function Slot() return rig.config.progress.slots.sword end
local function Forge(action,id,roll)
    return Store.Forge(rig,'sword',action,id,function() assert(roll);return roll end)
end
assert(not Forge('level') and not Forge('imprint','feather') and not Forge('select','thorn'))
rig.config.progress.ore,rig.config.progress.sand=30,7
assert(Forge('imprint','edge') and Forge('level'))
assert(Forge('refine',nil,100) and Slot().failures.edge==1 and Slot().ranks.edge==1)
assert(Forge('craft','warden') and Slot().levels.iron==2 and Slot().levels.warden==1)
assert(Slot().imprint=='edge' and Slot().failures.edge==1)
assert(Forge('select','iron') and Forge('smelt','warden'))
assert(Slot().weapon=='warden' and Slot().levels.warden==2 and not Slot().levels.iron and rig.config.progress.ore==23)
assert(Forge('refine') and Slot().ranks.edge==2 and Slot().failures.edge==0)
assert(Forge('refine',nil,51) and Slot().failures.edge==1)
assert(Forge('refine',nil,76) and Slot().failures.edge==2)
rig.config=Store.Load()
assert(Slot().failures.edge==2 and Forge('refine') and Slot().ranks.edge==3)
assert(rig.config.progress.sand==2 and not Forge('refine'))
assert(Forge('smelt','wing') and Slot().levels.wing==2 and not Slot().levels.warden)
assert(not Forge('smelt','iron') and not Forge('smelt','wing'))
assert(Forge('imprint','impact') and Forge('guarantee') and rig.config.progress.sand==0)
assert(not Forge('refine') and Slot().ranks.impact==2)
for _,failure in ipairs({'write','publish'}) do
    local progress=rig.config.progress
    fault=failure;assert(not Forge('level'));fault=''
    assert(rig.config.progress==progress)
    local restored=Store.Load().progress
    assert(restored.slots.sword.levels.wing==2 and restored.ore==progress.ore)
end
assert(Forge('level') and Store.Load().progress.slots.sword.levels.wing==3)
assert(opened==closed)
print('weapon_store: progression, migration, smelt, pity and interrupted publish PASS')
