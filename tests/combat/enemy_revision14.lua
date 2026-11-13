package.path='scripts/?.lua;tests/?.lua;'..package.path
local T=require('combat.enemy_support')
local Base=require('combat.enemies.EnemyBase')
local Beast=require('combat.enemies.StoneBeast')
local Beetle=require('combat.enemies.MossBeetle')
local Sentry=require('combat.enemies.StoneSentry')
local terrain,combat=T.Fixture()
local boss=Beast.New(nil,nil,terrain,combat,Vector3.ZERO,'revision')
combat.pos=Vector3(0,0,5)
assert(boss.parts.foreleg_l.armor==40 and boss.parts.foreleg_r.armor==40 and boss.parts.back_armor.armor==70)
boss:ApplyHit({dmg=2,poise=40,part='foreleg_l'})
T.Near(boss.hp,598); T.Near(boss.parts.foreleg_l.armor,38); T.Near(boss.poise,40)
boss.hitStop=10 -- timers keep advancing while only animation is frozen
T.Tick(boss,3,combat.pos); T.Near(boss.poise,40)
T.Tick(boss,.5,combat.pos); T.Near(boss.poise,35)
boss:ApplyHit({dmg=1,poise=0,part='foreleg_l'}); boss.hitStop=10
T.Tick(boss,.5,combat.pos); T.Near(boss.poise,30)
boss:ApplyHit({dmg=1,poise=1,part='foreleg_l'}); boss.hitStop=10
T.Tick(boss,2.99,combat.pos); T.Near(boss.poise,31)
print('PASS independent HP/armor/poise; 3s delay then 10/s; HP-only hits do not delay recovery')

boss:Reset(); boss:ApplyHit({dmg=1,poise=100,part='head'})
assert(boss.down and boss.staggerDuration==3)
for _=1,10 do boss:ApplyHit({dmg=.01,poise=100,part='head'}) end
T.Near(boss.poise,0)
boss.hitStop=0; T.Tick(boss,3.01,combat.pos)
assert(not boss.down and boss.poiseProtection>1.48 and boss.poise==0)
boss:ApplyHit({dmg=.01,poise=100,part='head'}); assert(not boss.down and boss.poise==0)
boss.hitStop=5; T.Tick(boss,1.5,combat.pos)
boss:ApplyHit({dmg=.01,poise=100,part='head'}); assert(boss.down)
print('PASS no poise stacking while down, stand clears poise, 1.5s real-time immunity')

boss:Reset(); boss:ApplyHit({dmg=40,poise=30,part='foreleg_l'}); boss.hitStop=0
assert(boss.pendingTrip and boss.state~=Base.State.STAGGER and not boss.down)
boss:SelectAttack(); boss:SetState(Base.State.TELEGRAPH)
T.Tick(boss,.6,combat.pos); assert(boss.state==Base.State.ATTACK)
T.Tick(boss,.59,combat.pos); assert(boss.state==Base.State.ATTACK and not boss.down)
T.Tick(boss,.01,combat.pos); T.Near(boss.attackTravel,9)
assert(boss.state==Base.State.STAGGER and boss.staggerDuration==1 and not boss.down and not boss.pendingTrip)
T.Near(boss.poise,30) -- armor-triggered stumble does not erase whole-body poise
T.Tick(boss,.99,combat.pos); assert(boss.state==Base.State.STAGGER)
T.Tick(boss,.02,combat.pos); assert(boss.state==Base.State.RECOVER)
T.Near(boss.poise,30); T.Near(boss.poiseProtection,0)
boss.attack=Beast.Config.attacks[1]; boss:SetState(Base.State.TELEGRAPH)
T.Tick(boss,1.2,combat.pos); assert(boss.state==Base.State.RECOVER,'leg break grants only one extra stumble')
boss:Reset(); boss:ApplyHit({dmg=70,part='back_armor'})
assert(boss.hp==530 and boss.parts.back_armor.broken and boss:GetHurtShapes()[5].enabled)
boss:Reset(); boss:ApplyHit({dmg=301,part='head'})
assert(boss.phase==2 and not boss.parts.back_armor.broken and not boss:GetHurtShapes()[5].enabled)
assert(boss.fastStomp.telegraph>=Beast.Config.attacks[3].telegraph*.85)
assert(boss.secondCharge.telegraph>=.45 and boss.secondCharge.telegraph>=.6*.85)
print('PASS leg break schedules next charge-end 1s stumble once; early back break; phase never substitutes armor break')

boss:Reset(); boss.obstacles={{x=0,z=2,radius=.5}}
boss:SelectAttack(); boss:SetState(Base.State.TELEGRAPH); T.Tick(boss,.65,combat.pos)
assert(boss.state==Base.State.STAGGER and boss.chargeStunned)
local time=boss.stateTime
boss:AttackStep(.1,combat.pos); assert(boss.stateTime==time and boss.staggerDuration==2.5)
assert(not boss:Stagger(2.5,true),'repeated impact cannot restart current stun')
boss.obstacles={}; boss:Reset()
local origin=boss.position
boss:ApplyHit({dmg=1,poise=1,part='foreleg_l',kind='sword',dir=Vector3(1,0,0)})
T.Near(boss.position.x,origin.x); T.Near(boss.position.z,origin.z)
boss:ApplyHit({dmg=1,poise=100,part='foreleg_l',kind='sword',dir=Vector3(1,0,0)})
T.Near(boss.position.x-origin.x,.6)
print('PASS one pillar stun per charge; ordinary Boss hits zero knockback, poise break moves safely')

local group={count=0,limit=2}
local pack={}
for i=1,4 do
    pack[i]=Beetle.New(nil,nil,terrain,combat,Vector3.ZERO,'pack_'..i)
    pack[i].attackGroup=group
end
assert(pack[1]:StartAttack() and pack[2]:StartAttack())
assert(not pack[3]:StartAttack() and not pack[4]:StartAttack() and group.count==2)
pack[1]:SetState(Base.State.ATTACK); assert(not pack[3]:StartAttack())
pack[1]:SetState(Base.State.RECOVER); assert(pack[3]:StartAttack() and group.count==2)
pack[2]:Stagger(.8,false); assert(pack[4]:StartAttack() and group.count==2)
pack[3]:ApplyHit({dmg=1000}); assert(group.count==1)
pack[4]:SetActive(false); assert(group.count==0)
for _,enemy in ipairs(pack) do enemy:Destroy() end
assert(group.count==0)
print('PASS four melee actors share two tokens; recovery/stagger/death/deactivation release without leaks')

local b=Beetle.New(nil,nil,terrain,combat,Vector3.ZERO,'lock')
b:SetState(Base.State.TELEGRAPH)
T.Tick(b,.2,Vector3(2,0,0)); T.Near(b.fx,1)
T.Tick(b,.22,Vector3(0,0,2)); assert(b.directionLocked); T.Near(b.fz,1)
T.Tick(b,.18,Vector3(2,0,0)); assert(b.state==Base.State.ATTACK); T.Near(b.fx,0)
T.Tick(b,.1,Vector3(-2,0,0)); T.Near(b.fx,0)
local s=Sentry.New(nil,nil,terrain,combat,Vector3.ZERO,'stone_lock')
s:SetState(Base.State.TELEGRAPH); T.Tick(s,.72,Vector3(0,0,8))
T.Tick(s,.18,Vector3(8,0,0)); local stone=s.stones[1]
assert(stone.active and math.abs(stone.vx)<1e-6)
local vx,vy,vz=stone.vx,stone.vy,stone.vz
s:TickExtras(.2,Vector3(-8,0,0)); T.Near(stone.vx,vx); T.Near(stone.vy,vy); T.Near(stone.vz,vz)
T.Near(math.sqrt(vx*vx+vy*vy+vz*vz),12)
print('PASS last 0.18s locks aim, active attacks never turn, emitted stone velocities never home')

for _,fps in ipairs({30,60}) do
    local e=Beetle.New(nil,nil,terrain,combat,Vector3.ZERO,'timing')
    e:SetState(Base.State.TELEGRAPH)
    assert(e.warning.visible and e.poseY<0 and e.cue.phase=='inhale')
    local sequence=e.cue.sequence
    local elapsed=0
    while e.state==Base.State.TELEGRAPH do e:Update(1/fps,Vector3(0,0,2)); elapsed=elapsed+1/fps end
    assert(elapsed>=.6-1e-8 and elapsed<=.6+1/fps+1e-8)
    assert(e.cue.phase=='whoosh' and e.cue.sequence==sequence+2 and not e.warning.visible)
    elapsed=0
    while e.state==Base.State.ATTACK do e:Update(1/fps,Vector3(0,0,2)); elapsed=elapsed+1/fps end
    assert(elapsed>=.2-1e-8 and elapsed<=.2+1/fps+1e-8)
    T.Near(e.attackTravel,1.8)
end
print('PASS 30/60fps timing; inhale/whoosh cues synchronize with body pose and ground warning')
for _,fps in ipairs({30,60}) do
    local e=Beetle.New(nil,nil,terrain,combat,Vector3.ZERO,'hitstop_clock')
    e:SetState(Base.State.TELEGRAPH); e.hitStop=.04
    for _=1,fps/2 do e:Update(1/fps,Vector3(0,0,2)) end
    T.Near(e.stateTime,.46)
end
print('PASS hit-stop consumes exact partial-frame time at 30/60fps')
