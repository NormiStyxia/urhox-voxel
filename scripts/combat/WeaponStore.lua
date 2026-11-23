-- File/cjson sandbox persistence. Web refresh clears the engine's in-memory save.
local Catalog = require("combat.WeaponCatalog")
local Store = {}
local SAVE_PATH = "weapons-v1.json"
local PENDING_PATH = SAVE_PATH..'.tmp'
local BACKUP_PATH = SAVE_PATH..'.bak'
local MAX_SAVE_BYTES = 16384
local MAX_COUNT = 999999
local REWARD_ORE, REWARD_SAND = 3, 2
local starters, dropOrder, imprintById, imprintClass = {}, {}, {}, {}
for _,class in ipairs(Catalog.Classes) do
    local byRole={}
    starters[class]=byRole
    for _,item in ipairs(Catalog.Imprints[class]) do
        imprintById[item.id]=item
        imprintClass[item.id]=class
        if byRole[item.role] then dropOrder[#dropOrder+1]={class=class,item=item}
        else byRole[item.role]=item.id end
    end
end
-- Give out the alternate imprints first, two per kill, then the starting types.
for _,class in ipairs(Catalog.Classes) do
    for _,role in ipairs(Catalog.ImprintRoles) do
        dropOrder[#dropOrder+1]={class=class,item=imprintById[starters[class][role]]}
    end
end

local function Progress(legacy)
    local progress={ore=legacy and 0 or 3,sand=1,imprintDrops=0,slots={}}
    for _,class in ipairs(Catalog.Classes) do
        local items=Catalog.Weapons[class]
        local id=items[legacy and #items or 1].id
        local slot={weapon=id,imprints={},levels={[id]=1},counts={},ranks={},failures={}}
        for _,role in ipairs(Catalog.ImprintRoles) do
            local seal=starters[class][role]
            slot.imprints[role]=seal
            slot.counts[seal]=seal=='edge' and 2 or 1
        end
        for _,imprint in ipairs(Catalog.Imprints[class]) do
            local seal=imprint.id
            slot.counts[seal]=slot.counts[seal] or 0
            slot.ranks[seal],slot.failures[seal]=1,0
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
    if type(source)~='table' or type(source.slots)~='table' or not Integer(source.ore,0,MAX_COUNT)
        or not Integer(source.sand,0,MAX_COUNT) then return nil end
    local cursor=source.imprintDrops
    if cursor==nil then cursor=0 end
    if not Integer(cursor,0,#dropOrder-1) then return nil end
    local result={ore=source.ore,sand=source.sand,imprintDrops=cursor,slots={}}
    for _,class in ipairs(Catalog.Classes) do
        local slot=source.slots[class]
        if type(slot)~='table' or type(slot.levels)~='table' or type(slot.ranks)~='table' or type(slot.failures)~='table' then return nil end
        local copy={weapon=slot.weapon,imprints={},levels={},counts={},ranks={},failures={}}
        for _,item in ipairs(Catalog.Weapons[class]) do
            local level=slot.levels[item.id]
            if level~=nil and not Integer(level,1,Catalog.LevelCap) then return nil end
            copy.levels[item.id]=level
        end
        if not copy.levels[copy.weapon] then return nil end
        local old=slot.imprints==nil and slot.counts==nil
        if not old and (type(slot.imprints)~='table' or type(slot.counts)~='table') then return nil end
        local equipped=old and {} or slot.imprints
        if old and slot.imprint~='' then
            local imprint=Catalog.Find(Catalog.Imprints[class],slot.imprint)
            if not imprint then return nil end
            equipped[imprint.role]=imprint.id
        end
        for _,item in ipairs(Catalog.Imprints[class]) do
            local id=item.id
            local rank,failures=slot.ranks[id],slot.failures[id]
            local count=old and ((rank~=nil) and 1 or 0) or slot.counts[id]
            if old and rank==nil and failures==nil then rank,failures=1,0 end
            if not Integer(count,0,MAX_COUNT) or not Integer(rank,1,3)
                or not Integer(failures,0,rank==3 and 0 or #Catalog.RefineChance[rank]-1) then return nil end
            copy.counts[id],copy.ranks[id],copy.failures[id]=count,rank,failures
        end
        for _,role in ipairs(Catalog.ImprintRoles) do
            local id=equipped[role]
            if old and id==nil then id='' end
            local item=imprintById[id]
            if id~='' and (not item or item.role~=role or (copy.counts[id] or 0)==0) then return nil end
            copy.imprints[role]=id
        end
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

-- The inventory count includes the equipped copy. An imprint can feed an
-- upgrade only when one copy remains for its slot or for the upgrade itself.
function Store.FodderCount(slot,id,targetId)
    local item=imprintById[id]
    if not item then return 0 end
    local reserved=slot.imprints[item.role]==id or id==targetId
    return math.max(0,(slot.counts[id] or 0)-(reserved and 1 or 0))
end

function Store.RefineChance(slot,id)
    local rank=slot.ranks[id]
    local odds=Catalog.RefineChance[rank]
    return odds and (slot.counts[id] or 0)>0 and odds[slot.failures[id]+1] or nil
end

-- A quote describes the ore cost and resulting level even when stock is short.
function Store.ForgeQuote(progress,class,action,id,sourceId)
    local weapons=Catalog.Weapons[class]
    if not weapons then return nil,'武器类型不符' end
    local item,tier=Catalog.Find(weapons,id)
    if not item then return nil,'图纸无效' end
    local slot=progress.slots[class]
    local owned=slot.levels[id]
    if action=='craft' then
        if owned then return nil,'已拥有这件武器' end
        local _,equippedTier=Catalog.Find(weapons,slot.weapon)
        local previous=weapons[tier-1]
        if tier>equippedTier+1 and not (previous and slot.levels[previous.id]) then return nil,'请先打造同类上一阶武器' end
        return {cost=Catalog.CraftCost[tier],level=1}
    end
    if action~='smelt' then return nil,'未知锻造方式' end
    local source=weapons[tier-1]
    local level=source and slot.levels[source.id]
    if not level or (sourceId and sourceId~=source.id) then return nil,'只能熔入同类下一阶，需要拥有上一阶武器' end
    if owned and owned>=level then return nil,'目标武器等级已达继承等级' end
    return {source=source,level=level,cost=owned and 0 or Catalog.CraftCost[tier]}
end

-- Operate on a private draft. The panel can stage several edits and save once.
function Store.Edit(config,class,action,id,option,random)
    config=Store.Normalize(config)
    if not config or not Catalog.Weapons[class] then return nil,'装备配置无效' end
    local progress=config.progress
    local slot=progress.slots[class]
    local message
    if action=='select' then
        if not slot.levels[id] then return nil,'尚未打造' end
        slot.weapon=id
    elseif action=='imprint' then
        local item=Catalog.Find(Catalog.Imprints[class],id)
        if not item then return nil,'时印类型不符' end
        if slot.counts[id]==0 then return nil,'尚未获得这枚时印' end
        slot.imprints[item.role]=id
    elseif action=='craft' or action=='smelt' then
        local quote,reason=Store.ForgeQuote(progress,class,action,id,option)
        if not quote then return nil,reason end
        if progress.ore<quote.cost then return nil,'强化矿不足' end
        progress.ore=progress.ore-quote.cost
        slot.levels[id]=quote.level
        if quote.source then
            local source=quote.source.id
            slot.levels[source]=nil
            if slot.weapon==source then slot.weapon=id end
        end
    elseif action=='level' then
        id=id or slot.weapon
        local level=slot.levels[id]
        if not level then return nil,'尚未打造' end
        if level>=Catalog.LevelCap then return nil,'武器已满级' end
        if progress.ore<level then return nil,'强化矿不足' end
        progress.ore=progress.ore-level
        slot.levels[id]=level+1
    elseif action=='refine' then
        local chance=Store.RefineChance(slot,id)
        if not chance then return nil,'请选择可强化的时印' end
        if progress.sand<1 then return nil,'淬炼砂不足' end
        local material=progress.slots[imprintClass[option]]
        if not material or Store.FodderCount(material,option,id)<1 then return nil,'请选择一枚闲置时印' end
        progress.sand=progress.sand-1
        material.counts[option]=material.counts[option]-1
        if material.counts[option]==0 then material.ranks[option],material.failures[option]=1,0 end
        if chance==100 or (random or math.random)(100)<=chance then
            slot.ranks[id],slot.failures[id]=slot.ranks[id]+1,0
            message='强化成功'
        else
            slot.failures[id]=slot.failures[id]+1
            message=('强化未成，下次成功率 %d%%'):format(Store.RefineChance(slot,id))
        end
    else return nil,'未知锻造操作' end
    if config[class] then config[class].modelId=slot.weapon end
    return config,message or '已应用'
end

function Store.Commit(rig,draft)
    local config=Store.Normalize(draft)
    if not config or rig.disposed or config.active~=rig.config.active then return false,'装备配置无效' end
    if not Store.Save(config) then return false,'保存失败，材料已保留' end
    local previous=rig.config.progress.slots
    rig.config=config
    local current=config.progress.slots
    if rig.SyncEquipmentModels and (previous.sword.weapon~=current.sword.weapon or previous.bow.weapon~=current.bow.weapon) then
        local ok,err=pcall(rig.SyncEquipmentModels,rig)
        if not ok then print('WeaponStore: saved equipment model sync deferred: '..tostring(err)) end
    end
    return true
end

function Store.Forge(rig,class,action,id,option,random)
    local config,message=Store.Edit(rig.config,class,action,id,option,random)
    if not config then return false,message end
    local ok,reason=Store.Commit(rig,config)
    return ok,reason or message
end

function Store.RewardKill(rig)
    local config=Store.Normalize(rig.config)
    if not config then return false,'装备配置无效' end
    local progress=config.progress
    progress.ore=math.min(MAX_COUNT,progress.ore+REWARD_ORE)
    progress.sand=math.min(MAX_COUNT,progress.sand+REWARD_SAND)
    local drops={}
    for i=1,2 do
        local drop=dropOrder[progress.imprintDrops+1]
        progress.imprintDrops=(progress.imprintDrops+1)%#dropOrder
        local counts=progress.slots[drop.class].counts
        counts[drop.item.id]=math.min(MAX_COUNT,counts[drop.item.id]+1)
        drops[i]=drop.item.name
    end
    -- Enemy death cannot be retried. Keep earned loot in memory if the save fails.
    rig.config=config
    local saved=Store.Save(config)
    local message=('强化矿 +%d　淬炼砂 +%d　%s'):format(REWARD_ORE,REWARD_SAND,table.concat(drops,'、'))
    return saved,saved and message or (message..'（本次保存失败）')
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
