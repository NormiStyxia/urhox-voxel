-- Run from project root: lua5.4 tests/combat/audio_spec.lua
-- Also compatible with Python lupa.lua54.LuaRuntime, without any game Runtime.
package.path = 'scripts/?.lua;tests/?.lua;' .. package.path
local Audio = require('combat.CombatAudio')
local Mock = require('combat.audio_mock')
local checks = 0
local function check(value, label) checks = checks + 1; assert(value, label) end
local function close(a, b) return math.abs(a - b) < 0.00001 end
local function fresh(config, cold)
    Audio.Dispose()
    local mock = Mock.New(config)
    local manager = Audio.New(mock.scene)
    if not cold then
        manager:Preload()
        for _ = 1, 39 do manager:Update(1/60) end
    end
    return manager, mock
end
local function sourceFor(manager, handle)
    for _, slot in ipairs(manager.pool) do if slot.handle == handle then return slot.source end end
end
local function isActive(manager, handle) return sourceFor(manager, handle) ~= nil end
math.randomseed(731)

local expected = {sword_whoosh=3, hit_soft=3, hit_armor=3, hit_heavy=2, hit_core=1,
    armor_break=2, deflect_stone=2, bow_draw=1, bow_full=1, bow_fire=2, arrow_hit=3,
    blade_draw=1, blade_sheath=1, enemy_windup=3, player_hurt=2, dodge=2, dodge_land=1,
    stagger_land=1, enemy_die=2, boss_roar=1, victory=1}
local manifest, total, names = Audio.Events(), 0, 0
for name, row in pairs(manifest) do
    names = names + 1
    check(row.variants == expected[name], 'variant count ' .. name)
    check(row.interval > 0, 'retrigger limit ' .. name)
    for _, path in ipairs(row.files) do
        local file = io.open('assets/' .. path, 'rb')
        check(file ~= nil, 'asset exists ' .. path)
        if file then check(file:seek('end') > 0, 'asset not empty'); file:close() end
        local meta = io.open('assets/' .. path .. '.meta', 'rb')
        check(meta ~= nil, 'official metadata exists ' .. path)
        if meta then meta:close() end
        total = total + 1
    end
end
check(total == 38 and names == 21, '38 assets / 21 events')
manifest.hit_soft.files[1] = 'corrupted'
check(Audio.Events().hit_soft.files[1] ~= 'corrupted', 'manifest isolated')

check(not Audio.IsReady(), 'no manager is not ready')
local initialLoaded, initialTotal = Audio.PreloadProgress()
check(initialLoaded == 0 and initialTotal == 38, 'no manager progress')
local manager, mock = fresh(nil, true)
local loaded, assetTotal = Audio.Preload()
check(loaded == 0 and assetTotal == 38 and mock.readCount == 0, 'Preload only queues, no synchronous I/O')
check(not Audio.IsReady(), 'queued but not ready')
for frame = 1, 38 do
    Audio.Preload(); Audio.Update(1/60)
    loaded, assetTotal = Audio.PreloadProgress()
    check(loaded == frame and assetTotal == 38, 'monotonic frame progress')
    check(mock.readCount == frame, 'at most one resource each frame')
    check(Audio.IsReady() == (frame == 38), 'ready only after all resources loaded')
end
Audio.Preload()
Audio.Update(1/60)
check(mock.readCount == 38, 'completed Preload is idempotent')
for _, count in pairs(mock.reads) do check(count == 1, 'cache preloaded once') end
check(mock.sounds['audio/sfx/cmb_bow_draw.mp3'].looped, 'bow looping resource')
for name, variants in pairs(expected) do
    local previous
    for _ = 1, 15 do
        manager:Update(0.6)
        local handle = Audio.Play(name)
        check(handle ~= nil, 'event plays ' .. name)
        local source = sourceFor(manager, handle)
        local pitch = source.frequency / source.sound.frequency
        check(pitch >= 0.97 and pitch <= 1.03, 'pitch within 3 percent')
        if variants > 1 and name ~= 'arrow_hit' and name ~= 'enemy_windup' then
            check(source.sound.path ~= previous, 'no repeat ' .. name)
        end
        previous = source.sound.path
        Audio.Stop(handle); Audio.Update(0.05)
    end
end

local routes = {
    {'hit_soft', {material='armor'}, 'cmb_hit_armor_'},
    {'hit_armor', {material='core', tier='critical'}, 'cmb_hit_core_1'},
    {'hit_core', {material='soft'}, 'cmb_hit_soft_'},
    {'sword_whoosh', {tier=3}, 'cmb_sword_whoosh_3'},
    {'arrow_hit', {material='stone'}, 'cmb_arrow_hit_stone_1'},
    {'arrow_hit', {material='body'}, 'cmb_arrow_hit_body_1'},
    {'arrow_hit', {material='armor'}, 'cmb_arrow_hit_armor_1'},
    {'enemy_windup', {enemy='beetle'}, 'cmb_windup_beetle'},
    {'enemy_windup', {enemy='sentry'}, 'cmb_windup_sentry'},
    {'enemy_windup', {enemy='beast', tier='danger'}, 'cmb_windup_beast'},
    {'enemy_die', {enemy='beetle'}, 'cmb_enemy_die_2'},
    {'enemy_die', {enemy='boss'}, 'cmb_enemy_die_1'},
}
for _, row in ipairs(routes) do
    manager:Update(1)
    local handle = manager:Play(row[1], row[2])
    check(sourceFor(manager, handle).sound.path:find(row[3], 1, true), 'semantic routing ' .. row[3])
    manager:Stop(handle)
end
manager:Update(1)
local hit = manager:Play('hit_core', {tier='critical', volume=0.5, pitch=2})
local source = sourceFor(manager, hit)
check(close(source.gain, 10 ^ (-4/20) * 0.5), 'relative +2dB with -6dB headroom')
check(source.frequency >= 48000 * 1.94 and source.frequency <= 48000 * 2.06, 'pitch multiplies sample rate')
manager:SetVolume(0.25)
check(close(source.gain, 10 ^ (-4/20) * 0.125), 'master volume updates active sounds')
manager:SetVolume(2); check(manager.volume == 1, 'volume clamped')
manager:SetVolume(-1); check(source.gain == 0, 'zero volume')
manager:SetEnabled(false); check(Mock.Active(mock) == 0, 'disable stops all')
check(manager:Play('hit_soft') == nil, 'disabled ignores play')
manager:SetEnabled(true); manager:SetVolume(1)

manager, mock = fresh()
for name in pairs(expected) do
    manager:Update(1)
    local handle = manager:Play(name)
    check(handle and manager:Play(name) == nil, 'throttle ' .. name)
    manager:Stop(handle); manager:Update(0.05)
end
manager, mock = fresh()
local layers = {'hit_soft', 'hit_heavy', 'hit_core', 'armor_break'}
for _, event in ipairs(layers) do manager:Play(event, {hitId='attack:1'}); manager:Update(0.01) end
check(Mock.Active(mock) == 3, 'same impact caps at three across frames')
check(manager.pool[1].event == 'armor_break', 'break replaces oldest ordinary layer')
manager, mock = fresh()
for _, event in ipairs(layers) do manager:Play(event) end
check(Mock.Active(mock) == 3, 'implicit same-frame impact budget')

for _, quality in ipairs({'low','mid','high'}) do
    manager, mock = fresh(); manager:SetQuality(quality)
    local first
    for _ = 1, manager.limit do
        local handle = manager:Play('sword_whoosh'); first = first or handle; manager:Update(0.06)
    end
    check(Mock.Active(mock) == manager.limit, quality .. ' voice cap fill')
    local warning = manager:Play('enemy_windup')
    check(warning and not isActive(manager, first), 'warning evicts oldest normal')
    check(Mock.Active(mock) == manager.limit, quality .. ' no overflow')
    manager:SetQuality('low'); check(Mock.Active(mock) == 8, 'lower quality evicts immediately')
    check(isActive(manager, warning), 'lower quality preserves warning')
end
manager, mock = fresh(); manager:SetQuality('low')
local low = manager:Play('sword_whoosh'); manager:Update(0.1)
local armor = manager:Play('armor_break'); manager:Update(0.1)
local hurt = manager:Play('player_hurt'); manager:Update(0.1)
for _ = 1, 5 do manager:Play('enemy_windup'); manager:Update(0.1) end
manager:Play('boss_roar')
check(not isActive(manager, low) and isActive(manager, armor), 'ordinary before armor')
manager:Update(0.3); manager:Play('boss_roar')
check(not isActive(manager, armor) and isActive(manager, hurt), 'armor before hurt')
manager:Update(0.3); manager:Play('boss_roar')
check(not isActive(manager, hurt), 'hurt before warnings')
manager:Update(0.3)
check(manager:Play('sword_whoosh') == nil and Mock.Active(mock) == 8, 'ordinary cannot steal warning')

manager, mock = fresh()
local bow = manager:Play('bow_draw'); source = sourceFor(manager, bow)
manager:Update(0.68)
check(source.seek and source.seek < 0.65, 'bow uses 650ms loop region, skips MP3 padding')
check(manager:Play('bow_draw') == bow, 'held bow does not stack loops')
manager:Stop(bow)
check(source.stopCalls == 1 and source.fadingOut, 'fade requested synchronously')
manager:Update(0.02)
check(source.gain > 0 and source.gain < 10 ^ (-18/20), 'fade gain ramps down')
manager:Stop(bow); check(source.stopCalls == 1, 'repeated stop does not restart fade')
manager:Update(0.021)
check(source.gain == 0 and not source.fadingOut and not isActive(manager, bow), 'loop silent by 41ms')
local newBow = manager:Play('bow_draw')
check(newBow and not manager:Stop(bow) and isActive(manager, newBow), 'stale handle cannot stop reused slot')

manager, mock = fresh()
mock.listener = {node = {worldPosition = {x=0,y=0,z=0}}}
local warning = manager:Play('enemy_windup', {pos={x=10,y=0,z=0}})
source = sourceFor(manager, warning)
check(source.kind == 'SoundSource3D' and source.near == 2 and source.far == 35, 'native spatial attenuation')
check(source.node.worldPosition.x == 10, 'world-space source position')
check(source.autoRemoveMode == 0 and source.declickEnabled, 'pooled nodes survive completion and native declick is enabled')
manager:Stop(warning)
for i = 1, 100 do
    local handle
    if i % 2 == 0 then handle = manager:Play('enemy_windup', {pos={x=10,y=0,z=0}})
    else handle = manager:Play('sword_whoosh') end
    manager:Stop(handle); manager:Update(0.1)
end
check(#mock.nodes == 1 and #mock.sources == 2, '2D/3D switching reuses bounded components on one slot')
manager, mock = fresh({no3D=true})
mock.listener = {node = {worldPosition = {x=0,y=0,z=0}}}
local savedPrint, logs = print, {}
_G.print = function(message) logs[#logs+1] = message end
warning = manager:Play('enemy_windup', {pos={x=18.5,y=0,z=0}})
source = sourceFor(manager, warning)
check(source.kind == 'SoundSource', '3D failure falls back')
check(close(source.gain, 10 ^ (-11/20) * 0.5), 'fallback distance gain')
mock.listener.node.worldPosition = {x=18.5,y=0,z=0}; manager:Update(0.1)
check(close(source.gain, 10 ^ (-11/20)), 'moving listener changes fallback gain')
manager:Play('enemy_windup', {pos={x=20,y=0,z=0}})
check(mock.attempts3D == 1 and #logs == 1, 'unsupported 3D probes/logs once')
_G.print = savedPrint
manager, mock = fresh()
manager:SetListenerPosition({x=100,y=0,z=0})
warning = manager:Play('enemy_windup', {pos={x=135,y=0,z=0}})
check(sourceFor(manager, warning).gain == 0, 'no listener fallback uses explicit player position')

for _, config in ipairs({{missing=true}, {resourceError=true}, {noSource=true}, {noScene=true}, {playError=true}}) do
    manager, mock = fresh(config, true); logs = {}
    _G.print = function(message) logs[#logs+1] = message end
    for _ = 1, 20 do
        manager:Preload(); check(manager:Play('hit_soft') == nil, 'failure is silent'); manager:Update(0.1)
    end
    check(#logs == 1, 'failure logs once per category')
    check(#mock.nodes <= 1 and Mock.Active(mock) == 0, 'failure does not leak nodes/voices')
    _G.print = savedPrint
end

-- Cold combat: only one demand load, never plays its late sound in this frame.
manager, mock = fresh(nil, true)
check(manager:Play('bow_draw') == nil and mock.readCount == 1, 'cold play loads one and stays silent')
check(manager:Play('bow_draw') == nil and mock.readCount == 1, 'same-frame repeat cannot play newly loaded asset')
check(manager:Play('bow_full') == nil and mock.readCount == 1, 'second cold event shares frame load allowance')
for _ = 1, 10 do manager:Play('bow_full') end
check(#manager.demandQueue == 1, 'deferred demand is deduplicated')
manager:Preload(); check(mock.readCount == 1, 'combat Preload never performs bulk I/O')
manager:Update(1/60)
check(mock.readCount == 2 and mock.reads['audio/sfx/cmb_bow_full.mp3'] == 1, 'next frame loads demand before idle queue')
check(manager:Play('bow_full') == nil, 'background load also cannot play in its load frame')
check(Mock.Active(mock) == 0, 'cold events are not replayed automatically')
check(manager:Play('bow_draw') ~= nil, 'later fresh event can use ready asset')
manager:Update(1/60)
check(manager:Play('bow_full') ~= nil, 'next-frame explicit event plays normally')
for _ = 1, 45 do manager:Preload(); manager:Update(1/60) end
check(manager:IsReady() and mock.readCount == 38, 'demand and idle queue share cache without duplicate loads')
for _, count in pairs(mock.reads) do check(count == 1, 'each successful path loaded once') end

-- Budget uses wall time, not dt (a long dt must not cause catch-up batches).
manager, mock = fresh(nil, true)
mock.engineFrame = 100
manager:Play('bow_full'); manager:Preload(); manager:Update(1/60)
check(mock.readCount == 1 and manager:Play('bow_full') == nil, 'Play before Update shares native frame budget and silent frame')
manager:Update(1/60)
check(mock.readCount == 1, 'repeated Update in same engine frame cannot duplicate loads')
mock.engineFrame = 101
manager:Update(1/60); manager:Play('bow_draw')
check(mock.readCount == 2, 'Update before Play shares native frame budget')
check(manager:Play('bow_full') ~= nil, 'native next-frame playback allowed')
manager, mock = fresh({loadMs=0.5}, true)
manager:Preload(); manager:Update(20)
check(mock.readCount == 1 and close(manager.loadSpentMs, 0.5), 'cheap loads still limited to one, large dt no catch-up')
mock.listenerMs = 2
manager:Update(1/60)
check(mock.readCount == 1, 'spent 2ms Update budget defers work')
manager:Play('bow_full')
check(mock.readCount == 1, 'cold Play cannot bypass exhausted Update budget')
mock.listenerMs = 0
manager:Update(1/60)
check(mock.readCount == 2, 'budget-deferred queue resumes next frame')
manager, mock = fresh({loadMs=3}, true)
manager:Preload(); manager:Update(1/60)
check(mock.readCount == 1 and manager.loadSpentMs == 3, 'single non-preemptible slow load is measured')
manager:Play('bow_full'); manager:Preload()
check(mock.readCount == 1, 'over-budget load prevents further loads in frame')
manager:Update(1/60)
check(mock.readCount == 2, 'slow-load remainder continues next frame')

manager, mock = fresh({missing=true}, true); logs = {}
_G.print = function(message) logs[#logs+1] = message end
manager:Preload()
for _ = 1, 80 do manager:Preload(); manager:Update(1/60); manager:Play('bow_full') end
loaded, assetTotal = manager:PreloadProgress()
check(loaded == 0 and assetTotal == 38 and not manager:IsReady(), 'failed assets do not count as ready')
check(mock.readCount == 38 and #logs == 1, 'failed resource paths terminal, one failure log')
_G.print = savedPrint
manager:Dispose(); manager:Preload(); manager:Update(1)
check(not manager:IsReady() and mock.readCount == 38 and #manager.demandQueue == 0, 'dispose cancels pending loads')

manager, mock = fresh(nil, true)
manager:Preload(); manager:Update(1/60)
manager:Dispose(); manager:Update(1)
check(mock.readCount == 1, 'dispose interrupts incomplete preload')

manager, mock = fresh({stopError=true})
bow = manager:Play('bow_draw'); source = sourceFor(manager, bow)
manager:Stop(bow)
check(source.gain == 0 and Mock.Active(mock) == 0, 'broken native fade falls back to immediate mute')
manager, mock = fresh({seekError=true}); logs = {}
_G.print = function(message) logs[#logs+1] = message end
manager:Play('bow_draw'); manager:Update(0.7)
check(Mock.Active(mock) == 0 and #logs == 1, 'unsupported loop seeking stops safely')
_G.print = savedPrint

manager, mock = fresh()
for i = 1, 600 do
    local event = i % 2 == 0 and 'sword_whoosh' or 'player_hurt'
    local handle = manager:Play(event)
    check(handle ~= nil, 'pool reuse playback')
    source = sourceFor(manager, handle)
    source.playing = false -- mixer completed a one-shot
    manager:Update(0.1)
end
check(#mock.nodes == 1 and #mock.sources == 1, '600 events reuse one node/source')
manager:Dispose(); manager:Dispose()
check(mock.nodes[1].removed and mock.nodes[1].disposed, 'dispose releases owned pool nodes')
check(manager:Play('hit_soft') == nil, 'disposed manager ignores play')
manager:Update(1)
print('PASS CombatAudio: ' .. checks .. ' assertions (' .. _VERSION .. ')')
