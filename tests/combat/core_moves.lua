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
        fire=function(charge,stats,crystal) shots=shots+1; lastShot={charge=charge,crystal=crystal};return true end}
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
m=New();assert(m:ApplyHit{dmg=10,dir=Vector3.RIGHT}.hit)
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
assert(shots==before,'weak tap cancels immediately')
for i=1,5 do Tick(.02) end
assert(shots==before,'weak tap never queues a later shot')
Bow(); before=shots
Tick(.01,{heavy=true}); for i=1,10 do Tick(.02) end
m:Cancel('menu')
for i=1,50 do Tick(.02) end
assert(shots==before and not m.autoFire,'menu discards automatic shot')
m=New(); assert(m:Swap()); assert(m.clip=='weapon_swap_sword_to_bow')
Tick(.18); assert(not m:CanCancel(),'swap first .2 is not cancellable')
Tick(.03); assert(m:CanCancel(),'swap cancel follows animation event')
m=New(); assert(m:Swap()); Tick(.41)
assert(State.GetWeapon()=='bow' and State.TransitionRemaining()==0 and not m.clip,'weapon_ready completes swap')
-- Long press: the cross slash fires by itself at HEAVY_HOLD, no release and no charge levels.
m=New(); Tick(.01,{attack=true}); assert(m.clip=='sword_heavy_charge')
for i=1,17 do Tick(.02,{attack=true}) end
assert(m.clip=='sword_heavy_charge' and not m.fullCharged,'still winding up before HEAVY_HOLD')
for i=1,3 do Tick(.02,{attack=true}) end
assert(m.clip=='sword_heavy_release' and m.charge==0,'holding fires the cross slash without releasing')
S.near(m.stamina.value,m.stamina.max-25,1e-6)
Tick(.02); assert(m.clip=='sword_heavy_release','release after firing changes nothing')
m=New(); m:Play('getup'); Tick(.46)
assert(not m.clip and next(m.protection),'getup finishes pose at .45 but keeps real-time protection')
assert(m:Action('light'))
Tick(.10); assert(next(m.protection),'new action must not cancel independent getup tail')
Tick(.05); assert(not next(m.protection),'protection ends at .60 real seconds')
m=New();m.invuln=.8;m.hitstop=1;Tick(.30);S.near(m.invuln,.5)

-- F7 seek follows authored events without sending them through gameplay handlers.
local preview=A.New(S.anim.character(),nil)
local t,events=C.SeekPreview(preview,'sword_light_1',.20,4/30)
S.near(t,.20); assert(C.PreviewPhase('sword_light_1',t)=='active' and events:find('hit_on',1,true))
t,events=C.SeekPreview(preview,'sword_light_1',.10,.18)
assert(C.PreviewPhase('sword_light_1',t)=='anticipation' and not events:find('hit_on',1,true))
t,events=C.SeekPreview(preview,'sword_heavy_release',11/30,.33) -- second cut's hit_on
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
local previewBranch=assert(sceneSource:match('(        if step~=0 or changed then.-)\n        animPreview_.text='))
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
pe.combatAllowed=true;pe.animPreview_.t=1.14
frame();S.near(pe.animPreview_.t,0);S.near(pausedAnim.tracks[1].t,0)
print('PASS actual Scene F7 pause/focus frames suppress Apply fallback; loop display clock matches pose')

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
S.near(m.feedbackGroups['arrow:2'].amp,0);S.near(m.hitstop,0)
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

-- A cold Play is intentionally silent; never retry it as the resource warms.
for _,cancel in ipairs({true,false}) do
    Bow(); local calls,stopped,beforeShots={},0,shots
    m.o.audio={Play=function(name) calls[name]=(calls[name] or 0)+1; return nil end,
        Stop=function() stopped=stopped+1; error('nil handle must not reach Stop') end}
    Tick(.01,{attack=true})
    for _=1,80 do Tick(.02,{attack=true}) end
    assert(m.drawSound==nil and calls.bow_draw==1 and calls.bow_full==1,'cold cues are not replayed')
    if cancel then m:Cancel('touchcancel') else Tick(.01,{attack=false}) end
    for _=1,30 do Tick(.02) end
    assert(stopped==0 and shots==beforeShots+(cancel and 0 or 1),'cold sound never changes cancel/fire behavior')
end
print('PASS cold nil bow handle: no retry, safe cancellation, release still fires once')

-- R8 profiles are selected without upgrading weak/kill stop, and borrowed
-- slots overwrite false/nil fields after a strong impact wraps the ring.
do
    m=New()
    local captured,consumed=0,0
    local target={hitStop=0,OnHitEvent=function(_,e)
        assert(e.resolved and e.combo~=nil and type(e.full)=='boolean')
        consumed=consumed+1;return true
    end}
    local input={dmg=10,poise=6,pos=Vector3.ZERO,dir=Vector3.FORWARD,combo=1,deferPresentation=true}
    local result={hit=true,resolved=true}
    local expectedId,expectedStop,expectedFlash
    m.o.feedback=function(e)
        captured=captured+1
        assert(e.profileId==expectedId and e.presentationConsumed and not e.player)
        S.near(e.stop,expectedStop);S.near(e.attackerStop,expectedStop);S.near(e.flash,expectedFlash)
        S.near(e.impactDir:Length(),1)
    end
    local cases={{1,false,false,false,false,'light_1',.04,.06},
        {2,false,false,false,false,'light_2',.04,.06},{3,false,false,false,false,'third',.04,.08},
        {0,true,false,false,false,'heavy',.08,.08},{0,true,true,false,false,'full',.08,.10},
        {1,false,false,true,false,'critical',.04,.09},{1,false,false,false,true,'kill',.04,.10}}
    for i,c in ipairs(cases) do
        input.combo,input.heavy,input.full,input.swingId=c[1],c[2],c[3],i
        result.weak,result.killed=c[4],c[5]
        expectedId,expectedStop,expectedFlash=c[6],c[7],c[8]
        m:Feedback(target,input,result,false,false)
    end
    result.broke=true;expectedId,expectedStop,expectedFlash='break',.10,.10
    m:Feedback(target,input,result,false,false)
    result.broke,result.killed,result.weak=false,false,false
    input.combo,input.heavy,input.full=1,false,false
    expectedId,expectedStop,expectedFlash='light_1',.04,.06
    for i=1,16 do
        input.swingId=i+100;m:Feedback(target,input,result,false,false)
        local e=m.eventPool[m.eventWrite]
        assert(not e.full and not e.critical and not e.weak and not e.killed and not e.broke and not e.staggered and e.part==nil)
    end
    assert(captured==consumed and #m.eventPool==8 and #m.feedbackPool==32)
    local pool={}
    for _,g in ipairs(m.feedbackPool) do pool[g]=true end
    for i=1,200 do m:Envelope(i,1,.12,0,Vector3.FORWARD,.04) end
    for _,g in pairs(m.feedbackGroups) do assert(pool[g]) end
    S.near(m:ShakeOffset():Length(),0)
    m.age=m.age+.02
    local punch=m:ShakeOffset(Vector3.RIGHT,Vector3.UP)
    assert(punch:Length()<=.030001 and punch:Length()>0 and punch.z==0,'local-time screen-plane punch, including forward-direction fallback')
    m.age=m.age+1;S.near(m:ShakeOffset():Length(),0)
end
do
    m=New();local arcCalls=0
    rig.ShowContactArc=function(_,zone)arcCalls=arcCalls+1;S.near(zone.radius,1.8);assert(zone.angle==120)end
    m:Play('sword_light_1');m.anim:Update(.28);m:Events()
    assert(m.hitPending and not m.hitOpen,'hitch crosses on/off')
    local before=count;m:AfterPose();m:AfterPose()
    assert(arcCalls==1 and count==before+1,'one visible arc and one hit, unchanged broadphase/reach/dedupe')
    rig.ShowContactArc=nil
    m=New();local full=0
    m.o.audio={Play=function(cue)if cue=='sword_full' then full=full+1 end end}
    m:Play('sword_heavy_charge');m.anim:Update(1.1);m:Events();m:Events()
    m.anim:Update(.5);m:Events()
    assert(full==0 and not m.fullCharged,'long-press windup has no charge levels or full cue')
end
print('PASS R8 profiles 40/40/80/100ms, complete pooled event overwrite/consumer, bounded groups, local punch, low-FPS visible contact fallback, no sword charge levels')
do
    local owner=C.New{state={GetSetting=function()return false end},rig={},anim={}}
    local target={hitStop=0}
    local input={dmg=10,poise=6,pos=Vector3.ZERO,dir=Vector3.FORWARD,combo=1,swingId=1}
    local result={hit=true,resolved=true}
    for i=1,100 do input.swingId=i;owner:Feedback(target,input,result,false,false) end
    collectgarbage('collect');collectgarbage('stop')
    local before=collectgarbage('count')
    for i=101,1100 do input.swingId=i;owner:Feedback(target,input,result,false,false);owner:ShakeOffset() end
    local bytes=(collectgarbage('count')-before)*1024/1000
    collectgarbage('restart')
    assert(bytes<=256,'new feedback layer mock allocation budget, excluding existing Apply/audio/native bindings')
    print(string.format('R8 Feedback+Shake mock gross allocation %.2f B/iteration; 8 events/32 groups fixed. Excludes existing info/result snapshots, audio handles and native userdata.',bytes))
end
do
    local vector,quaternion=Vector3,Quaternion
    local EnemySupport=dofile('tests/combat/enemy_support.lua')
    Vector3,Quaternion=vector,quaternion
    local terrain,port=EnemySupport.Fixture()
    local beetle=require('combat.enemies.MossBeetle').New(nil,nil,terrain,port,Vector3.ZERO,'r8_contract')
    local owner=C.New{state={GetSetting=function()return false end},rig={},anim={}}
    local input={dmg=1,poise=0,part='shell',kind='sword',swingId=21,deferPresentation=true,combo=1,
        pos=Vector3(-.6,.3,0),dir=Vector3.FORWARD,normal=Vector3.LEFT or Vector3(-1,0,0)}
    local result=H.Apply(beetle,input)
    assert(result.resolved and beetle.presentedHits==0)
    owner:Feedback(beetle,input,result,result.weak,false)
    assert(beetle.presentedHits==1 and beetle.particles:CountOwner(beetle)==6)
    assert(owner.eventPool[owner.eventWrite].presentationConsumed and not beetle:OnHitEvent(owner.eventPool[owner.eventWrite]))
    input.dmg,input.swingId=10000,22
    result=H.Apply(beetle,input);assert(result.killed)
    owner:Feedback(beetle,input,result,result.weak,false)
    assert(beetle.deathPresentationReady and beetle.particles:CountOwner(beetle)==1,'kill still presents immediate shared white kernel once')
    assert(beetle.deathImpact.profileId=='kill' and beetle.deathImpact.flash==.10)
    beetle:Destroy()
end
print('PASS R8 actual Hit.Apply -> Moves.Feedback -> EnemyBase.OnHitEvent, one kernel on kill, copied profile contract and no double presentation')

-- Five independent clips/zones/profiles, any stage branches to heavy at its gate.
do
 local D=require('combat.AnimClips')
 assert(C.COMBO_LENGTH==5 and #D.Combo==5)
 for stage,row in ipairs(D.Combo) do
  m=New();m.combo=stage-1;assert(m:Action('light'));assert(m.clip==row.id)
  local clip=D.Clips[row.id]
  local damage,counted,event=0,0,nil
  local target={active=true,GetHurtShapes=function()return {{id='body',center=Vector3(0,1,1),radius=.3}}end,
   ApplyHit=function(_,info)damage=info.dmg;counted=counted+1;return {hit=true}end}
  m.o.enemies=function()return {target}end
  m.o.feedback=function(e)event={profile=e.profileId,stop=e.stop,poise=e.poise}end
  Tick(clip.phases.active[1]+.01);m:AfterPose();m:AfterPose()
  assert(counted==1 and event.profile==row.profile);S.near(damage,10*row.damage)
  S.near(event.poise,6*row.poise);S.near(event.stop,stage==5 and .09 or (stage==4 and .06 or .04))
  local zone=C.MeleeZone(row.id,Vector3.ZERO,Vector3.FORWARD,1,false)
  S.near(zone.radius,row.radius);S.near(zone.angle,row.angle)
  for _=1,100 do Tick(.01) end
  assert(counted==1,'one settlement per target for the entire swing')
  m=New();m.combo=stage-1;assert(m:Action('light'))
  for _=1,100 do
   Tick(.01)
   if (m.cancelOpen or not m.clip) and m.age>=(m.comboCooldownUntil or 0) then break end
  end
  assert(m:Action('heavy') and m.clip=='sword_heavy_release')
 end
 m=New();m.combo=4;assert(m:Action('light'));Tick(.47)
 local untilTime=m.comboCooldownUntil;assert(untilTime and not m:Action('light'))
 for _=1,33 do Tick(.01);assert(not m:Action('light')) end
 while m.age<untilTime+1e-6 or m.clip do Tick(.01) end
 assert(m:Action('light') and m.combo==1)
 m=New();m.combo=2;m.comboUntil=0;Tick(.8);assert(m:Action('light') and m.combo==1)
end
print('PASS five-stage data, exact damage/poise/stop/zones/dedupe, heavy branches, finisher .35s lock, timeout reset')
-- Removed aerial landing attack: ordinary input, no fall control or landing damage.
do
 assert(C.PLUNGE==nil and C.PlungeDistance==nil and C.StartPlunge==nil and C.UpdatePlunge==nil)
 for _,height in ipairs({0,.59,.6,4,20}) do
  local air={onGround=false,height=height,y=height,vx=2,vz=1}
  m=New();m.o.airState=function()error('ordinary attacks must not request fall control')end
  m.o.position=function()return Vector3(0,air.y,0)end
  local calls,rings,lands,fx,impactSounds=0,0,0,0,0
  local target={active=true,GetHurtShapes=function()return {{id='body',center=Vector3(0,air.y+.5,-2),radius=.25}}end,
   ApplyHit=function()calls=calls+1;return {hit=true}end}
  m.o.enemies=function()return {target}end
  m.o.impactRing=function()rings=rings+1 end
  m.o.camera={Land=function()lands=lands+1 end,Cancel=function()end}
  m.o.feedback=function()fx=fx+1 end
  m.o.audio={Play=function(cue)if cue=='hit_heavy' or cue=='arrow_hit' then impactSounds=impactSounds+1 end end}
  Tick(.01,{attackTap=true,onGround=false})
  assert(m.clip=='sword_light_1' and m.plunging==nil and m.plungeVelocity==nil)
  local handle,serial=m.handle,m.swingSerial
  Tick(.05,{onGround=false});air.onGround,air.y=true,0;Tick(.01,{onGround=true})
  assert(m.handle==handle and m.swingSerial==serial,'landing cannot replace/requeue the ordinary attack')
  for _=1,100 do Tick(.02,{onGround=true}) end
  assert(not m.clip and m.buffer==nil and m:MoveScale()==1 and m:CanCancel(),'no landing lock or buffered follow-up')
  assert(calls==0 and rings==0 and lands==0 and fx==0 and impactSounds==0,'landing emits no radial hit or landing combat feedback')
  S.near(m.stamina.value,m.stamina.max)
 end
 for _,reason in ipairs({'hit','void','rewind','mount','menu'}) do
  m=New();Tick(.01,{attackTap=true,onGround=false});m:Cancel(reason)
  for _=1,80 do Tick(.02,{onGround=true}) end
  assert(not m.clip and not m.hitPending and m.buffer==nil and m:MoveScale()==1,'interrupted air input cannot resume on landing')
 end
 -- Stale/unknown authored hit events cannot reopen a damage window, even if
 -- their old handle is accidentally retained by a caller during cancellation.
 for _,id in ipairs({'plunge_start','plunge_loop','plunge_land','sword_light_6','unknown'}) do
  m=New();m.clip,m.handle=id,900
  m.anim.Poll=function()return {{name='hit_on',clip=id,handle=900}}end
  m:Events();assert(not m.hitOpen and not m.hitPending and m:StrikeZones()==nil)
  m.hitOpen,m.hitPending,m.hitClip=true,true,id
  local before=count;m:AfterPose();assert(count==before,'stale landing clip never settles damage')
 end
 m=New();Tick(.01,{attackTap=true,onGround=false})
 assert(m:ApplyHit{dmg=5,dir=Vector3.RIGHT}.hit and m.clip=='hit_light','ordinary air attack remains vulnerable')
 Tick(.01,{onGround=true});assert(m.clip=='hit_light','landing cannot replace the hit reaction')
end
print('PASS removed landing attack: heights/input, no forced velocity/cost/radial hit/feedback/lock, interrupts and stale events')

Bow();m.o.airState=function(out)out.onGround,out.height,out.y=false,2,2;return out end
assert(m:Action('hold') and m.clip=='bow_draw','airborne bow input keeps its existing draw rule')
