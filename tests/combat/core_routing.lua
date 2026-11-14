-- Exercise actual Scene charge/breath routing with an offline input/caster mock.
local file=assert(io.open('scripts/ruins/RuinsScene.lua','r'))
local source=file:read('*a');file:close()
local state={allowed=true,combat=false}
local keys,press,touchDown,touchPress={},{},{},{}
local touch=false
local casts,charges={},{}
local caster={charging=false,charge=0}
function caster:HandleCharge(on) charges[#charges+1]=on;self.charging=on end
function caster:Cast(id) casts[#casts+1]=id end
function caster:Say(text) self.message=text end
local env=setmetatable({M={mounted=false,debugOn=false,ride={mode='free'},ctrl={state='IDLE'}},
    caster_=caster,voidInputBlocked=false,combatInputBlocked=false,combatNoticeAt=0,time_=10,
    KEY_1=1,KEY_2=2,KEY_3=3,KEY_E=4,KEY_Q=5,MOUSEB_LEFT=1,
    CombatState={CanUseTime=function() return state.allowed end,InCombat=function() return state.combat end},
    TouchControls={IsBlocked=function() return false end},
    TouchInput={IsEnabled=function() return touch end,Down=function(k) return touchDown[k] or false end,
        Press=function(k) local p=touchPress[k];touchPress[k]=nil;return p end},
    input={focus=true,minimized=false,GetMouseButtonDown=function() return keys.mouse or false end},
    pointer={CanAttack=function() return not keys.blocked end,IsEnabled=function() return true end},
    Down=function(k) return keys[k] or false end,
    Press=function(k) local p=press[k];press[k]=nil;return p end}, {__index=_G})
-- Use actual newline boundaries (not a Lua runtime function approximation).
local body=source:match('(local function HandleSpells.-)'..string.char(10)..'function Ruins_HandleSceneUpdate')
local handle=assert(load(body..string.char(10)..'return HandleSpells','Scene.HandleSpells','t',env))()
keys.mouse=true;handle(.1,{});assert(caster.charging and #charges==1)
keys.mouse=false;handle(.1,{});assert(not caster.charging and #charges==2)
press[4],press[5]=true,true;handle(.1,{});assert(casts[1]=='freeze' and casts[2]=='rewind')
state.allowed,state.combat=false,true;caster.charging=true;keys.mouse=true;press[4]=true
handle(.1,{});assert(not caster.charging and caster.message=='战斗中无法使用时间之力' and #casts==2)
local count=#charges
state.combat=false;handle(.1,{});assert(#charges==count)
state.allowed=true;env.combatInputBlocked=true;handle(.1,{});assert(#charges==count)
env.combatInputBlocked=false;keys.mouse=false;touch=true;touchPress.shatter=true
handle(.1,{});assert(charges[#charges-1]==true and charges[#charges]==false)
env.M.mounted=true;touchDown.shatter=true;handle(.1,{});assert(not caster.charging)
local stream=assert(source:match('(function M.readStreamInput.-)'..string.char(10)..'%-%- 当前瞄准目标'))
assert(load(stream,'Scene.readStreamInput','t',env))()
env.M.ride.mode='mounted';touchDown.breath=true
local held,allowed=env.M.readStreamInput();assert(held and allowed)
env.M.ctrl.state='BREATH';held,allowed=env.M.readStreamInput();assert(held and not allowed)
env.M.ctrl.state='IDLE';touchDown.breath=false;touch=false;keys.mouse=true;keys.blocked=true
held,allowed=env.M.readStreamInput();assert(not held and not allowed)
keys.blocked=false;held,allowed=env.M.readStreamInput();assert(held and allowed)
env.M.ride.mode='free';held,allowed=env.M.readStreamInput();assert(not held and not allowed)
local cue=assert(source:match('(function Ruins_HandleEnemyAttackCue.-)\nend'))..'\nend'
env.M.combat={};env.DebugLog={Log=function() end}
local sounds={}
env.CombatAudio={Play=function(name,opts) sounds[#sounds+1]=name end}
assert(load(cue,'Scene.EnemyAttackCue','t',env))()
local fields={EnemyId='sentry_1',Attack='stone',Phase='telegraph',Position={x=1,y=2,z=3},Duration=.9,Event='enemy_windup',Enemy='sentry',Material='stone',Tier='light'}
local event={GetBool=function(_,key) return fields[key]==true end,GetString=function(_,key) return fields[key] end,GetFloat=function(_,key) return fields[key] end,
    GetVector3=function(_,key) return fields[key] end}
---@cast event VariantMap Offline adapter implements only fields consumed by handler.
env.Ruins_HandleEnemyAttackCue(nil,event)
local snapshot=env.M.combat.enemyCue
assert(snapshot.enemyId=='sentry_1' and snapshot.duration==.9 and snapshot.phase=='telegraph')
assert(sounds[1]=='enemy_windup')
fields.Event='attack_active';fields.Phase='active';env.Ruins_HandleEnemyAttackCue(nil,event)
assert(env.M.combat.enemyCue==snapshot and snapshot.phase=='active','sound event reuses one bounded event snapshot')
assert(#sounds==1,'active visual cue does not replay windup audio')
env.CombatState=dofile('scripts/combat/CombatState.lua')
local notices={};env.CombatHUD={Say=function(text) notices[#notices+1]=text end}
env.KEY_F2,env.KEY_F3=102,103
env.KEY_F5,env.KEY_F6=105,106
env.KEY_F8,env.KEY_F9,env.KEY_SHIFT,env.KEY_F11=108,109,110,111
env.StartCombatTest=function() end
local transfers,dummies=0,0
env.DebugTransfer=function() transfers=transfers+1 end
env.ToggleTrainingDummy=function() dummies=dummies+1 end
local mobile=false;env.PlatformUtils={IsMobilePlatform=function() return mobile end}
local debugKeys=assert(source:match('(local function HandleCombatDebugKeys.-)\nend'))..'\nend\nreturn HandleCombatDebugKeys'
local debug=assert(load(debugKeys,'Scene.PC combat debug keys','t',env))()
assert(env.CombatState.GetSetting('aimAssist') and not env.CombatState.GetSetting('damageNumbers'))
touch=true;press[105],press[106]=true,true;debug(true)
assert(#notices==0 and env.CombatState.GetSetting('aimAssist'),'touch mode ignores debug keys')
touch=false;debug(false);assert(#notices==0,'modal/focus gate blocks debug keys')
mobile=true;debug(true);assert(#notices==0,'native mobile cannot toggle even with touch forced off');mobile=false
debug(true)
assert(not env.CombatState.GetSetting('aimAssist') and env.CombatState.GetSetting('damageNumbers') and #notices==2)
debug(true);assert(#notices==2,'debug switches only on a key press edge')
press[105],press[106]=true,true;debug(true)
assert(env.CombatState.GetSetting('aimAssist') and not env.CombatState.GetSetting('damageNumbers'))
press[108],press[109]=true,true;touch=true;debug(true)
assert(transfers==0 and dummies==0,'touch mode blocks debug teleport and dummy')
touch=false;debug(true);assert(transfers==1 and dummies==1)
debug(true);assert(transfers==1 and dummies==1,'debug actions trigger once per edge')
keys[110]=true;press[109]=true;debug(true)
assert(dummies==1,'Shift+F9 remains touch emulation, not dummy')
keys[110]=nil
local stopped=0
env.ForgePanel={Close=function(keep) assert(keep);stopped=stopped+1 end}
local stop=assert(source:match('(function M.Stop%(%).-)%s+if M.atmosphere'))..'\nend'
assert(load(stop,'Scene forge disposal prefix','t',env))()
env.M.Stop();assert(stopped==1,'forced close works without optional ForceClose API')
env.ForgePanel.ForceClose=function() stopped=stopped+10 end
env.M.Stop();assert(stopped==12,'Scene also invokes optional ForceClose')
print('PASS core_routing: Scene exploration charge/tap/freeze/rewind, combat+exit gates, mounted breath, pointer gate, special exclusivity')

press[102]=true;debug(true)
assert(not env.CombatState.GetSetting('cameraShake') and env.CombatState.GetSetting('cameraFov'))
press[103]=true;debug(true)
assert(not env.CombatState.GetSetting('cameraFov'),'F2/F3 independent effect toggles')
print('PASS enemy authored sound cue routing, no active duplicate, independent camera debug switches')

-- Particle integration borrows the Spawner pool; never emits a second enemy hit.
local feedbackBody=assert(source:match('(local function CombatFeedback.-)\nend'))..'\nend\nreturn CombatFeedback'
local particleCalls={}
local particleOwner={}
local feedbackEnv=setmetatable({combatParticles_={Emit=function(_,owner,event)
 assert(owner==particleOwner and type(event)=='table' and event.pos and event.dir)
 particleCalls[#particleCalls+1]=event
end},hitParticleOwner_=particleOwner,time_=1},{__index=_G})
local feedback=assert(load(feedbackBody,'Scene shared particle consumer','t',feedbackEnv))()
local enemyImpact={enemy={particles={}},kind='hit',pos={},dir={},material='armor'}
feedback(enemyImpact);assert(#particleCalls==0,'enemy settlement already owns impact particles')
feedback({player=true,kind='hit',pos={},dir={},material='soft'})
feedback({kind='hit',pos={},dir={},material='stone',tier='arrow_mid'})
assert(#particleCalls==2,'player and wall arrow use shared pool new table signature')
assert(source:find('combatEnemies_:GetParticlePool()',1,true))
assert(not source:find('combatParticles_:Release',1,true),'borrower must not release owner pool reference')
local rigStart=assert(source:find('local offset,euler=combatAnim_:GetWeaponPose()',1,true))
local swing=assert(source:find('combatRig_:SetSwing(offset,euler)',rigStart,true))
local sample=assert(source:find('combatRig_:GetAfterimagePose()',rigStart,true))
local update=assert(source:find('combatRig_:Update(dt)',rigStart,true))
assert(swing<sample and sample<update,'SetSwing this frame before world pose sample, then advance Rig once')
print('PASS no duplicate enemy particles, player/wall shared pool table port, borrower cleanup, current-frame slide snapshot order')

local exclusionBody=assert(source:match('(local function IsCombatVisualVolume.-)\nend'))..'\nend\nreturn IsCombatVisualVolume'
local volumes={{},{},{},{},{},{},{}}
local visualRig={entries={sword={mesh={volume=volumes[1]}}},trails={{volume=volumes[2]}},
 images={{volume=volumes[3]}},bowImages={{volume=volumes[4]}},particles={{volume=volumes[5]}},
 flashes={blade={volume=volumes[6]},socket={volume=volumes[7]}}}
local excludes=assert(load(exclusionBody,'Scene independent visual exclusion','t',setmetatable({combatRig_=visualRig},{__index=_G})))()
for _,volume in ipairs(volumes) do assert(excludes(volume)) end
assert(not excludes({}),'new bow images and flashes cannot occlude aim even with incorrect native layers')
print('PASS independent ray exclusion for main weapon/trail/sword+bow images/charge particles/blade+socket flashes')

-- F11 interruption must leave the original key available to its normal handler.
local keyBody=assert(source:match('(function Ruins_HandleKeyDown.-)\nend'))..'\nend'
local stoppedTest,resumed=0,0
local keyEnv=setmetatable({combatTest_={active=true,Stop=function()stoppedTest=stoppedTest+1 end},
 KEY_F11=111,KEY_W=119,KEY_F10=110,KEY_ESCAPE=27,KEY_E=101,KEY_Q=113,KEY_A=97,KEY_S=115,KEY_D=100,
 ForgePanel={IsOpen=function()return false end},SettingsMenu={IsOpen=function()return false end,IsBlocked=function()return false end},
 TouchInput={IsEnabled=function()return false end},pointer={Resume=function()resumed=resumed+1 end},M={}}, {__index=_G})
assert(load(keyBody,'Scene F11 abort key preservation','t',keyEnv))()
local eventKey=111
local event={GetInt=function()return eventKey end}
keyEnv.Ruins_HandleKeyDown(nil,event);assert(stoppedTest==0)
eventKey=119;keyEnv.Ruins_HandleKeyDown(nil,event);assert(stoppedTest==1 and resumed==1)
local touchCallbacks=assert(source:match('(local function AttachTouchControls.-)\nend'))
assert(not touchCallbacks:find('combatTest_:Stop',1,true),'selftest own per-step TouchControls.Cancel must not abort runner')
print('PASS F11 original key preserved and own cleanup cannot recursively abort')

-- Execute the Scene warmup hook against W5's real incremental loader.
package.path='scripts/?.lua;tests/?.lua;'..package.path
local Audio=require('combat.CombatAudio')
local audioMock=require('combat.audio_mock').New()
Audio.New(audioMock.scene)
local queued,updates,elapsed=0,0,0
local audioEnv={combatAudioWarmup_=0,CombatAudio={
    Preload=function() queued=queued+1; return Audio.Preload() end,
    Update=function(dt) updates=updates+1;elapsed=elapsed+dt;Audio.Update(dt) end}}
local warmupBody=assert(source:match('(local function UpdateCombatAudio.-)\nend'))..'\nend\nreturn UpdateCombatAudio'
local warmup=assert(load(warmupBody,'Scene incremental audio warmup','t',audioEnv))()
warmup(1);warmup(.99)
assert(queued==0 and audioMock.readCount==0,'no preload resources during startup')
warmup(.02)
assert(queued==1 and audioMock.readCount==1,'first frame after 2 seconds queues and loads at most one')
local loaded,total=Audio.PreloadProgress()
assert(loaded==1 and total==38 and not Audio.IsReady(),'second value is total, not missing')
local before=audioMock.readCount
local n,t=Audio.Preload() -- existing enter/draw call remains idempotent and performs zero IO
assert(n==1 and t==38 and audioMock.readCount==before)
for _=1,total+5 do
    before=audioMock.readCount;warmup(.016)
    assert(audioMock.readCount-before<=1,'Scene never batches resource loads')
end
assert(queued==1 and Audio.IsReady() and audioMock.readCount==total)
assert(updates==3+total+5 and math.abs(elapsed-(2.01+(total+5)*.016))<1e-9,'every call forwards unscaled real dt')
audioEnv.combatAudioWarmup_=nil;warmup(.5);assert(queued==1,'cleared/finished timer stays dormant')
audioEnv.combatAudioWarmup_=0;warmup(2);assert(queued==2,'new scene can warm up again')
assert(source:find('CombatAudio.New(scene_)\n    combatAudioWarmup_ = 0',1,true))
assert(source:find('CombatAudio.Dispose()\n    combatAudioWarmup_ = nil',1,true))
assert(source:find('音频预加载 %d/%d',1,true))
Audio.Dispose()
print('PASS Scene 2s warmup, real-time single-frame budget, idempotent enter preload, progress and lifecycle reset')
