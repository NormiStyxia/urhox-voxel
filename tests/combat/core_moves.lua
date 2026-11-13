local S=dofile('tests/combat/core_support.lua')
local A=require('combat.CombatAnim')
local State=require('combat.CombatState')
local C=require('combat.CombatMoves')
local rig={SetActive=function() end,SetPose=function() end,GetStats=function() return {attack=10,speed=1,reach=1,draw=.7,poise=6} end,
    GetHit=function() return {origin=Vector3.ZERO,dir=Vector3(1,0,0),length=1,radius=.12} end}
local count,respawns,shots=0,0,0
local lastShot
local enemy={active=true,GetHurtShapes=function() return {{id='body',center=Vector3(.5,0,0),radius=.3}} end,
    ApplyHit=function() count=count+1; return {hit=true} end}
local function New()
    State.Configure{rig=rig}; State.Enter(); State.Update(.31); State.Activity(true)
    return C.New{anim=A.New(S.anim.character(),nil),state=State,rig=rig,
        forward=function() return Vector3(0,0,1) end,position=function() return Vector3.ZERO end,
        enemies=function() return {enemy} end,respawn=function() respawns=respawns+1 end,
        fire=function(charge,stats,crystal) shots=shots+1; lastShot={charge=charge,crystal=crystal} end}
end
local m=New()
local function Tick(t,c)
    c=c or {}; c.allowed=c.allowed~=false
    m:Update(t,c); m:AfterPose()
end
Tick(.01,{attack=true}); Tick(.1,{attack=true}); Tick(.01,{attack=false})
assert(m.clip=='sword_light_1')
for i=1,40 do Tick(.02) end
assert(count==1,'one hit per enemy per swing')
m=New(); Tick(.01,{attack=true}); Tick(.1,{attack=true}); m:Cancel('touchcancel')
for i=1,50 do Tick(.02) end
assert(count==1 and shots==0,'cancel must not become release')
m=New(); Tick(.01,{dodge=true,axis=Vector3(1,0,0)}); assert(m.iframe)
assert(not m:ApplyHit{dmg=10}.hit)
for i=1,15 do Tick(.02) end
assert(not m.iframe); assert(m:ApplyHit{dmg=10,dir=Vector3(1,0,0)}.hit)
assert(not m:ApplyHit{dmg=10}.hit and m.hp==90)
for i=1,50 do Tick(.02) end
assert(m:ApplyHit{dmg=100}.killed)
for i=1,70 do Tick(.02,{allowed=false}) end
assert(respawns==1 and m.hp==100 and not m.dead)
m=New(); State.SetBusy(false); State.SetWeapon('bow'); State.Update(.5); State.Activity(true)
Tick(.01,{attack=true}); for i=1,40 do Tick(.02,{attack=true}) end
Tick(.01,{attack=false}); Tick(.01)
assert(shots==1,'bow releases exactly once via fire event')
local function Bow()
    m=New(); State.SetBusy(false); State.SetWeapon('bow'); State.Update(.5); State.Activity(true)
end
Bow(); local before=shots
Tick(.01,{heavy=true}); for i=1,33 do Tick(.02) end
assert(shots==before,'automatic crystal cannot fire before full charge cost')
for i=1,5 do Tick(.02) end
assert(shots==before+1 and lastShot.crystal and lastShot.charge>=1,'auto heavy fires one full crystal')
for i=1,45 do Tick(.02) end
assert(shots==before+1,'automatic heavy never repeats without another press')
for _,reason in ipairs({'touchcancel','menu','focus','death','mount','swap','mode'}) do
    Bow(); before=shots
    Tick(.01,{attack=true}); for i=1,20 do Tick(.02,{attack=true}) end
    m:Cancel(reason)
    for i=1,50 do Tick(.02) end
    assert(shots==before,'cancel must discard bow for '..reason)
end
Bow(); before=shots
Tick(.01,{attack=true}); Tick(.01)
for i=1,4 do Tick(.02) end
assert(shots==before,'tap must wait for draw_min event')
for i=1,5 do Tick(.02) end
assert(shots==before+1,'tap after draw_min must fire once')
Bow(); before=shots
Tick(.01,{heavy=true}); for i=1,10 do Tick(.02) end
Tick(.01,{dodge=true,axis=Vector3(1,0,0)})
for i=1,50 do Tick(.02) end
assert(shots==before and not m.autoFire,'dodge discards automatic shot')
m=New(); assert(m:Swap()); assert(m.clip=='weapon_swap_sword_to_bow')
Tick(.18); assert(not m:Action('dodge',Vector3(1,0,0)),'swap first .2 is not cancellable')
Tick(.03); assert(m:Action('dodge',Vector3(1,0,0)),'swap cancel follows animation event')
m=New(); assert(m:Swap()); Tick(.41)
assert(State.GetWeapon()=='bow' and State.TransitionRemaining()==0 and not m.clip,'weapon_ready completes swap')
local getStats=rig.GetStats
rig.GetStats=function() local stats=getStats();stats.chargeMultiplier=.92;return stats end
m=New(); Tick(.01,{attack=true})
for i=1,44 do Tick(.02,{attack=true}) end
assert(not m.fullCharged,'full-charge remains an animation event, not display progress')
for i=1,3 do Tick(.02,{attack=true}) end
assert(m.fullCharged,'crystal pommel advances charge clip by its multiplier')
rig.GetStats=getStats
m=New(); m:Play('getup'); Tick(.46)
assert(not m.clip and next(m.protection),'getup finishes pose at .45 but keeps real-time protection')
assert(m:Action('dodge',Vector3(1,0,0)))
Tick(.10); assert(next(m.protection),'new action must not cancel independent getup tail')
Tick(.05); assert(not next(m.protection),'protection ends at .60 real seconds')
m=New(); Tick(.01,{dodge=true}); assert(m.iframe)
m.hitstop=1; m.invuln=.8; Tick(.30)
assert(not m.iframe and math.abs(m.invuln-.5)<.000001,'hitstop never pauses iframe or damage immunity clocks')
print('PASS real animation events: sword dedupe, cancel no cast, dodge iframe, invuln, death respawn, bow fire')

-- F7 seek follows authored events without sending them through gameplay handlers.
local preview=A.New(S.anim.character(),nil)
local t,events=C.SeekPreview(preview,'sword_light_1',.1,2/30)
S.near(t,.1); assert(C.PreviewPhase('sword_light_1',t)=='active' and events:find('hit_on',1,true))
t,events=C.SeekPreview(preview,'sword_light_1',2/30,.1)
assert(C.PreviewPhase('sword_light_1',t)=='anticipation' and not events:find('hit_on',1,true))
t,events=C.SeekPreview(preview,'sword_heavy_release',7/30,.2)
assert(C.PreviewPhase('sword_heavy_release',t)=='active' and events:find('hit_on',1,true))
assert(preview.queueCount==0,'seek drains preview events without firing gameplay')

local enemiesAt={
 {id='moss_w1',home=Vector3(10,0,10),position=Vector3(10,0,10)},
 {id='sentry_w',home=Vector3(12,0,10),position=Vector3(12,0,10)},
 {id='stone_beast',boss=true,home=Vector3(-10,0,-10),position=Vector3(-10,0,-10)}}
local terrain={GroundHeight=function(x,z) if x<50 then return 0 end end,
 IsSafeGround=function(x,y,z) return z<30 and math.abs(y)<.45 end,HasGround=function() return true end}
for i=1,3 do
 local pos,anchor,label=C.DebugDestination(enemiesAt,terrain,i,function(p) return p.z<15 end)
 assert(pos and anchor and label and terrain.IsSafeGround(pos.x,pos.y,pos.z) and pos.z<15)
end
assert(C.DebugDestination(enemiesAt,terrain,1,function() return false end)==nil,'no teleport without a clear safe point')
assert(C.DebugDestination({},terrain,3)==nil,'missing encounter is never fabricated')

local H=require('combat.Hit')
local dummy=C.NewTrainingDummy(Vector3(1,0,0))
local result=H.Apply(dummy,{dmg=18,kind='arrow',tier='full',part='body'})
assert(result.hit and result.damage==18 and not dummy.dead)
dummy:Update(); assert(dummy.hp==9999)
m=New();State.SetSetting('damageNumbers',false)
m:Feedback(dummy,{dmg=18,poise=0,pos=Vector3.ZERO,dir=Vector3.FORWARD},result,false,true)
S.near(m.numbers[1].untilTime-m.age,1.2)
dummy:Destroy();assert(not dummy.active)

local fx={handGlow=.8,handAcc=.3,handLight={},handL={}}
function fx:Update(dt,pos,color,glow) assert(pos==nil); self.handGlow=glow end
local motes={list={},free={1,2,3,4,5,6,7,8},handAcc=.6}
function motes:Update() end
function motes:Spawn(mote) self.list[#self.list+1]=mote end
function motes:Clear() self.list={} end
C.UpdateHandFX(fx,motes,.1,Vector3(5,6,7),{},.28)
assert(fx.handLight.enabled and fx.handL.brightness>0 and #motes.list>0)
assert((motes.list[1].pos-Vector3(5,6,7)):Length()<.4,'hand particles originate at hand, never world origin')
C.UpdateHandFX(fx,motes,.1,Vector3(5,6,7),{},0)
assert(not fx.handLight.enabled and fx.handL.brightness==0 and fx.handGlow==0 and #motes.list==0 and motes.handAcc==0,'combat removes light and pending hand motes in one update')
print('PASS debug active-frame seek/backstep, real-anchor safety rejection, dummy reset/numbers, hand FX atomic off')

-- Execute the actual Scene preview-clock branch. Apply must not fall back to
-- the still-running exploration base clock while a screenshot frame is paused.
local sceneFile=assert(io.open('scripts/ruins/RuinsScene.lua'))
local sceneSource=sceneFile:read('*a');sceneFile:close()
local previewBranch=assert(sceneSource:match('(        if step~=0 then.-)\n        animPreview_.text='))
local character=S.anim.character()
---@type table Animation port uses mock bones rather than native Node userdata.
local pausedAnim=A.New(character,nil)
C.SeekPreview(pausedAnim,'sword_light_1',.1,0)
local pe=setmetatable({step=0,dt=.2,combatAllowed=true,
 animPreview_={t=.1,paused=true},combatAnim_=pausedAnim,CombatMoves=C,
 clip=require('combat.AnimClips').Clips.sword_light_1},{__index=_G})
local frame=assert(load(previewBranch,'actual Scene preview clock','t',pe))
for i=1,3 do
 frame();character.time=i*.2;S.anim.reset(character);pausedAnim:Apply()
 S.near(pausedAnim.tracks[1].t,.1);S.near(pe.animPreview_.t,.1)
end
pe.animPreview_.paused=false;pe.combatAllowed=false
frame();character.time=1;S.anim.reset(character);pausedAnim:Apply()
S.near(pausedAnim.tracks[1].t,.1)
pe.combatAllowed=true;pe.animPreview_.t=.74
frame();S.near(pe.animPreview_.t,0);S.near(pausedAnim.tracks[1].t,0)
print('PASS actual Scene F7 pause/focus frames suppress Apply fallback; loop display clock matches pose')

-- §18: actual W4 clip + player input loop, no Runtime/engine emulation claim.
local function Slide() m=New(); assert(m:Action('dodge',Vector3(1,0,0))); return m end
local function Travel(fps,stop)
    Slide();m.hitstop=1
    local distance=0
    for i=1,math.ceil(.34*fps) do
        Tick(1/fps)
        distance=distance+m.motion:Length()
    end
    return distance
end
S.near(Travel(30),2.2);S.near(Travel(60),2.2)
Slide();local walked=0
for i=1,8 do Tick(1/30,{axis=Vector3(1,0,0)});walked=walked+m.motion:Length() end
S.near(walked,2.12);assert(not m.clip,'walk input ends slide exactly at .26, dropping remaining .08m')
Slide();S.near(m:Facing().z,1);Tick(.04,{axis=Vector3(0,0,-1)})
assert(m.motion.x>0 and m.motion.z==0,'accepted movement cannot follow a later stick direction')
S.near(m:Facing().z,1)
m=New();assert(m:Action('dodge',Vector3(.05,0,.05)));S.near(m.moveDir.z,-1)
Slide();Tick(.49);assert(not m:Action('dodge'))
Tick(.01);assert(m:Action('dodge'),'cooldown .50 runs in real time')
m=New();m.o.slideStart=function() return false end
assert(not m:Action('dodge') and m.dodgeCool==0 and not m.iframe,'unsafe start consumes nothing')
Slide();m.o.slideMotion=function() return Vector3.ZERO,true end
Tick(.01);assert(m.slideStopped and m.iframe and m.dodgeCool>0)
Tick(.19);assert(not m.iframe,'clipped displacement retains original immunity expiry')

for _,entry in ipairs({{'sword_light_1',.18},{'sword_light_2',.18},{'sword_light_3',.30},{'sword_heavy_release',.48}}) do
 m=New();m.o.enemies=function() return {} end;m:Play(entry[1]);Tick(entry[2]-.001)
 assert(not m:Action('dodge'),'cannot cancel early '..entry[1])
 Tick(.001);assert(m:Action('dodge'),'cancel event must open '..entry[1])
end
Slide();Tick(.05);Tick(.01,{attackTap=true})
local travel=m.motion:Length()+.6 -- .05s initial movement
while m.clip=='dodge_slide' do Tick(1/30);travel=travel+m.motion:Length() end
assert(m.clip=='sword_light_1' and not m.iframe and m.buffer==nil,'same-frame single attack at .22')
S.near(travel,1.92)
local lunge=0
for i=1,30 do Tick(.02);lunge=lunge+m.motion:Length() end
assert(lunge<=.350001,'post-slide first attack lunge capped, no leftover slide impulse')
Slide();for i=1,20 do Tick(.02) end
assert(not m.clip and m.combo==0,'without a new edge slide never auto attacks')
m=New();m.combo=1;assert(m:Action('dodge'));Tick(.04);Tick(.01,{attackTap=true});Tick(.18)
assert(m.clip=='sword_light_2','slide preserves next combo stage')
m=New();m.combo=2;assert(m:Action('dodge'));Tick(.61);assert(m:Action('light'));assert(m.clip=='sword_light_1')
Slide();Tick(.04);assert(not m:ApplyHit{dmg=10}.hit);local reward=m.perfectUntil
Tick(.01);assert(not m:ApplyHit{dmg=10}.hit and m.perfectUntil==reward,'one precise reward per slide')
Tick(.18);assert(m:Action('light'));Tick(.11)
assert(m.strikePerfect and not m.perfectUntil,'next sword consumes poise-only reward')
Slide();Tick(.11);assert(not m:ApplyHit{dmg=10}.hit and not m.perfectUntil,'late iframe is not precise dodge')
Slide();Tick(.04);m:ApplyHit{dmg=10};Tick(.81);assert(m:Action('light'));Tick(.11)
assert(not m.strikePerfect,'precise reward expires .8 after intercept')
Bow();Tick(.1,{attack=true});Tick(.1,{attack=true});before=shots
Tick(.01,{dodge=true,attack=true});assert(m.clip=='dodge_slide' and m.charge==0)
for i=1,16 do Tick(.02,{attack=true}) end
assert(shots==before and not m.clip,'old held bow cannot charge or shoot after sliding')
Tick(.01);Tick(.01,{attack=true});assert(m.clip=='bow_draw' and m.charge<.1)
Bow();assert(m:Action('dodge'));Tick(.05);Tick(.01,{attackTap=true});Tick(.17)
assert(m.clip=='dodge_slide' and not m.buffer,'bow early tap is not latched')
Tick(.01,{attack=true});assert(m.clip=='bow_draw','new post-.22 press draws without waiting for .32')
print('PASS slide cancel matrix, same-frame latch, combo expiry, direction snapshot, CD, reward, no ghost bow, 30/60FPS')
Slide();local dust={};m.o.dust=function(count) dust[#dust+1]=count end
Tick(.04);local shotsOut=m:SlideAfterimages(Vector3.ZERO,{})
assert(#shotsOut==1 and shotsOut[1].life==.08)
Tick(.02);assert(#m:SlideAfterimages(Vector3.ZERO,{})==1,'no snapshot faster than .04')
Tick(.02);assert(#m:SlideAfterimages(Vector3.ZERO,{})==2)
Tick(.08);assert(not m.slideImages)
Tick(.08);assert(#m:SlideAfterimages(Vector3.ZERO,{})==0,'snapshots expire on real time')
Tick(.02);assert(dust[1]==3 and dust[2]==2 and #dust==2)
Slide();dust={};m.o.dust=function(count) dust[#dust+1]=count end
Tick(.04);m:Cancel('menu');assert(dust[1]==3 and dust[2]==2)
Tick(.3);assert(#dust==2,'interrupt emits exactly one brake, no stale extra dust event')
assert(State.GetSetting('dodgeFov')==false,'dodge FOV is opt-in')
print('PASS dust start/brake/interrupt once, <=2 snapshots/.04 cadence/.08 expiry, default FOV off')

-- §19: one immutable-in-consumption event and max-only group envelopes.
m=New()
local impacts,audio={},{}
m.o.feedback=function(e)
    impacts[#impacts+1]={id=e.swingId,material=e.material,weak=e.weak,part=e.part}
end
m.o.audio={Play=function(name,opts) audio[#audio+1]=name; return #audio end,Stop=function() audio[#audio+1]='stop' end}
local info={dmg=10,poise=6,pos=Vector3.ZERO,dir=Vector3.FORWARD,part='shell',material='armor',swingId='sword:99'}
m:Feedback(enemy,info,{hit=false},false,false);assert(#impacts==0 and #audio==0)
m:Feedback(enemy,info,{hit=true,damage=10,material='armor'},false,false)
local group=m.feedbackGroups['sword:99'];S.near(group.amp,.01);S.near(group.at,0)
m.age=.02; info.heavy=true
m:Feedback(enemy,info,{hit=true,damage=10,broke=true,partBroken='shell'},false,false)
assert(#impacts==2 and impacts[1].material=='armor' and audio[1]=='hit_armor')
S.near(group.at,0);S.near(group.amp,.03);S.near(group.duration,.12);S.near(m.hitstop,.08)
S.near(m:FovOffset(),2*(1-.02/.12))
m.age=.2;S.near(m:ShakeOffset():Length(),0);S.near(m:FovOffset(),0)
m=New();info.heavy=false;info.swingId='arrow:1';info.tier='mid'
m:Feedback(enemy,info,{hit=true},false,true)
S.near(m.feedbackGroups['arrow:1'].amp,0);S.near(m.hitstop,0)
info.swingId='arrow:2';info.full=true;info.tier='full'
m:Feedback(enemy,info,{hit=true},true,true)
S.near(m.feedbackGroups['arrow:2'].amp,.008);S.near(m.hitstop,.12)
State.SetSetting('cameraShake',false);S.near(m:ShakeOffset():Length(),0)
State.SetSetting('cameraShake',true)
for i=1,80 do m:Envelope('bounded:'..i,0,0,0,nil,0) end
local groups=0;for _ in pairs(m.feedbackGroups) do groups=groups+1 end;assert(groups<=32)
-- Bow's full cue has one animation edge, and cancellation stops its loop.
Bow();local sounds,stops={},0
m.o.audio={Play=function(name) sounds[name]=(sounds[name] or 0)+1;return 1 end,Stop=function() stops=stops+1 end}
Tick(.01,{attack=true});for i=1,80 do Tick(.02,{attack=true}) end
assert(sounds.bow_draw==1 and sounds.bow_full==1)
m:Cancel('touchcancel');assert(stops==1)
print('PASS unified hit event, material audio, group max/no restart, ordinary arrow no shake, full weak arrow, bounded groups, full once/cancel sound')
-- HUD histories use real hit time, not render count; bitmap scale never changes.
package.loaded['ui.PixelDraw']={colors={}}
local HUD=require('ui.CombatHUD')
local history={}
S.near(HUD.HealthTrail(history,100,0),100)
S.near(HUD.HealthTrail(history,90,.01),100)
S.near(HUD.HealthTrail(history,80,.10),100)
local half=HUD.HealthTrail(history,70,.255);assert(half<100 and half>70)
S.near(HUD.HealthTrail(history,60,.38),60)
S.near(HUD.HealthTrail(history,100,.39),100)
local hit={lastHitAt=1,age=1,lastHitWeak=true}
assert(HUD.HitPulse(hit)==10);hit.age=1.05;assert(HUD.HitPulse(hit)==8)
hit.age=1.17;assert(HUD.HitPulse(hit)==8);hit.age=1.19;assert(HUD.HitPulse(hit)==nil)
print('PASS HP .12 hold/.25 catchup without continuous-hit postponement; 2dp reticle contraction and .10 weak tail')

m=New()
local layers={}
m.o.audio={Play=function(name,opts) layers[#layers+1]={name=name,tier=opts.tier,material=opts.material,id=opts.hitId} end}
m:Feedback(enemy,{dmg=20,poise=12,heavy=true,kind='sword',pos=Vector3.ZERO,dir=Vector3.FORWARD,
 part='head',swingId='sword:critical',material='armor'},{hit=true,weak=true},true,false)
assert(layers[1].name=='hit_core' and layers[1].tier=='critical' and layers[1].material=='weakpoint')
assert(layers[2].name=='hit_heavy' and layers[2].tier=='heavy' and layers[1].id==layers[2].id)
print('PASS weak core +2dB tier, heavy extra layer shares same hitId and preserves event tier')
