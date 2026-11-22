package.path='scripts/?.lua;tests/?.lua;'..package.path
local T=require('combat.enemy_support')
local Base=require('combat.enemies.EnemyBase')
local Beetle=require('combat.enemies.MossBeetle')
local Beast=require('combat.enemies.StoneBeast')
local Sentry=require('combat.enemies.StoneSentry')
local Flash=require('combat.enemies.EnemyHitMaterial')
local terrain,combat=T.Fixture()
local function make(class,t)
    local _,c=T.Fixture()
    return class.New(nil,nil,t or terrain,c,Vector3.ZERO,'r8')
end
for _,heavy in ipairs({false,true}) do
    local duration,peak=heavy and .08 or .06,heavy and 1 or .85
    T.Near(Flash.Value(0,duration,peak),peak)
    T.Near(Flash.Value(1/60,duration,peak),peak)
    T.Near(Flash.Value((duration+1/60)/2,duration,peak),peak*.25)
    T.Near(Flash.Value(duration,duration,peak),0)
end
for _,fps in ipairs({30,60,120}) do
    for _,heavy in ipairs({false,true}) do
        local b=make(Beetle)
        b.aggro=true; b:SetState('CHASE')
        b:ApplyHit({dmg=.01,part='shell',heavy=heavy,kind='sword',dir=Vector3(1,0,0)})
        local stop=heavy and .08 or .04
        T.Near(b.hitStop,stop); T.Near(b.position.x,0)
        local pose=b.poseAge
        b:Update(stop,Vector3(0,0,5))
        T.Near(b.poseAge,pose); T.Near(b.reaction.recoilAge,0)
        T.Near(b.reaction.flashAge,stop); T.Near(b.position.x,0)
        local elapsed=0
        while elapsed<.12-1e-9 do
            local dt=math.min(1/fps,.12-elapsed)
            b:Update(dt,Vector3(0,0,5)); elapsed=elapsed+dt
        end
        T.Near(b.reaction.recoilAge,.12); T.Near(b.knock.travel,.1)
        b:Destroy()
    end
end
local b=make(Beetle)
b:SetState('TELEGRAPH'); b.hitStop=.04
b:Update(.05,combat.pos)
T.Near(b.stateTime,.01); T.Near(b.poseAge,.01); T.Near(b.age,.05)
print('PASS exact stop split, 30/60/120fps pose freeze, real flash clock, full 120ms recoil after stop')

for _,case in ipairs({{.1,.09},{.1,.12},{.55,.15}}) do
    b=make(Beetle); b:Knockback({dir=Vector3(1,0,0),heavy=case[2]==.12},case[1])
    local record=b.knock
    T.Near(b.position.x,0)
    b:TickKnock(case[2]/2); T.Near(b.position.x,case[1]*.875)
    b:TickKnock(case[2]/2); T.Near(b.position.x,case[1])
    assert(not b.knock.active and record==b.knock)
end
local boss=make(Beast)
boss:ApplyHit({dmg=1,part='foreleg_l',kind='sword',dir=Vector3(1,0,0)})
assert(not boss.knock.active)
boss:ApplyHit({dmg=1,poise=100,part='foreleg_l',kind='sword',dir=Vector3(1,0,0)})
T.Near(boss.position.x,0); assert(boss.knock.active)
T.Tick(boss,.24,combat.pos); T.Near(boss.knock.travel,.6)
b=make(Beetle); b.position=Vector3(47.4,0,0)
b:Knockback({dir=Vector3(1,0,0)},.55); b:TickKnock(.15)
assert(b.knock.blocked and not b.knock.active and b.position.x<47.6)
b=make(Beetle); b.obstacles={{x=1,z=0,radius=.2}}
b:Knockback({dir=Vector3(1,0,0)},.55); b:TickKnock(.15)
assert(b.knock.blocked and b.blockReason=='pillar' and b.position.x<=.3)
b=make(Beetle); b.world={RaycastSingle=function() return {hit=true} end}
b:Knockback({dir=Vector3(1,0,0)},.55); b:TickKnock(.15)
assert(b.knock.blocked and b.blockReason=='wall' and b.position.x==0)
print('PASS cubic incremental knock .1/.1/.55, Boss zero/.6, fixed record and terrain/wall/pillar truncation')

for _,heavy in ipairs({false,true}) do
    b=make(Beetle); local dies=0
    b.onEvent=function(name) if name=='die' then dies=dies+1 end end
    b:ApplyHit({dmg=1000,part='shell',heavy=heavy,pos=Vector3(1,1,1),dir=Vector3(1,0,0),normal=Vector3(0,1,0)})
    assert(b.particles.count==1 and b.particles.slots[1].material=='flash')
    T.Near(b.particles.slots[1].y,1.02)
    local stop=b.hitStop; b:Update(stop,combat.pos)
    T.Near(b.deathTime,0); assert(dies==0)
    T.Tick(b,.24,combat.pos); assert(not b.deathBurst)
    T.Tick(b,.01,combat.pos); assert(b.deathBurst and dies==1 and b.particles.count==12)
    T.Tick(b,.85,combat.pos); assert(b.deathFinished and b.particles.count==0 and dies==1)
end
b=make(Beetle); b:ApplyHit({dmg=1000})
for _=1,13 do b.hitStop=10; b:Update(.1,combat.pos) end
assert(b.deathFinished and b.deathRealTime<1.31,'external stop cannot extend cleanup past 1.22s + tick')
print('PASS killed immediate kernel, death pose respects stop, single .25 burst, real-time cleanup deadline')

local s=make(Sentry); s:BeginAttack(); local stone=s.stones[1]
local z=stone.z; s.hitStop=.08; s:Update(.04,Vector3(0,0,30))
assert(stone.z~=z and s.poseAge==0,'launched projectile keeps real-time motion')
boss=make(Beast); boss:ApplyHit({dmg=301,part='foreleg_l'})
boss:Update(.1,combat.pos); local rage=boss.rageTime
boss:ApplyHit({dmg=.1,part='foreleg_r',heavy=true}); boss:Update(.08,combat.pos)
T.Near(boss.rageTime,rage+.08); T.Near(boss.reaction.recoilAge,0)
print('PASS projectile realDt and rage exception do not restart or freeze on ordinary hit')

b=make(Beetle); local pool=b.particles
local fx={pos=Vector3.ZERO,dir=Vector3.FORWARD,normal=Vector3.UP,material='soft',tier='light'}
for _,item in ipairs({{'soft','light',6},{'armor','light',8},{'armor','heavy',11}}) do
    pool:ClearOwner(b); fx.material,fx.tier=item[1],item[2]
    assert(pool:Emit(b,fx)==item[3])
    assert(pool.slots[1].material=='flash' and pool.slots[1].priority==1)
    T.Near(pool.slots[1].ttl,.06)
end
pool:ClearOwner(b)
fx.kind='phase'; fx.material='armor'; fx.tier='light'
for _=1,10 do pool:Emit(b,fx) end
fx.kind='hit'; fx.material='soft'
for _=1,30 do pool:Emit(b,fx) end
assert(pool.count==64 and pool.evicted>0,'kernels reclaim old decorative slots')
local before=pool.kernels
pool:Emit(b,fx); assert(pool.kernels>before and pool.count==64)
fx.broke=true
for _=1,10 do pool:Emit(b,fx) end
local dropped=pool.kernelsDropped
fx.broke=false; pool:Emit(b,fx)
assert(pool.kernelsDropped>dropped and pool.count<=64)
local stats=pool:GetStats(); assert(stats.whiteKernels==pool.kernels and stats.whiteKernelsDropped==pool.kernelsDropped)
print('PASS first-slot kernel, exact total counts, priority1/2/3 reserve, eviction and lost-kernel statistics')
pool:ClearOwner(b); fx.killed=true
for _=1,64 do assert(pool:Emit(b,fx)==1) end
fx.killed=false; fx.broke=true
assert(pool:Emit(b,fx)==11,'denied priority1 kernel must not block higher priority armor chips')
pool:ClearOwner(b); fx.broke=false; fx.kind='phase'
pool:Emit(b,fx)
fx.kind='hit'; fx.broke=true
local firstSerial=pool.serial+1
pool:Emit(b,fx)
local visible=false
for _,slot in ipairs(pool.slots) do if slot.active and slot.serial==firstSerial then visible=slot.material=='flash' end end
assert(visible,'same impact decorations must not evict its own kernel')

b=make(Beetle); b.aggro=true; b:SetState('ATTACK')
b:Knockback({dir=Vector3(1,0,0)},.1); b:Update(.045,Vector3(0,0,20))
T.Near(b.position.x,.0875); T.Near(b.position.z,0)
print('PASS kernel denial retains armor priority and knock motion is not cancelled by attack travel')
