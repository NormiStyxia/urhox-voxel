-- File/cjson sandbox persistence. Web refresh clears the engine's in-memory save.
local Catalog = require("combat.WeaponCatalog")
local Store = {}
local SAVE_PATH = "weapons-v1.json"
local MAX_SAVE_BYTES = 16384

---@return table
function Store.Default()
    return {version=2, sword=Catalog.DefaultWeapon("sword"), bow=Catalog.DefaultWeapon("bow"), active="sword"}
end

-- Keep the filename so existing users migrate in place. Never retain removed parts.
function Store.Normalize(config,allowLegacy)
    if type(config)~="table" or (config.active~="sword" and config.active~="bow") then return nil end
    if config.version~=2 and not (allowLegacy and config.version==1) then return nil end
    local result=Store.Default()
    result.active=config.active
    for _,weapon in ipairs({'sword','bow'}) do
        local entry=config[weapon]
        if type(entry)~='table' then return nil end
        if config.version==1 then
            entry={appearance=Catalog.Definitions[weapon].appearance,colors=entry.colors}
        end
        result[weapon]=Catalog.CopyAppearance(weapon,entry)
        if not result[weapon] then return nil end
    end
    return result
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
        if fileSystem and not fileSystem:FileExists(SAVE_PATH) then return nil end
        file = File(SAVE_PATH, FILE_READ)
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
        file = File(SAVE_PATH, FILE_WRITE)
        if not file or not file:IsOpen() then return false end
        return file:WriteString(raw)
    end)
    Close(file)
    return ok and result==true
end
return Store
