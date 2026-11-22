-- File/cjson sandbox persistence. Web refresh clears the engine's in-memory save.
local Catalog = require("combat.WeaponCatalog")
local Store = {}
local SAVE_PATH = "weapons-v1.json"
local PENDING_PATH = SAVE_PATH..'.tmp'
local BACKUP_PATH = SAVE_PATH..'.bak'
local MAX_SAVE_BYTES = 16384

local function Progress(legacy)
    local progress={ore=0,sand=0,slots={}}
    for _,class in ipairs(Catalog.Classes) do
        local items=Catalog.Weapons[class]
        local id=items[legacy and #items or 1].id
        local slot={weapon=id,imprint='',levels={[id]=1},ranks={},failures={}}
        for _,imprint in ipairs(Catalog.Imprints[class]) do
            slot.ranks[imprint.id]=1
            slot.failures[imprint.id]=0
        end
        progress.slots[class]=slot
    end
    return progress
end

function Store.Default()
    return {version=3,sword=Catalog.DefaultWeapon('sword'),bow=Catalog.DefaultWeapon('bow'),active='sword',progress=Progress(false)}
end

local function Integer(n,lo,hi)
    return type(n)=='number' and n%1==0 and n>=lo and n<=hi
end
local function ReadProgress(source)
    if type(source)~='table' or type(source.slots)~='table' or not Integer(source.ore,0,999999) or not Integer(source.sand,0,999999) then return nil end
    local result={ore=source.ore,sand=source.sand,slots={}}
    for _,class in ipairs(Catalog.Classes) do
        local slot=source.slots[class]
        if type(slot)~='table' or type(slot.levels)~='table' or type(slot.ranks)~='table' or type(slot.failures)~='table' then return nil end
        local copy={weapon=slot.weapon,imprint=slot.imprint,levels={},ranks={},failures={}}
        for _,item in ipairs(Catalog.Weapons[class]) do
            local level=slot.levels[item.id]
            if level~=nil and not Integer(level,1,Catalog.LevelCap) then return nil end
            copy.levels[item.id]=level
        end
        if not copy.levels[copy.weapon] then return nil end
        for _,item in ipairs(Catalog.Imprints[class]) do
            local rank,failures=slot.ranks[item.id],slot.failures[item.id]
            if not Integer(rank,1,3) or not Integer(failures,0,rank==3 and 0 or #Catalog.RefineChance[rank]-1) then return nil end
            copy.ranks[item.id],copy.failures[item.id]=rank,failures
        end
        if copy.imprint~='' and not copy.ranks[copy.imprint] then return nil end
        result.slots[class]=copy
    end
    return result
end

-- Both shipped formats used the same two legendary appearances. Preserve those
-- items and the approved colours when introducing the inventory.
function Store.Normalize(config,allowLegacy)
    if type(config)~='table' or (config.active~='sword' and config.active~='bow') then return nil end
    local legacy=allowLegacy and (config.version==1 or config.version==2)
    if config.version~=3 and not legacy then return nil end
    local progress=legacy and Progress(true) or ReadProgress(config.progress)
    if not progress then return nil end
    local result={version=3,active=config.active,progress=progress}
    for _,weapon in ipairs({'sword','bow'}) do
        local entry=config[weapon]
        if type(entry)~='table' then return nil end
        if config.version==1 then entry={appearance=Catalog.Definitions[weapon].appearance,colors=entry.colors} end
        result[weapon]=Catalog.CopyAppearance(weapon,entry)
        if not result[weapon] then return nil end
        -- The selected inventory item chooses the authored high-detail visual.
        -- Keep the legacy appearance field for voxel/fallback compilation.
        result[weapon].modelId=progress.slots[weapon].weapon
    end
    return result
end

-- Operate on a private draft. A failed save or rejected action leaves the live
-- inventory untouched. Failed refinement rolls are saved like successful ones.
function Store.Forge(rig,class,action,id,random)
    local config=Store.Normalize(rig.config)
    if not config or not Catalog.Weapons[class] then return false,'装备配置无效' end
    local progress=config.progress
    local slot=progress.slots[class]
    local old,tier=Catalog.Find(Catalog.Weapons[class],slot.weapon)
    local level=slot.levels[old.id]
    local message
    if action=='select' then
        if not slot.levels[id] then return false,'尚未打造' end
        slot.weapon=id
    elseif action=='imprint' then
        if not slot.ranks[id] then return false,'时印类型不符' end
        slot.imprint=id
    elseif action=='craft' or action=='smelt' then
        local item,target=Catalog.Find(Catalog.Weapons[class],id)
        if not item or target>tier+1 then return false,'无法打造这件武器' end
        local owned=slot.levels[id]
        if owned and (action=='craft' or owned>=level) then return false,'武器已拥有，当前等级无需继承' end
        if action=='smelt' and target~=tier+1 then return false,'只能将当前武器熔入同类下一阶' end
        local cost=owned and 0 or Catalog.CraftCost[target]
        if progress.ore<cost then return false,'强化矿不足' end
        progress.ore=progress.ore-cost
        slot.levels[id]=action=='smelt' and level or 1
        if action=='smelt' then slot.levels[old.id]=nil end
        slot.weapon=id
    elseif action=='level' then
        if level>=Catalog.LevelCap then return false,'武器已满级' end
        if progress.ore<level then return false,'强化矿不足' end
        progress.ore=progress.ore-level
        slot.levels[old.id]=level+1
    elseif action=='refine' or action=='guarantee' then
        local seal=slot.imprint
        local rank=slot.ranks[seal]
        if not rank or rank>=3 then return false,'请选择可精炼的时印' end
        local chance=Catalog.RefineChance[rank][slot.failures[seal]+1]
        local cost=action=='guarantee' and chance<100 and 2 or 1
        if progress.sand<cost then return false,'淬炼砂不足' end
        progress.sand=progress.sand-cost
        if action=='guarantee' or chance==100 or (random or math.random)(100)<=chance then
            slot.ranks[seal],slot.failures[seal]=rank+1,0
            message='精炼成功'
        else
            slot.failures[seal]=slot.failures[seal]+1
            message=('精炼未成，下次成功率 %d%%'):format(Catalog.RefineChance[rank][slot.failures[seal]+1])
        end
    else return false,'未知锻造操作' end
    if not Store.Save(config) then return false,'保存失败，材料已保留' end
    rig.config.progress=progress
    return true,message or '已保存'
end

---@param file File?
local function Close(file)
    if file then pcall(function() file:Close() end) end
end

---@return table
function Store.Load()
    ---@type File?
    local file = nil
    local ok, result = pcall(function()
        -- 首次进入没有存档：先判断存在，避免引擎对不存在的文件打印 ERROR（Could not open file）。
        local path=SAVE_PATH
        if not fileSystem:FileExists(path) then
            if not fileSystem:FileExists(BACKUP_PATH) then return nil end
            path=BACKUP_PATH
        end
        file = File(path, FILE_READ)
        if not file or not file:IsOpen() then return nil end
        if file:GetSize()>MAX_SAVE_BYTES then return nil end
        local raw = file:ReadString()
        if type(raw)~="string" or #raw>MAX_SAVE_BYTES then return nil end
        return Store.Normalize(cjson.decode(raw),true)
    end)
    Close(file)
    if ok and result then return result end
    return Store.Default()
end

---@param config table
---@return boolean saved
function Store.Save(config)
    ---@type File?
    local file = nil
    local ok, result = pcall(function()
        local normalized = Store.Normalize(config)
        if not normalized then return false end
        -- Encode before opening: an invalid config must not truncate a valid save.
        local raw = cjson.encode(normalized)
        if #raw>MAX_SAVE_BYTES then return false end
        file = File(PENDING_PATH, FILE_WRITE)
        if not file or not file:IsOpen() then return false end
        if not file:WriteString(raw) then return false end
        file:Close();file=nil
        -- Rename only to vacant destinations, including on Windows. Load can
        -- restore the previous inventory if interrupted between the two moves.
        if fileSystem:FileExists(SAVE_PATH) then
            if fileSystem:FileExists(BACKUP_PATH) and not fileSystem:Delete(BACKUP_PATH) then return false end
            if not fileSystem:Rename(SAVE_PATH,BACKUP_PATH) then return false end
        end
        return fileSystem:Rename(PENDING_PATH,SAVE_PATH)
    end)
    Close(file)
    return ok and result==true
end
return Store
