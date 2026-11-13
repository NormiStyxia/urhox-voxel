-- File/cjson sandbox persistence. Web refresh clears the engine's in-memory save.
local Parts = require("combat.WeaponParts")
local Store = {}
local SAVE_PATH = "weapons-v1.json"
local MAX_SAVE_BYTES = 16384

---@return table
function Store.Default()
    return {version=1, sword=Parts.DefaultWeapon("sword"), bow=Parts.DefaultWeapon("bow"), active="sword"}
end

--- Presets are catalogue data; save the chosen parts using the existing v1 schema.
---@param weapon string
---@param id string
---@return table?
function Store.Preset(weapon,id) return Parts.Preset(weapon,id) end

-- Copy only the versioned schema; never retain arbitrary JSON fields/references.
---@param config table
---@return table?
local function Normalize(config)
    if type(config)~="table" or config.version~=1 or (config.active~="sword" and config.active~="bow") then return nil end
    local result = Store.Default()
    result.active = config.active
    for _, weapon in ipairs({"sword","bow"}) do
        local entry = config[weapon]
        if not Parts.ValidateWeapon(weapon,entry) then return nil end
        for _, slot in ipairs(Parts.Slots[weapon]) do result[weapon].parts[slot] = entry.parts[slot] end
        for _, channel in ipairs(Parts.Channels) do result[weapon].colors[channel] = entry.colors[channel] end
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
        return Normalize(cjson.decode(raw))
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
        local normalized = Normalize(config)
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
