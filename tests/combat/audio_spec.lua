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
        for _ = 1, 80 do manager:Update(1/60) end
    end
    return manager, mock
end
local function sourceFor(manager, handle)
    for _, slot in ipairs(manager.pool) do if slot.handle == handle then return slot.source end end
end
local function isActive(manager, handle) return sourceFor(manager, handle) ~= nil end
math.randomseed(731)

local expected = {sword_whoosh=3, sword_full=1, hit_soft=3, hit_armor=3, hit_heavy=2, hit_core=1,
    armor_break=2, deflect_stone=2, bow_draw=1, bow_full=1, bow_fire=2, arrow_hit=3,
    blade_draw=1, blade_sheath=1, enemy_windup=3, player_hurt=2, run_step=1,
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
check(total == 37 and names == 21, '37 references / 21 events, sword_full/run_step reuse existing assets (36 unique assets)')
manifest.hit_soft.files[1] = 'corrupted'
check(Audio.Events().hit_soft.files[1] ~= 'corrupted', 'manifest isolated')

check(not Audio.IsReady(), 'no manager is not ready')
local initialLoaded, initialTotal = Audio.PreloadProgress()
check(initialLoaded == 0 and initialTotal == 36, 'no manager progress')
local manager, mock = fresh(nil, true)
local loaded, assetTotal = Audio.Preload()
check(loaded == 0 and assetTotal == 36 and mock.readCount == 0, 'Preload only queues, no synchronous I/O')
check(not Audio.IsReady(), 'queued but not ready')
for frame = 1, 80 do
    local readsBefore = mock.readCount
    Audio.Preload(); Audio.Update(1/60)
    loaded, assetTotal = Audio.PreloadProgress()
    check(loaded == math.min(math.floor(frame/2),36) and assetTotal == 36, 'async monotonic progress')
    check(mock.readCount-readsBefore <= 1, 'at most one file request each frame')
    check(Audio.IsReady() == (frame >= 72), 'ready only after all async resources completed')
end
check(mock.readCount == 36 and mock.syncReads == 0, 'async preload without GetResource')
check(manager:IsFirstStrikeReady() and manager.readySources==12, 'idle prebuilt first-strike readiness')
check(mock.order[1]:find('sword_whoosh_1') and mock.order[2]:find('sword_whoosh_2') and mock.order[3]:find('sword_whoosh_3'), 'all three swings are first')
check(mock.order[4]:find('hit_heavy_1') and mock.order[6]:find('hit_soft_1'), 'heavy then materials')
Audio.Preload(); Audio.Update(1/60)
check(mock.readCount == 36, 'completed Preload is idempotent')
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
        local basePitch=name=='sword_full' and .8 or 1
        check(pitch >= basePitch*.97 and pitch <= basePitch*1.03, 'pitch within 3 percent of authored base')
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
    for _ = 1, 15 do manager:Update(1/60) end
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
manager:Update(0.01)
check(source.gain > 0 and source.gain < 10 ^ (-18/20), 'fade gain ramps down')
manager:Stop(bow); check(source.stopCalls == 1, 'repeated stop does not restart fade')
manager:Update(0.011)
check(source.gain == 0 and not source.fadingOut and not isActive(manager, bow), 'loop silent by 21ms')
local newBow = manager:Play('bow_draw')
check(newBow and not manager:Stop(bow) and isActive(manager, newBow), 'stale handle cannot stop reused slot')
manager, mock = fresh()
local fullBow=manager:Play('bow_full')
manager:Update(.119);check(isActive(manager,fullBow),'full cue remains audible before 120ms')
manager:Update(.002);check(not isActive(manager,fullBow),'full cue ends within 120ms plus frame boundary')

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
check(#mock.nodes == 12 and #mock.sources == 24, '2D/3D switching never expands prebuilt components')
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
check(mock.attempts3D == 1 and #logs == 0, 'unsupported 3D probes/logs once')
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
    check(#mock.nodes <= 12 and Mock.Active(mock) == 0, 'failure does not leak nodes/voices')
    _G.print = savedPrint
end

-- Cold combat has no I/O, nodes, components, or automatic late replay.
manager, mock = fresh(nil, true)
check(manager:Play('bow_draw') == nil and mock.readCount == 0, 'cold Play never loads')
for _ = 1, 10 do
    manager:Play('sword_whoosh', {tier=1}); manager:Preload(); manager:Update(1/60, false)
end
check(mock.readCount==0 and #mock.nodes==0, 'combat suppresses all idle warmup')
local priorState = package.loaded['combat.CombatState']
local stateName = 'COMBAT_ACTIVE'
package.loaded['combat.CombatState'] = {EXPLORE='EXPLORE', Get=function() return stateName end}
manager:Update(1/60)
check(mock.readCount==0 and #mock.nodes==0, 'default Update uses existing CombatState, no Scene changes')
package.loaded['combat.CombatState'] = priorState
for _ = 1, 6 do manager:Update(1/60, true) end
check(manager:IsFirstStrikeReady(), 'first three swings warm before other files')
check(Mock.Active(mock)==0, 'warming never plays or unlocks browser audio')
manager:Update(1/60, false)
local readyHandle=manager:Play('sword_whoosh', {tier=1})
check(readyHandle~=nil, 'hot cue plays at current call, not a later Update')
local readsBefore,nodesBefore,sourcesBefore=mock.readCount,#mock.nodes,#mock.sources
for _ = 1, 40 do
    manager:Update(0.1, false)
    manager:Play('sword_whoosh', {tier=3}); manager:Play('armor_break')
end
check(mock.readCount==readsBefore and #mock.nodes==nodesBefore and #mock.sources==sourcesBefore, 'combat neither expands partial pool nor loads cold materials')
for _=1,100 do manager:Update(1/60,true) end
check(manager:IsReady() and mock.readCount==36 and #mock.nodes==12, 'idle resumes complete warmup without duplicate requests')
for _,count in pairs(mock.reads) do check(count==1,'requests deduplicated') end

-- Quality changes during combat cannot allocate; saturated warnings reject decor.
manager:SetQuality('high')
for _=1,20 do manager:Update(0.1,false); manager:Play('enemy_windup') end
nodesBefore,sourcesBefore=#mock.nodes,#mock.sources
check(Mock.Active(mock)==12,'high quality is limited by idle-prebuilt capacity until next exploration')
check(manager:Play('sword_whoosh',{tier=1})==nil,'saturated warning pool drops lower priority cue')
check(#mock.nodes==nodesBefore and #mock.sources==sourcesBefore,'pool exhaustion never builds')
for _=1,12 do manager:Update(1/60,true) end
check(manager.readySources==16 and #mock.nodes==16,'high quality expansion occurs only in idle')

-- Same native frame admits at most one resource and one construction operation.
manager, mock = fresh(nil,true); mock.engineFrame=100
manager:Update(1/60); manager:Update(1/60); manager:Play('bow_full')
check(mock.readCount==1 and #mock.nodes==1 and #mock.sources==0, 'same frame budget')
mock.engineFrame=101; manager:Update(1/60)
check(mock.readCount==1 and #mock.sources==1, 'async completion uses frame allowance')

-- Budget includes earlier audio work; sync compatibility only ever runs in idle.
manager,mock=fresh({noAsync=true,loadMs=3},true)
manager:Update(1/60)
check(mock.syncReads==0, 'unsupported async does not retry synchronously same frame')
manager:Update(1/60,false)
check(mock.syncReads==0, 'compatibility loader forbidden in combat')
manager:Update(1/60,true)
check(mock.syncReads==1 and #mock.sources==0, '3ms non-preemptible load defers source creation')
manager:Play('bow_full'); check(mock.syncReads==1, 'Play never bypasses budget')
mock.listenerMs=2; manager:Update(1/60,true)
check(mock.syncReads==1, '2ms prior work defers remaining queue')
mock.listenerMs=0; manager:Update(1/60,true)
check(mock.syncReads==2, 'next idle frame resumes queue')
manager,mock=fresh({loadMs=3},true); mock.engineFrame=300
manager:Update(1/60,true); manager:Update(1/60,true)
check(mock.readCount==1 and #mock.nodes==0,'same native frame cannot bypass over-budget resource via second Update')
manager,mock=fresh({asyncReject=true},true)
manager:Update(1/60,true)
check(mock.syncReads==0,'rejected background request cannot synchronously retry')
manager:Update(1/60,false)
check(mock.syncReads==0,'rejected async fallback remains exploration-only')
manager:Update(1/60,true)
check(mock.syncReads==1 and manager.loadedCount==1,'API-present-but-rejected host supports later idle fallback')

-- Diagnostic clock, fields, rate limit and RUINS.combat.state switch.
manager,mock=fresh({loadMs=5},true);logs={}
_G.print=function(message) logs[#logs+1]=message end
_G.RUINS={combat={state={audioPerf=true}}}
for _=1,8 do manager:Update(1/60,true) end
check(#logs==1 and logs[1]:find('cue=sword_whoosh') and logs[1]:find('cold=true') and logs[1]:find('newSource=false'),'cold load diagnostic and rate limit')
_G.RUINS.combat.state.audioPerf=false
for _=1,10 do manager:Update(1,true) end
check(#logs==1,'diagnostics disabled by live state switch')
_G.print=savedPrint;_G.RUINS=nil
manager,mock=fresh({createMs=5},true);logs={}
_G.print=function(message) logs[#logs+1]=message end
manager:Update(1/60,true)
check(#logs==1 and logs[1]:find('cue=pool') and logs[1]:find('cold=false') and logs[1]:find('newSource=true'),'source construction diagnostic')
_G.print=savedPrint

manager,mock=fresh({missing=true},true);logs={}
_G.print=function(message) logs[#logs+1]=message end
for _=1,100 do manager:Preload();manager:Update(1/60,true) end
loaded,assetTotal=manager:PreloadProgress()
check(loaded==0 and assetTotal==36 and not manager:IsReady(),'failed resources are not ready')
check(mock.readCount==36 and #logs==1,'terminal failures log once, no repeated loads')
_G.print=savedPrint
manager:Dispose();manager:Preload();manager:Update(1,true)
check(not manager:IsReady() and mock.readCount==36,'dispose cancels queued work')

-- Async pending work is not finalized by Lua in combat and never replays a cue.
manager,mock=fresh({asyncDelay=4},true)
manager:Update(1/60,true)
for _=1,20 do manager:Update(1/60,false) end
check(manager.loadedCount==0 and mock.syncReads==0,'pending resource does not force blocking retrieval')
manager:Dispose();manager:Update(1,true)
check(mock.readCount==1,'dispose abandons pending resource reference')

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
check(#mock.nodes == 12 and #mock.sources == 24, '600 events stay in prebuilt pool')
manager:Dispose(); manager:Dispose()
check(mock.nodes[1].removed and mock.nodes[1].disposed, 'dispose releases owned pool nodes')
check(manager:Play('hit_soft') == nil, 'disposed manager ignores play')
manager:Update(1)
print('PASS CombatAudio: ' .. checks .. ' assertions (' .. _VERSION .. ')')
manager,mock=fresh()
local swordFull=manager:Play('sword_full')
local bowFull=manager:Play('bow_full')
check(swordFull and bowFull and swordFull~=bowFull,'separate full cue rate keys')
local fullSource=sourceFor(manager,swordFull)
check(fullSource.sound.path=='audio/sfx/cmb_bow_full.mp3','sword full reuses existing sample')
check(close(fullSource.gain,10^(-12/20)),'sword full -6dB plus existing -6dB bus')
check(manager:Play('sword_full')==nil,'duplicate edge is independently rate limited')
manager:Dispose()
print('PASS R8 sword_full reused sample, .8 pitch, -6dB cue and independent key; same-frame material/core+heavy layering retained')
manager,mock=fresh()
local runStep=manager:Play('run_step')
check(runStep~=nil,'prewarmed existing sample is ready for a run step')
local stepSource=sourceFor(manager,runStep)
check(stepSource.sound.path=='audio/sfx/cmb_dodge_land.mp3','run step reuses landing asset')
check(close(stepSource.gain,10^(-20/20)),'run step -14dB plus -6dB bus')
check(manager:Play('run_step')==nil,'footsteps rate limited to .12s')
manager:Dispose()
print('PASS R9 reused run_step sample, -14dB cue, no new preload or runtime resources')
