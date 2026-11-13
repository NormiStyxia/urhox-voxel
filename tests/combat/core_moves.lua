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
    return C.New{anim=A.New(S.anim.character(),{}),state=State,rig=rig,
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
