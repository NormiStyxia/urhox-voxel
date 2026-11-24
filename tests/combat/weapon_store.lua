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
local function Slot(class) return rig.config.progress.slots[class or 'sword'] end
local function Forge(action,id,option,roll)
    return Store.Forge(rig,'sword',action,id,option,roll and function() return roll end)
end
local imprintTotal=0
for _,class in ipairs(Parts.Classes) do
    local slot=Slot(class)
    for i,item in ipairs(Parts.Weapons[class]) do assert(slot.levels[item.id]==(i==1 and 1 or nil)) end
    for _,role in ipairs(Parts.ImprintRoles) do
        assert(Parts.Find(Parts.Imprints[class],slot.imprints[role]).role==role)
        local variants=0
        for _,item in ipairs(Parts.Imprints[class]) do if item.role==role then variants=variants+1 end end
        assert(variants==2)
        imprintTotal=imprintTotal+variants
    end
end
assert(imprintTotal==18 and rig.config.progress.ore==3 and rig.config.progress.sand==1)
local newQuote=assert(Store.ForgeQuote(rig.config.progress,'sword','craft','warden'))
assert(newQuote.cost==6 and newQuote.level==1 and newQuote.source==nil)
local inheritQuote=assert(Store.ForgeQuote(rig.config.progress,'sword','smelt','warden'))
assert(inheritQuote.cost==6 and inheritQuote.level==1 and inheritQuote.source.id=='iron')
assert(not Store.ForgeQuote(rig.config.progress,'sword','craft','iron'))
assert(not Store.ForgeQuote(rig.config.progress,'sword','craft','wing'))
assert(not Store.ForgeQuote(rig.config.progress,'sword','smelt','iron','iron'))
assert(not Store.ForgeQuote(rig.config.progress,'sword','smelt','wing','iron'))
assert(Store.FodderCount(Slot(),'edge','edge')==1)
assert(Store.FodderCount(Slot(),'reach','edge')==0)
assert(not Forge('craft','warden') and not Forge('imprint','impact') and not Forge('imprint','feather'))
assert(not Forge('select','wing') and not Forge('refine','edge','reach'))

local draft=assert(Store.Edit(rig.config,'sword','level','iron'))
assert(Slot().levels.iron==1 and draft.progress.slots.sword.levels.iron==2)
assert(draft.progress.ore==2 and rig.config.progress.ore==3)
local before=Slot()
assert(Forge('refine','edge','edge',100) and Slot().ranks.edge==1 and Slot().failures.edge==1)
assert(before.counts.edge==2 and Slot().counts.edge==1 and Slot().imprints.edge=='edge')
assert(rig.config.progress.sand==0 and Store.RefineChance(Slot(),'edge')==100)
assert(Store.FodderCount(Slot(),'edge','edge')==0)
assert(not Forge('refine','edge','edge') and not Forge('guarantee','edge','edge'))

-- Six normal kills grant all alternate imprints and start replenishing the starter copies.
for _=1,6 do assert(Store.RewardKill(rig)) end
for _,class in ipairs(Parts.Classes) do
    for _,item in ipairs(Parts.Imprints[class]) do assert(Slot(class).counts[item.id]>0,item.id) end
end
assert(rig.config.progress.ore==21 and rig.config.progress.sand==12)
assert(Forge('level','iron') and Forge('craft','warden'))
assert(Slot().weapon=='iron' and rig.config.sword.modelId=='iron' and Slot().levels.warden==1)
assert(Forge('level','warden') and Slot().weapon=='iron' and Slot().levels.warden==2)
assert(not Store.ForgeQuote(rig.config.progress,'sword','smelt','warden','iron'))
assert(Forge('imprint','ruishi') and Slot().imprints.edge=='ruishi' and Slot().imprints['break']=='reach')
assert(Slot().imprints.time=='jiying' and Store.FodderCount(Slot(),'edge','edge')==1)
assert(Forge('refine','edge','impact') and Slot().ranks.edge==2 and Slot().counts.impact==0)
assert(Forge('refine','edge','ningshi',51) and Store.RefineChance(Slot(),'edge')==75)
assert(not Forge('refine','edge','ruishi',76),'equipped copy is protected')
assert(Forge('imprint','edge') and Forge('refine','edge','ruishi',76) and Store.RefineChance(Slot(),'edge')==100)
rig.config=Store.Load()
assert(Slot().failures.edge==2 and Slot().imprints.edge=='edge')
assert(Store.RewardKill(rig) and Store.RefineChance(Slot(),'edge')==100)
assert(Forge('refine','edge','reach') and Slot().ranks.edge==3 and Store.RefineChance(Slot(),'edge')==nil)
assert(not Forge('refine','edge','reach'))

local ore=rig.config.progress.ore
assert(Forge('level','iron'))
local upgradeQuote=assert(Store.ForgeQuote(rig.config.progress,'sword','smelt','warden','iron'))
assert(upgradeQuote.cost==0 and upgradeQuote.level==3 and upgradeQuote.source.id=='iron')
assert(Forge('smelt','warden','iron'))
assert(Slot().weapon=='warden' and Slot().levels.warden==3 and not Slot().levels.iron)
assert(rig.config.progress.ore==ore-2 and Slot().ranks.edge==3)
assert(Forge('craft','iron') and Slot().weapon=='warden')
assert(Forge('select','iron') and Slot().weapon=='iron' and rig.config.active=='sword')
assert(not Forge('smelt','wing','iron'))
rig.config.progress.ore=30
assert(Forge('smelt','wing','warden') and Slot().levels.wing==3 and Slot().weapon=='iron')
assert(not Forge('smelt','iron','wing') and not Forge('smelt','warden','wing'))
assert(Forge('select','wing'))
for _,failure in ipairs({'write','publish'}) do
    local configBefore=rig.config
    fault=failure;assert(not Forge('level','wing'));fault=''
    assert(rig.config==configBefore)
    local restored=Store.Load().progress
    assert(restored.slots.sword.levels.wing==3 and restored.ore==configBefore.progress.ore)
end
assert(Forge('level','wing') and Store.Load().progress.slots.sword.levels.wing==4)
assert(opened==closed)
print('weapon_store: real unlocks, three slots, 18 drops, draft isolation, fodder, pity, smelt and interrupted publish PASS')

local Materials=require('combat.MaterialCatalog')
local preMaterials=Store.Default()
preMaterials.progress.materials,preMaterials.progress.trainingClaims,preMaterials.progress.siteClaims=nil,nil,nil
preMaterials.progress.ore,preMaterials.progress.sand=47,26
disk['weapons-v1.json']=cjson.encode(preMaterials)
rig.config=Store.Load()
assert(Materials.Count(rig.config.progress,'wood_resin')==0 and Materials.Count(rig.config.progress,'ore')==47)
local imprintCursor=rig.config.progress.imprintDrops
fault='publish'
assert(not Store.AddMaterial(rig,'wood_resin',1,'wood_spirit'))
assert(not next(rig.config.progress.materials) and not next(rig.config.progress.trainingClaims))
fault=''
assert(Store.AddMaterial(rig,'wood_resin',1,'wood_spirit'))
assert(Store.AddMaterial(rig,'timber',2,nil,'site:east_ancient'))
assert(Store.AddMaterial(rig,'crystal_ore',1,nil,'site:court_vein'))
assert(not Store.AddMaterial(rig,'crystal_ore',2,nil,'site:south_vein'))
assert(not Store.AddMaterial(rig,'ore',1))
rig.config=Store.Load()
assert(rig.config.progress.imprintDrops==imprintCursor and Materials.Count(rig.config.progress,'sand')==26)
assert(not Store.AddMaterial(rig,'wood_resin',1,'wood_spirit'))
assert(not Store.AddMaterial(rig,'timber',2,nil,'site:east_ancient'))
assert(Store.AddMaterial(rig,'wood_resin',1))
assert(Forge('level','iron'))
assert(Store.RewardKill(rig))
rig.config=Store.Load()
assert(Materials.Count(rig.config.progress,'ore')==49 and Materials.Count(rig.config.progress,'sand')==28)
assert(Materials.Count(rig.config.progress,'wood_resin')==2 and Materials.Count(rig.config.progress,'timber')==2)
assert(Materials.Count(rig.config.progress,'crystal_ore')==1)
assert(rig.config.progress.siteClaims['site:court_vein'] and rig.config.progress.trainingClaims.wood_spirit)
print('weapon_store: materials migration, inventory and source receipts, retry, and forge integration PASS')

local cloudDisk, readCallback, writeCallback, writeCount
GetPlatform=function() return 'Web' end
fileSystem.HasPersistentFS=function() return false end
clientCloud={userId=1001}
function clientCloud:Get(key,callbacks) assert(key=='weapons_v1');readCallback=callbacks end
function clientCloud:Set(key,raw,callbacks)
    assert(key=='weapons_v1' and not writeCallback)
    writeCount=(writeCount or 0)+1
    writeCallback=function(fail)
        writeCallback=nil
        if fail then callbacks.error() else cloudDisk=raw;callbacks.ok() end
    end
end
local boots=0
local function Ready() boots=boots+1;rig.config=Store.Load() end
Store.Prepare(Ready);assert(boots==0)
readCallback.ok({weapons_v1=cjson.encode(rig.config)})
assert(boots==1 and rig.config.progress.materials.wood_resin==2)
assert(Store.AddMaterial(rig,'wood_resin',1))
Store.Update(0);assert(writeCallback and writeCount==1)
assert(Store.AddMaterial(rig,'wood_resin',1))
Store.Update(0);assert(writeCount==1,'wait for the previous cloud write')
writeCallback(true);Store.Update(1);assert(writeCount==1)
Store.Update(4);assert(writeCount==2);writeCallback(false)
Store.Stop();disk={}
Store.Prepare(Ready);readCallback.ok({weapons_v1=cloudDisk})
assert(boots==2 and rig.config.progress.materials.wood_resin==4,'reload the most recent count')
assert(rig.config.progress.trainingClaims.wood_spirit and rig.config.progress.siteClaims['site:court_vein'])
Store.Stop();Store.Prepare(Ready);Store.Update(4.1)
assert(boots==3)
readCallback.ok({weapons_v1=cloudDisk});assert(boots==3,'ignore a late cloud baseline')
assert(Store.AddMaterial(rig,'timber',1));Store.Update(10)
assert(writeCount==2,'an unconfirmed baseline must not overwrite saved cloud progress')
Store.Stop()
print('weapon_store: Web cloud fallback snapshot, sequential retry, reload and safe timeout PASS (SDK double)')
