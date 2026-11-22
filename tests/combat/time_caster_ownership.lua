-- The caster must enforce weapon ownership even if an input caller bypasses Scene.
local S=dofile('tests/combat/core_support.lua')
local State=require('combat.CombatState')
local function Read(path)
    local f=assert(io.open(path));local s=f:read('*a');f:close();return s
end
local nl=string.char(10)
local body=assert(Read('scripts/ruins/TimeSpells.lua'):match('(function M.NewCaster.-)'..nl..'%-%-'))
local spells={BY_ID={},CHARGE_SECONDS=1.4,ShatterRadius=function()return 1 end}
local effects={casts=0,beams=0,pulses=0,poses=0}
for _,id in ipairs({'shatter','freeze','rewind'})do
    spells.BY_ID[id]={cooldown=.1,color={},cast=function()effects.casts=effects.casts+1;return true end}
end
local casterEnv=setmetatable({M=spells,C={}}, {__index=_G})
casterEnv.C.__index=casterEnv.C
assert(load(body,'actual TimeCaster methods','t',casterEnv))()
local scene=Read('scripts/ruins/RuinsScene.lua')
local policy=assert(scene:match('canCast=(function%(id%).-end),'),'Scene must wire caster ownership')
local canCast=assert(load('return '..policy,'Scene caster permission','t',{CombatState=State}))()
local ctx={canCast=canCast,
    fx={Beam=function()effects.beams=effects.beams+1 end},
    sigils={Pulse=function()effects.pulses=effects.pulses+1 end},
    prepareCast=function()effects.poses=effects.poses+1 end,handPos=function()return Vector3.ZERO end}
local aim={hit=true,pos=Vector3.FORWARD,normal=Vector3.UP}
State.Configure{explicitSelection=true,log=function()end}
assert(State.Enter('loadout'));State.FinishTransition()
for _,weapon in ipairs({'sword','bow'})do
    State.SetBusy(false);State.FinishTransition();assert(State.SetWeapon(weapon));State.FinishTransition()
    local c=spells.NewCaster(ctx)
    for _=1,180 do c:HandleCharge(true,aim,true);c:Update(1/60)end
    assert(not c.charging and c.charge==0,weapon..' cannot start shatter through a stale input caller')
    c:HandleCharge(false,aim,true)
    assert(not c:Cast('shatter',aim),weapon..' cannot bypass ownership through direct Cast')
    assert(c.castSerial==0 and c.lastCast==nil and c.castAnim==0 and c.cool.shatter==nil)
    assert(effects.casts==0 and effects.beams==0 and effects.pulses==0 and effects.poses==0,
        'rejected shatter must not produce damage, animation, beam, clock or cooldown')
end
local c=spells.NewCaster(ctx)
for _,id in ipairs({'freeze','rewind'})do assert(c:Cast(id,aim),id..' remains portable')end
local before=effects.casts
State.Exit('loadout');c=spells.NewCaster(ctx)
c:HandleCharge(true,aim,true);c:Update(1.4)
assert(c.charging and c.charge==1,'time selection can fully charge')
c:HandleCharge(false,aim,true)
assert(effects.casts==before+1 and c.lastCast=='shatter' and not c.charging)
c=spells.NewCaster(ctx);c:HandleCharge(true,aim,true);c:Update(.5)
assert(c.charging)
assert(State.Enter('loadout'));State.FinishTransition();c:Update(.1)
assert(not c.charging and c.charge==0,'ownership loss cancels a live charge before release')
before=effects.casts;c:HandleCharge(false,aim,true)
assert(effects.casts==before,'switching to sword discards the held cast')
State.SetMounted(true);assert(not c:Cast('freeze',aim))
State.SetMounted(false);State.SetDead(true);assert(not c:Cast('rewind',aim))
-- Legacy standalone callers without an equipment policy remain supported.
local standalone=spells.NewCaster{fx=ctx.fx,handPos=ctx.handPos}
standalone:HandleCharge(true,aim,true);assert(standalone.charging)
print('PASS caster ownership: sword/bow 3s hold and direct Cast rejected without effects; E/R, time charge and interruptions preserved')

-- Continuous held mouse through real Scene routing, sword moves and State.
local Moves=require('combat.CombatMoves')
local Anim=require('combat.CombatAnim')
local rig={SetActive=function()end,SetPose=function()end,
    GetStats=function()return {attack=10,speed=1,reach=1,poise=6,draw=.7}end,
    GetHit=function()return {origin=Vector3.ZERO,dir=Vector3.FORWARD,length=1,radius=.12}end}
State.Configure{rig=rig,explicitSelection=true,log=function()end}
assert(State.Enter('loadout'));State.FinishTransition();State.Activity(true)
local moves=Moves.New{anim=Anim.New(S.anim.character(),nil),state=State,rig=rig,
    position=function()return Vector3.ZERO end,forward=function()return Vector3.FORWARD end,
    enemies=function()return {}end}
local heavy=false
moves.observe=function(kind,e)if kind=='start' and e.clip=='sword_heavy_release'then heavy=true end end
c=spells.NewCaster(ctx)
local env=setmetatable({M={},caster_=c,CombatState=State,animPreview_={index=0},
    time_=10,KEY_E='e',KEY_R='r',KEY_Q='q',MOUSEB_LEFT=1,
    Press=function()return false end,input={focus=true,GetMouseButtonDown=function()return true end},
    pointer={CanAttack=function()return true end,IsEnabled=function()return true end},
    WeaponWheel={IsBlocked=function()return false end},ForgePanel={IsOpen=function()return false end},
    SettingsMenu={IsBlocked=function()return false end},TouchControls={IsBlocked=function()return false end},
    TouchInput={IsEnabled=function()return false end,Down=function()return false end,Press=function()return false end}},
    {__index=_G})
local inputBody=assert(scene:match('(local function HandleSpells.-)'..nl..'function Ruins_HandleSceneUpdate'))
local input=assert(load(inputBody..nl..'return HandleSpells','actual Scene held mouse','t',env))()
before=effects.casts
for _=1,180 do
    moves:Update(1/60,{allowed=true,attack=true,onGround=true})
    State.Update(1/60);input(1/60,aim);c:Update(1/60);moves:AfterPose()
    assert(State.GetSelection()=='sword' and not c.charging and c.castAnim==0)
end
assert(heavy and effects.casts==before,'3s held mouse fires sword cross slash without any time spell')
print('PASS actual Scene + Moves + Caster: continuous 3s left hold stays sword and fires cross slash, zero time casts')
