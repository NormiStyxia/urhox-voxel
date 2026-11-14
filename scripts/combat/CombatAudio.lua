-- Combat audio, §19.6. No engine work at require time.
-- New(scene) installs the default manager; use Audio.Play(...) OR manager:Play(...).
-- Update(realDt) once per frame (also during hit-stop); Dispose before scene teardown.
-- Call Preload once during scene idle time (W2: two seconds after scene startup).
-- It only schedules work. Update loads at most ONE resource per frame, sharing
-- that allowance with cold Play calls; each cold request is silent for this frame.
-- 2 ms is an admission budget: synchronous ResourceCache:GetResource cannot be
-- interrupted mid-decode. A single slow resource may overrun; no more work follows.
-- opts: pos (world Vector3), material, tier, enemy, volume [0,1], pitch multiplier;
-- hitId optionally groups layers across frames. Without hitId, impacts in one frame
-- share a conservative three-voice budget. Explicit sword tier 1/2/3 selects a swing;
-- unqualified multi-variant events randomize without immediate repetition.
-- SetListenerPosition(playerPos) supplies the 2D fallback. For native 3D, the scene
-- owner must install a SoundListener using audio:SetListener(listener).
local Audio = {}
local Manager = {}
Manager.__index = Manager
local defaultManager
local BUS_GAIN = 10 ^ (-6 / 20)
local FADE_SECONDS = 0.04
local BOW_LOOP_SECONDS = 0.65 -- skip generated MP3 encoder padding beyond 0.7 s
local LOAD_BUDGET_MS = 2
local NEAR, FAR = 2, 35
local LIMITS = { low = 8, mid = 12, high = 16 }
local EVENTS = {
    sword_whoosh = { files = { 'audio/sfx/cmb_sword_whoosh_1.mp3', 'audio/sfx/cmb_sword_whoosh_2.mp3', 'audio/sfx/cmb_sword_whoosh_3.mp3' }, db = -8, gains = {-8, -7, -5}, interval = 0.05 },
    hit_soft = { files = { 'audio/sfx/cmb_hit_soft_1.mp3', 'audio/sfx/cmb_hit_soft_2.mp3', 'audio/sfx/cmb_hit_soft_3.mp3' }, db = 0, impact = true },
    hit_armor = { files = { 'audio/sfx/cmb_hit_armor_1.mp3', 'audio/sfx/cmb_hit_armor_2.mp3', 'audio/sfx/cmb_hit_armor_3.mp3' }, db = 0, impact = true },
    hit_heavy = { files = { 'audio/sfx/cmb_hit_heavy_1.mp3', 'audio/sfx/cmb_hit_heavy_2.mp3' }, db = -3, impact = true },
    hit_core = { files = { 'audio/sfx/cmb_hit_core_1.mp3' }, db = 0, impact = true },
    armor_break = { files = { 'audio/sfx/cmb_armor_break_1.mp3', 'audio/sfx/cmb_armor_break_2.mp3' }, db = -4, impact = true, priority = 2 },
    deflect_stone = { files = { 'audio/sfx/cmb_deflect_stone_1.mp3', 'audio/sfx/cmb_deflect_stone_2.mp3' }, db = -1, impact = true },
    bow_draw = { files = { 'audio/sfx/cmb_bow_draw.mp3' }, db = -12, loop = true, interval = 0.10 },
    bow_full = { files = { 'audio/sfx/cmb_bow_full.mp3' }, db = -4, interval = 0.10 },
    bow_fire = { files = { 'audio/sfx/cmb_bow_fire_1.mp3', 'audio/sfx/cmb_bow_fire_2.mp3' }, db = -5 },
    arrow_hit = { files = { 'audio/sfx/cmb_arrow_hit_stone_1.mp3', 'audio/sfx/cmb_arrow_hit_body_1.mp3', 'audio/sfx/cmb_arrow_hit_armor_1.mp3' }, db = -2, impact = true },
    blade_draw = { files = { 'audio/sfx/cmb_blade_draw.mp3' }, db = -8, interval = 0.10 },
    blade_sheath = { files = { 'audio/sfx/cmb_blade_sheath.mp3' }, db = -8, interval = 0.10 },
    enemy_windup = { files = { 'audio/sfx/cmb_windup_beetle.mp3', 'audio/sfx/cmb_windup_sentry.mp3', 'audio/sfx/cmb_windup_beast.mp3' }, db = -5, priority = 4 },
    player_hurt = { files = { 'audio/sfx/cmb_player_hurt_1.mp3', 'audio/sfx/cmb_player_hurt_2.mp3' }, db = 0, priority = 3, interval = 0.06 },
    dodge = { files = { 'audio/sfx/cmb_dodge_slide_1.mp3', 'audio/sfx/cmb_dodge_slide_2.mp3' }, db = -10, interval = 0.06 },
    dodge_land = { files = { 'audio/sfx/cmb_dodge_land.mp3' }, db = -10, interval = 0.06 },
    stagger_land = { files = { 'audio/sfx/cmb_stagger_land.mp3' }, db = 0, interval = 0.10 },
    enemy_die = { files = { 'audio/sfx/cmb_enemy_die_1.mp3', 'audio/sfx/cmb_enemy_die_2.mp3' }, db = 0, gains = {0, -6} },
    boss_roar = { files = { 'audio/sfx/cmb_boss_roar.mp3' }, db = 2, priority = 4, interval = 0.20 },
    victory = { files = { 'audio/sfx/cmb_victory.mp3' }, db = -4, interval = 0.50 },
}

local ASSETS, ASSET_LOOPS = {}, {}
for _, definition in pairs(EVENTS) do
    for _, path in ipairs(definition.files) do
        if ASSET_LOOPS[path] == nil then ASSETS[#ASSETS + 1] = path end
        ASSET_LOOPS[path] = definition.loop == true
    end
end
table.sort(ASSETS)

local function milliseconds()
    -- Wall clock includes file I/O stalls; os.clock is the offline fallback only.
    if time then
        local ok, value = pcall(function() return time:GetSystemTime() end)
        if ok and type(value) == 'number' then return value end
    end
    return os.clock() * 1000
end

local function elapsed(start)
    return (milliseconds() - start) % 4294967296 -- engine uint32 millisecond wrap
end

local function beginLoadFrame(self)
    local frame = self.frame
    if time then
        local ok, value = pcall(function() return time:GetFrameNumber() end)
        if ok and type(value) == 'number' then frame = value end
    end
    if self.loadFrameKey ~= frame then
        self.loadFrameKey, self.loadsThisFrame, self.loadSpentMs = frame, 0, 0
    end
end

local function finite(value, fallback)
    if type(value) ~= 'number' or value ~= value or math.abs(value) == math.huge then return fallback end
    return value
end
local function clamp(value, lo, hi) return math.max(lo, math.min(hi, value)) end
local function warnOnce(self, key, message)
    if self.warned[key] then return end
    self.warned[key] = true
    print('[CombatAudio] ' .. message)
end

function Manager:Init(scene)
    self.scene = scene -- strong reference; caller owns the scene
    self.pool, self.sounds, self.lastVariant, self.lastPlay, self.warned = {}, {}, {}, {}, {}
    self.enabled, self.disposed, self.volume, self.limit = true, false, 1, LIMITS.mid
    self.time, self.frame, self.serial = 0, 0, 0
    self.preloadQueued, self.preloadCursor, self.loadedCount = false, 1, 0
    self.demandQueue, self.demandQueued, self.loadedFrame = {}, {}, {}
    self.loadsThisFrame, self.loadSpentMs = 0, 0
    self.loadFrameKey = nil
    self.listenerPosition = {x = 0, y = 0, z = 0}
end

local function loadSound(self, path, looped)
    local sound = self.sounds[path]
    if sound ~= nil then return sound or nil end
    if self.loadsThisFrame >= 1 or self.loadSpentMs >= LOAD_BUDGET_MS then return nil end
    self.loadsThisFrame = self.loadsThisFrame + 1
    local start = milliseconds()
    local ok, result = pcall(function()
        local resource = cache:GetResource('Sound', path)
        if resource then resource:SetLooped(looped == true) end
        return resource
    end)
    self.loadSpentMs = self.loadSpentMs + elapsed(start)
    if not ok or not result then
        self.sounds[path] = false -- do not retry missing resources every frame
        warnOnce(self, 'resource', '战斗音效加载失败，已静音降级：' .. path)
        return nil
    end
    self.sounds[path] = result
    self.loadedCount = self.loadedCount + 1
    self.loadedFrame[path] = self.loadFrameKey
    return result
end

function Manager:Preload()
    if not self.disposed then self.preloadQueued = true end
    return self:PreloadProgress()
end

-- loaded counts SUCCESSFUL resources, never failures. IsReady stays false if any
-- asset failed, but each failed path is terminal and never retried automatically.
function Manager:PreloadProgress()
    return self.loadedCount, #ASSETS
end

function Manager:IsReady()
    return not self.disposed and self.loadedCount == #ASSETS
end

local function preloadStep(self, updateStart)
    while self.loadsThisFrame < 1 and self.loadSpentMs < LOAD_BUDGET_MS and elapsed(updateStart) < LOAD_BUDGET_MS do
        local path
        if #self.demandQueue > 0 then
            path = table.remove(self.demandQueue, 1)
            self.demandQueued[path] = nil
        elseif self.preloadQueued then
            path = ASSETS[self.preloadCursor]
            if not path then return end
            self.preloadCursor = self.preloadCursor + 1
        else return end
        -- On-demand loads may already have fulfilled items in the background list.
        if self.sounds[path] == nil then loadSound(self, path, ASSET_LOOPS[path]) end
    end
end

local function stopVoice(self, slot)
    if slot.source then
        local ok = pcall(function()
            slot.source:SetGain(0) -- even an unavailable stop API must not leave audible loops
            slot.source:StopImmediate()
        end)
        if not ok then
            pcall(function() slot.source:Stop() end)
            warnOnce(self, 'stop', '声源停止接口不可用，已尝试静音。')
        end
    end
    slot.active, slot.handle, slot.fade = false, nil, nil
    slot.hitId, slot.pos = nil, nil
end

local function getListener(self)
    local ok, listener = pcall(function() return audio:GetListener() end)
    if ok and listener then
        local posOk, pos = pcall(function() return listener.node.worldPosition end)
        if posOk and pos then return listener, pos end
    end
    return nil, self.listenerPosition
end

local function distanceGain(pos, listenerPos)
    if not pos then return 1 end
    local dx, dy, dz = pos.x - listenerPos.x, pos.y - listenerPos.y, pos.z - listenerPos.z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    return clamp(1 - (distance - NEAR) / (FAR - NEAR), 0, 1)
end

local function setGain(self, slot, listenerPos)
    local attenuation = slot.spatial and 1 or distanceGain(slot.pos, listenerPos)
    local fade = slot.fade and clamp(1 - (self.time - slot.fade) / FADE_SECONDS, 0, 1) or 1
    local ok = pcall(function() slot.source:SetGain(slot.baseGain * self.volume * attenuation * fade) end)
    if not ok then
        warnOnce(self, 'playback', '战斗音效播放接口失败，已静音降级。')
        stopVoice(self, slot)
    end
end

-- Oldest among the lowest priority voices. A new lower-priority voice cannot
-- steal a warning. Slot serial (not time) breaks ties for events in one frame.
local function weakest(self, hitId)
    local victim, count
    count = 0
    for _, slot in ipairs(self.pool) do
        if slot.active and (hitId == nil or slot.hitId == hitId) then
            count = count + 1
            if not victim or slot.priority < victim.priority or
                (slot.priority == victim.priority and slot.serial < victim.serial) then victim = slot end
        end
    end
    return victim, count
end

local function acquire(self, priority, hitId)
    if hitId ~= nil then
        local victim, count = weakest(self, hitId)
        if count >= 3 then
            if victim.priority > priority then return nil end
            stopVoice(self, victim)
        end
    end
    local victim, count = weakest(self)
    if count >= self.limit then
        if victim.priority > priority then return nil end
        stopVoice(self, victim)
    end
    for _, slot in ipairs(self.pool) do if not slot.active then return slot end end
    if #self.pool >= self.limit then return nil end
    local ok, node = pcall(function() return self.scene:CreateChild('CombatAudioVoice') end)
    if not ok or not node then
        warnOnce(self, 'source', '无法创建战斗声源，已静音降级。')
        return nil
    end
    local slot = { node = node, active = false }
    self.pool[#self.pool + 1] = slot
    return slot
end

local function configureSource(self, slot, pos, listener)
    slot.spatial = false
    if pos and listener and not self.no3D then
        local ok, source = pcall(function()
            local s = slot.source3D or slot.node:CreateComponent('SoundSource3D')
            slot.source3D = s
            s:SetDistanceAttenuation(NEAR, FAR, 1)
            slot.node.worldPosition = pos
            return s
        end)
        if ok and source then slot.source, slot.spatial = source, true; return true end
        self.no3D = true
        warnOnce(self, 'spatial', '空间音源不可用，改为平面播放并按距离衰减。')
    end
    local ok, source = pcall(function()
        local s = slot.source2D or slot.node:CreateComponent('SoundSource')
        slot.source2D = s
        return s
    end)
    if not ok or not source then
        warnOnce(self, 'source', '无法创建战斗声源，已静音降级。')
        return false
    end
    slot.source = source
    return true
end

local function resolve(event, opts)
    if event == 'hit_soft' or event == 'hit_armor' or event == 'hit_core' then
        local materials = {soft = 'hit_soft', body = 'hit_soft', armor = 'hit_armor', stone = 'hit_armor', core = 'hit_core', weakpoint = 'hit_core'}
        event = materials[opts.material] or event
    end
    return event
end

local function chooseVariant(self, event, definition, opts)
    local index
    if event == 'arrow_hit' then
        index = ({stone = 1, body = 2, soft = 2, core = 2, armor = 3})[opts.material] or 1
    elseif event == 'enemy_windup' then
        index = ({beetle = 1, sentry = 2, beast = 3, boss = 3})[opts.enemy] or 1
    elseif event == 'enemy_die' and (opts.enemy or opts.material) then
        index = (opts.enemy == 'beetle' or opts.enemy == 'insect' or opts.material == 'soft' or opts.material == 'body') and 2 or 1
    elseif event == 'sword_whoosh' and type(opts.tier) == 'number' then
        index = math.floor(clamp(finite(opts.tier, 1), 1, 3))
    end
    if not index then
        local count, last = #definition.files, self.lastVariant[event]
        if count > 1 and last then
            index = math.random(1, count - 1)
            if index >= last then index = index + 1 end
        else index = math.random(1, count) end
    end
    return index
end

function Manager:Play(eventName, opts)
    if self.disposed or not self.enabled then return nil end
    beginLoadFrame(self)
    opts = opts or {}
    local event = resolve(eventName, opts)
    local definition = EVENTS[event]
    if not definition then warnOnce(self, 'event', '忽略未知战斗音效事件。'); return nil end
    local last = self.lastPlay[event]
    if last and self.time - last < (definition.interval or 0.035) then return nil end
    if definition.loop then
        for _, slot in ipairs(self.pool) do
            if slot.active and slot.event == event and not slot.fade then return slot.handle end
        end
    end
    local index = chooseVariant(self, event, definition, opts)
    local path = definition.files[index]
    local sound = self.sounds[path]
    if sound == nil then
        loadSound(self, path, definition.loop)
        if self.sounds[path] == nil and not self.demandQueued[path] then
            self.demandQueued[path] = true
            self.demandQueue[#self.demandQueue + 1] = path
        end
        return nil -- no late replay: gameplay timing takes precedence over audio
    end
    if self.loadedFrame[path] == self.loadFrameKey then return nil end
    if not sound then return nil end
    local priority = definition.priority or 1
    local hitId = opts.hitId
    if hitId == nil and definition.impact then hitId = 'frame:' .. self.frame end
    local slot = acquire(self, priority, hitId)
    if not slot then return nil end
    local listener, listenerPos = getListener(self)
    if not configureSource(self, slot, opts.pos, listener) then return nil end
    local db = definition.gains and definition.gains[index] or definition.db
    if event == 'hit_core' and (opts.tier == 'critical' or opts.tier == 'core' or opts.tier == 2) then db = db + 2 end
    if event == 'enemy_windup' and (opts.tier == 'danger' or opts.tier == 2) then db = -2 end
    local pitch = clamp(finite(opts.pitch, 1), 0.25, 4) * (0.97 + math.random() * 0.06)
    slot.baseGain = BUS_GAIN * 10 ^ (db / 20) * clamp(finite(opts.volume, 1), 0, 1)
    slot.pos, slot.fade = opts.pos, nil
    local attenuation = slot.spatial and 1 or distanceGain(slot.pos, listenerPos)
    local ok = pcall(function()
        slot.source:SetAutoRemoveMode(REMOVE_DISABLED or 0)
        slot.source:SetDeclickEnabled(true)
        slot.source:SetSoundType(SOUND_EFFECT or 'Effect')
        slot.source:Play(sound, sound:GetFrequency() * pitch, slot.baseGain * self.volume * attenuation)
    end)
    if not ok then
        stopVoice(self, slot)
        warnOnce(self, 'playback', '战斗音效播放接口失败，已静音降级。')
        return nil
    end
    self.serial = self.serial + 1
    slot.active, slot.serial, slot.handle = true, self.serial, { id = self.serial }
    slot.priority, slot.event, slot.hitId, slot.loop = priority, event, hitId, definition.loop
    slot.loopTime, slot.pitch = 0, pitch
    self.lastPlay[event], self.lastVariant[event] = self.time, index
    return slot.handle
end

function Manager:Stop(handle)
    if not handle then return false end
    for _, slot in ipairs(self.pool) do
        if slot.active and slot.handle == handle then
            if slot.loop then
                -- Native Stop performs the engine's short declick fade immediately,
                -- even while game Update is paused. Update enforces a 40 ms hard cap.
                if not slot.fade then
                    slot.fade = self.time
                    local ok = pcall(function() slot.source:Stop() end)
                    if not ok then stopVoice(self, slot) end
                end
            else stopVoice(self, slot) end
            return true
        end
    end
    return false
end

function Manager:Update(dt)
    if self.disposed then return end
    local updateStart = milliseconds()
    self.time, self.frame = self.time + math.max(0, finite(dt, 0)), self.frame + 1
    beginLoadFrame(self)
    local _, listenerPos = getListener(self)
    for _, slot in ipairs(self.pool) do
        if slot.active then
            local ok, playing = pcall(function() return slot.source:IsPlaying() end)
            if (slot.fade and self.time - slot.fade >= FADE_SECONDS) or not ok or (not slot.fade and not playing) then
                stopVoice(self, slot)
            else
                if slot.loop and not slot.fade then
                    slot.loopTime = slot.loopTime + math.max(0, finite(dt, 0)) * slot.pitch
                    if slot.loopTime >= BOW_LOOP_SECONDS then
                        slot.loopTime = slot.loopTime % BOW_LOOP_SECONDS
                        local seekOk = pcall(function() slot.source:Seek(slot.loopTime) end)
                        if not seekOk then
                            stopVoice(self, slot)
                            warnOnce(self, 'loop', '拉弓循环接口不可用，已静音降级。')
                        end
                    end
                end
                if slot.active then setGain(self, slot, listenerPos) end
            end
        end
    end
    -- Preserve exhausted Update budget for Play calls later in this same frame.
    self.loadSpentMs = math.max(self.loadSpentMs, elapsed(updateStart))
    preloadStep(self, updateStart)
end

function Manager:SetEnabled(enabled)
    self.enabled = enabled == true
    if not self.enabled then for _, slot in ipairs(self.pool) do if slot.active then stopVoice(self, slot) end end end
end

function Manager:SetVolume(value)
    self.volume = clamp(finite(value, 1), 0, 1)
    local _, listenerPos = getListener(self)
    for _, slot in ipairs(self.pool) do if slot.active then setGain(self, slot, listenerPos) end end
end

function Manager:SetQuality(quality)
    if not LIMITS[quality] then return false end
    self.limit = LIMITS[quality]
    while true do
        local victim, count = weakest(self)
        if count <= self.limit then break end
        stopVoice(self, victim)
    end
    return true
end

function Manager:SetListenerPosition(pos) self.listenerPosition = pos end

function Manager:Dispose()
    if self.disposed then return end
    for _, slot in ipairs(self.pool) do
        stopVoice(self, slot)
        pcall(function() slot.node:Remove() end)
        pcall(function() slot.node:Dispose() end)
    end
    self.pool, self.sounds, self.scene, self.disposed = {}, {}, nil, true
    self.demandQueue, self.demandQueued, self.loadedFrame, self.loadedCount = {}, {}, {}, 0
    self.preloadQueued = false
end

function Audio.Events()
    local events = {}
    for name, definition in pairs(EVENTS) do
        events[name] = { files = {table.unpack(definition.files)}, variants = #definition.files,
            db = definition.db, interval = definition.interval or 0.035, priority = definition.priority or 1 }
    end
    return events
end
Manager.Events = Audio.Events

function Audio.New(scene)
    if defaultManager then defaultManager:Dispose() end
    local manager = setmetatable({}, Manager)
    manager:Init(scene)
    defaultManager = manager
    return manager
end

-- Module facade allows W2/W3 to share the scene-owned manager without globals.
for _, name in ipairs({'Play', 'Stop', 'SetEnabled', 'SetVolume', 'SetQuality', 'Preload', 'PreloadProgress', 'IsReady', 'Update', 'Dispose', 'SetListenerPosition'}) do
    Audio[name] = function(...)
        if defaultManager then return Manager[name](defaultManager, ...) end
        if name == 'IsReady' then return false end
        if name == 'PreloadProgress' then return 0, #ASSETS end
        return nil
    end
end
return Audio
