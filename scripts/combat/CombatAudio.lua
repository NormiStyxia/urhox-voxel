-- Combat audio, §19.6. No engine work at require time.
-- New(scene) installs the default manager; use Audio.Play(...) OR manager:Play(...).
-- Update(realDt) once per frame (also during hit-stop); Dispose before scene teardown.
-- New schedules idle prewarming immediately; Update uses the already-loaded
-- CombatState (or an explicit allowWarmup override in isolated tests).
-- Playback NEVER loads resources or creates engine objects.
-- Missing cues are dropped, never queued for late replay. Browser gesture unlock
-- remains the engine/host's responsibility; warmup does not play silent sounds.
-- The 2ms admission budget cannot preempt one native operation or engine-side
-- async finalization. Unsupported async loading falls back ONLY while exploring.
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
local FADE_SECONDS = 0.02 -- bow draw loop release/cancel; no queued fire sound
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
    sword_full = { files = { 'audio/sfx/cmb_bow_full.mp3' }, db = -6, pitch = .8, interval = 0.10 },
    bow_fire = { files = { 'audio/sfx/cmb_bow_fire_1.mp3', 'audio/sfx/cmb_bow_fire_2.mp3' }, db = -5 },
    arrow_hit = { files = { 'audio/sfx/cmb_arrow_hit_stone_1.mp3', 'audio/sfx/cmb_arrow_hit_body_1.mp3', 'audio/sfx/cmb_arrow_hit_armor_1.mp3' }, db = -2, impact = true },
    blade_draw = { files = { 'audio/sfx/cmb_blade_draw.mp3' }, db = -8, interval = 0.10 },
    blade_sheath = { files = { 'audio/sfx/cmb_blade_sheath.mp3' }, db = -8, interval = 0.10 },
    enemy_windup = { files = { 'audio/sfx/cmb_windup_beetle.mp3', 'audio/sfx/cmb_windup_sentry.mp3', 'audio/sfx/cmb_windup_beast.mp3' }, db = -5, priority = 4 },
    player_hurt = { files = { 'audio/sfx/cmb_player_hurt_1.mp3', 'audio/sfx/cmb_player_hurt_2.mp3' }, db = 0, priority = 3, interval = 0.06 },
    dodge = { files = { 'audio/sfx/cmb_dodge_slide_1.mp3', 'audio/sfx/cmb_dodge_slide_2.mp3' }, db = -10, interval = 0.06 },
    dodge_land = { files = { 'audio/sfx/cmb_dodge_land.mp3' }, db = -10, interval = 0.06 },
    run_step = { files = { 'audio/sfx/cmb_dodge_land.mp3' }, db = -14, interval = 0.12 },
    stagger_land = { files = { 'audio/sfx/cmb_stagger_land.mp3' }, db = 0, interval = 0.10 },
    enemy_die = { files = { 'audio/sfx/cmb_enemy_die_1.mp3', 'audio/sfx/cmb_enemy_die_2.mp3' }, db = 0, gains = {0, -6} },
    boss_roar = { files = { 'audio/sfx/cmb_boss_roar.mp3' }, db = 2, priority = 4, interval = 0.20 },
    victory = { files = { 'audio/sfx/cmb_victory.mp3' }, db = -4, interval = 0.50 },
}

local ASSETS, ASSET_LOOPS, ASSET_CUES = {}, {}, {}
local WARM_ORDER = {'sword_whoosh','hit_heavy','hit_soft','hit_armor','hit_core',
    'armor_break','deflect_stone','bow_draw','bow_fire','arrow_hit','bow_full',
    'blade_draw','blade_sheath','enemy_windup','player_hurt','dodge','dodge_land',
    'stagger_land','enemy_die','boss_roar','victory'}
for _, cue in ipairs(WARM_ORDER) do
    local definition = EVENTS[cue]
    for _, path in ipairs(definition.files) do
        ASSETS[#ASSETS + 1] = path
        ASSET_LOOPS[path], ASSET_CUES[path] = definition.loop == true, cue
    end
end

-- Static pcall targets: no new closures in Play/Update or instrumentation.
local function method(object, name, ...) return object[name](object, ...) end
local function engineClock() return Time:GetSystemTime() end
local function engineFrame() return time:GetFrameNumber() end
local function listenerPosition(listener) return listener.node.worldPosition end
local function positionNode(node, pos) node.worldPosition = pos end
local function playSource(source, sound, pitch, gain)
    source:Play(sound, sound:GetFrequency() * pitch, gain)
end
local function configurePooledSource(source, spatial)
    source:SetAutoRemoveMode(REMOVE_DISABLED or 0)
    source:SetDeclickEnabled(true)
    source:SetSoundType(SOUND_EFFECT or 'Effect')
    source:SetGain(0)
    if spatial then source:SetDistanceAttenuation(NEAR, FAR, 1) end
end

local function milliseconds()
    -- 静态绑定必须用 Time 类表；墙钟包含 I/O 停顿，离线测试才退回 CPU 计时。
    if Time then
        local ok, value = pcall(engineClock)
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
        local ok, value = pcall(engineFrame)
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

local function slowLog(self, cue, duration, cold, created)
    if duration < 4 or self.time - self.lastSlowLog < 5 then return end
    local ruins = rawget(_G, 'RUINS')
    local state = ruins and ruins.combat and ruins.combat.state
    if state and state.audioPerf == false then return end
    self.lastSlowLog = self.time
    print(string.format('Perf: combatAudio cue=%s ms=%.3f cold=%s newSource=%s',
        cue, duration, tostring(cold), tostring(created)))
end

function Manager:Init(scene)
    self.scene = scene -- strong reference; caller owns the scene
    self.pool, self.sounds, self.lastVariant, self.lastPlay, self.warned = {}, {}, {}, {}, {}
    self.enabled, self.disposed, self.volume, self.limit = true, false, 1, LIMITS.mid
    self.time, self.frame, self.serial = 0, 0, 0
    self.preloadQueued, self.preloadCursor, self.loadedCount = true, 1, 0
    self.poolCursor, self.poolPhase, self.readySources = 1, 1, 0
    self.pendingPath, self.pendingAt, self.noAsync = nil, 0, false
    self.lastSlowLog = -math.huge
    self.loadedFrame = {}
    self.loadsThisFrame, self.loadSpentMs = 0, 0
    self.loadFrameKey = nil
    self.listenerPosition = {x = 0, y = 0, z = 0}
end

local function finishSound(self, path, resource)
    if resource then
        local ok = pcall(method, resource, 'SetLooped', ASSET_LOOPS[path])
        if not ok then resource = nil end
    end
    if not resource then
        self.sounds[path] = false
        warnOnce(self, 'resource', '战斗音效加载失败，已静音降级：' .. path)
        return
    end
    self.sounds[path] = resource
    self.loadedCount = self.loadedCount + 1
    self.loadedFrame[path] = self.loadFrameKey
end

local function loadSound(self, path)
    local start = milliseconds()
    self.loadsThisFrame = self.loadsThisFrame + 1
    if not self.noAsync and self.syncPath ~= path then
        local ok, accepted = pcall(method, cache, 'BackgroundLoadResource', 'Sound', path, false)
        if ok and accepted then
            self.pendingPath, self.pendingAt = path, self.time
        elseif ok then
            local existsOK, resource = pcall(method, cache, 'GetExistingResource', 'Sound', path)
            if existsOK and resource then finishSound(self, path, resource)
            else
                -- Some hosts expose the API but reject background requests.
                -- Try this file once on a later idle frame, never in Play.
                self.syncPath = path
                self.preloadCursor = self.preloadCursor - 1
            end
        else
            -- No speculative synchronous retry in this frame. Retry the same
            -- asset on a later EXPLORE frame, using the compatibility loader.
            self.noAsync = true
            self.preloadCursor = self.preloadCursor - 1
        end
    else
        self.syncPath = nil
        local ok, resource = pcall(method, cache, 'GetResource', 'Sound', path, false)
        finishSound(self, path, ok and resource or nil)
    end
    local duration = elapsed(start)
    self.loadSpentMs = self.loadSpentMs + duration
    slowLog(self, ASSET_CUES[path], duration, true, false)
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
    if self.loadsThisFrame >= 1 or self.loadSpentMs >= LOAD_BUDGET_MS or elapsed(updateStart) >= LOAD_BUDGET_MS then return end
    if self.pendingPath then
        local path, start = self.pendingPath, milliseconds()
        self.loadsThisFrame = self.loadsThisFrame + 1
        -- GetExistingResource never invokes a synchronous resource load.
        local ok, resource = pcall(method, cache, 'GetExistingResource', 'Sound', path)
        if ok and resource then
            finishSound(self, path, resource)
            self.pendingPath = nil
        else
            local countOK, count = pcall(method, cache, 'GetNumBackgroundLoadResources')
            if not ok or (countOK and count == 0) or self.time - self.pendingAt >= 30 then
                finishSound(self, path, nil)
                self.pendingPath = nil
            end
        end
        local duration = elapsed(start)
        self.loadSpentMs = self.loadSpentMs + duration
        slowLog(self, ASSET_CUES[path], duration, true, false)
        return
    end
    if not self.preloadQueued then return end
    local path = ASSETS[self.preloadCursor]
    if path then
        self.preloadCursor = self.preloadCursor + 1
        loadSound(self, path)
    end
end

-- At most one Node/Component construction operation per engine frame; each slot
-- holds both 2D and 3D paths so the first spatial cue cannot expand the pool.
local function warmPool(self, updateStart)
    if self.poolWorkFrame == self.loadFrameKey or self.poolCursor > self.limit or self.poolFailed or self.loadSpentMs >= LOAD_BUDGET_MS or elapsed(updateStart) >= LOAD_BUDGET_MS then return end
    self.poolWorkFrame = self.loadFrameKey
    local start, created = milliseconds(), false
    local slot = self.pool[self.poolCursor]
    if self.poolPhase == 1 then
        local ok, node = pcall(method, self.scene, 'CreateChild', 'CombatAudioVoice')
        if not ok or not node then
            self.poolFailed = true
            warnOnce(self, 'source', '无法预建战斗声源，已静音降级。')
            return
        end
        slot = {node = node, active = false, ready = false}
        self.pool[self.poolCursor] = slot
        self.poolPhase, created = 2, true
    else
        local spatial = self.poolPhase == 3
        local ok, source
        if not spatial or not self.no3D then
            ok, source = pcall(method, slot.node, 'CreateComponent', spatial and 'SoundSource3D' or 'SoundSource')
            created = source ~= nil
            if ok and source then ok = pcall(configurePooledSource, source, spatial) end
        end
        if spatial then
            if ok and source then slot.source3D = source
            else
                if source then pcall(method, source, 'Remove') end
                if not self.no3D then warnOnce(self, 'spatial', '空间音源不可用，改为平面播放并按距离衰减。') end
                self.no3D = true
            end
            slot.ready = true
            self.readySources = self.readySources + 1
            self.poolCursor, self.poolPhase = self.poolCursor + 1, 1
        elseif ok and source then
            slot.source2D, self.poolPhase = source, 3
        else
            self.poolFailed = true
            warnOnce(self, 'source', '无法预建战斗声源，已静音降级。')
        end
    end
    slowLog(self, 'pool', elapsed(start), false, created)
end

function Manager:IsFirstStrikeReady()
    if self.readySources == 0 then return false end
    for _, path in ipairs(EVENTS.sword_whoosh.files) do if not self.sounds[path] then return false end end
    return true
end

local function stopVoice(self, slot)
    if slot.source then
        pcall(method, slot.source, 'SetGain', 0)
        local ok = pcall(method, slot.source, 'StopImmediate')
        if not ok then
            pcall(method, slot.source, 'Stop')
            warnOnce(self, 'stop', '声源停止接口不可用，已尝试静音。')
        end
    end
    slot.active, slot.handle, slot.fade = false, nil, nil
    slot.hitId, slot.pos = nil, nil
end

local function getListener(self)
    local ok, listener = pcall(method, audio, 'GetListener')
    if ok and listener then
        local posOk, pos = pcall(listenerPosition, listener)
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
    local ok = pcall(method, slot.source, 'SetGain', slot.baseGain * self.volume * attenuation * fade)
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
    if count >= math.min(self.limit, self.readySources) then
        if not victim then return nil end
        if victim.priority > priority then return nil end
        stopVoice(self, victim)
    end
    for _, slot in ipairs(self.pool) do if slot.ready and not slot.active then return slot end end
    return nil -- combat never expands the pool
end

local function configureSource(self, slot, pos, listener)
    slot.spatial = pos ~= nil and listener ~= nil and slot.source3D ~= nil
    if slot.spatial then
        local ok = pcall(positionNode, slot.node, pos)
        if not ok then slot.spatial = false end
    end
    slot.source = slot.spatial and slot.source3D or slot.source2D
    return slot.source ~= nil
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
    if sound == nil then return nil end -- drop cold cue; only idle Update does I/O
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
    local pitch = clamp(finite(opts.pitch, definition.pitch or 1), 0.25, 4) * (0.97 + math.random() * 0.06)
    slot.baseGain = BUS_GAIN * 10 ^ (db / 20) * clamp(finite(opts.volume, 1), 0, 1)
    slot.pos, slot.fade = opts.pos, nil
    local attenuation = slot.spatial and 1 or distanceGain(slot.pos, listenerPos)
    local ok = pcall(playSource, slot.source, sound, pitch, slot.baseGain * self.volume * attenuation)
    if not ok then
        stopVoice(self, slot)
        warnOnce(self, 'playback', '战斗音效播放接口失败，已静音降级。')
        return nil
    end
    self.serial = self.serial + 1
    slot.active, slot.serial, slot.handle = true, self.serial, { id = self.serial }
    slot.priority, slot.event, slot.hitId, slot.loop = priority, event, hitId, definition.loop
    slot.loopTime, slot.pitch = 0, pitch
    slot.bowFullEnd = event == 'bow_full' and self.time + .12 or nil
    self.lastPlay[event], self.lastVariant[event] = self.time, index
    return slot.handle
end

function Manager:Stop(handle)
    if not handle then return false end
    for _, slot in ipairs(self.pool) do
        if slot.active and slot.handle == handle then
            if slot.loop then
                -- Native Stop performs the engine's short declick fade immediately,
                -- even while game Update is paused. Update enforces a 20 ms hard cap.
                if not slot.fade then
                    slot.fade = self.time
                    local ok = pcall(method, slot.source, 'Stop')
                    if not ok then stopVoice(self, slot) end
                end
            else stopVoice(self, slot) end
            return true
        end
    end
    return false
end

function Manager:Update(dt, allowWarmup)
    if self.disposed then return end
    if allowWarmup == nil then
        local state = package.loaded['combat.CombatState']
        allowWarmup = not state or state.Get() == state.EXPLORE
    end
    local updateStart = milliseconds()
    self.time, self.frame = self.time + math.max(0, finite(dt, 0)), self.frame + 1
    beginLoadFrame(self)
    local _, listenerPos = getListener(self)
    for _, slot in ipairs(self.pool) do
        if slot.active then
            local ok, playing = pcall(method, slot.source, 'IsPlaying')
            if (slot.bowFullEnd and self.time >= slot.bowFullEnd) or (slot.fade and self.time - slot.fade >= FADE_SECONDS) or not ok or (not slot.fade and not playing) then
                stopVoice(self, slot)
            else
                if slot.loop and not slot.fade then
                    slot.loopTime = slot.loopTime + math.max(0, finite(dt, 0)) * slot.pitch
                    if slot.loopTime >= BOW_LOOP_SECONDS then
                        slot.loopTime = slot.loopTime % BOW_LOOP_SECONDS
                        local seekOk = pcall(method, slot.source, 'Seek', slot.loopTime)
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
    if allowWarmup ~= false then
        preloadStep(self, updateStart)
        warmPool(self, updateStart)
    end
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
        pcall(method, slot.node, 'Remove')
        pcall(method, slot.node, 'Dispose')
    end
    self.pool, self.sounds, self.scene, self.disposed = {}, {}, nil, true
    self.loadedFrame, self.loadedCount, self.readySources = {}, 0, 0
    self.pendingPath = nil
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
for _, name in ipairs({'Play', 'Stop', 'SetEnabled', 'SetVolume', 'SetQuality', 'Preload', 'PreloadProgress', 'IsReady', 'IsFirstStrikeReady', 'Update', 'Dispose', 'SetListenerPosition'}) do
    Audio[name] = function(...)
        if defaultManager then return Manager[name](defaultManager, ...) end
        if name == 'IsReady' or name == 'IsFirstStrikeReady' then return false end
        if name == 'PreloadProgress' then return 0, #ASSETS end
        return nil
    end
end
return Audio
