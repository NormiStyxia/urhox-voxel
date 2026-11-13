package.path='scripts/?.lua;tests/?.lua;'..package.path
local T=require('combat.enemy_support')
local Beetle=require('combat.enemies.MossBeetle')
local Beast=require('combat.enemies.StoneBeast')
local Sentry=require('combat.enemies.StoneSentry')
local Spawner=require('combat.enemies.Spawner')
local Terrain=require('ruins.RuinsTerrain')
local terrain,combat=T.Fixture()
local function actor(class)
    -- Separate fixture key for isolated pools; no engine, no runtime.
    local _,c=T.Fixture()
    return class.New(nil,nil,terrain,c,Vector3.ZERO,'r19')
end
local function events(e)
    local out={}
    e.onEvent=function(name,info)
        out[#out+1]={name=name,time=e.age,enemy=info.enemy,phase=info.phase,danger=info.danger,magnitude=info.magnitude,duration=info.duration}
    end
    return out
end
local function count(log,name)
    local n=0; for _,e in ipairs(log) do if e.name==name then n=n+1 end end; return n
end
local b=actor(Beetle)
assert(b:GetHurtShapes()[1].material=='armor' and b:GetHurtShapes()[2].material=='soft')
local hit=b:ApplyHit({dmg=1,part='side_l',pos=Vector3(-.6,.3,0),dir=Vector3(1,0,0),tier='light'})
assert(hit.hit and hit.part=='side_l' and hit.material=='soft' and hit.weak and not hit.broke and not hit.staggered and not hit.killed)
local pool=b.particles
assert(pool.count==6)
for _,p in ipairs(pool.slots) do if p.active then
    T.Near(p.x,-.6); T.Near(p.y,.3); T.Near(p.z,0)
    assert(p.vx>0 and p.shape=='cross' and p.ttl>=.18 and p.ttl<=.28)
end end
hit=b:ApplyHit({dmg=1,part='belly'})
assert(not hit.hit and hit.part==nil and hit.material==nil and not hit.weak)
local boss=actor(Beast)
local r=boss:ApplyHit({dmg=1,part='foreleg_l',poise=100,pos=Vector3(-.8,.4,.7),dir=Vector3(0,0,1)})
assert(r.staggered and not r.broke and r.material=='armor')
boss:Reset(); r=boss:ApplyHit({dmg=40,part='foreleg_l'})
assert(r.broke and r.partBroken=='foreleg_l' and not r.staggered)
r=boss:ApplyHit({dmg=10000,part='head'})
assert(r.killed and r.broke and not r.staggered)
local sentry=actor(Sentry); sentry:BeginAttack()
r=sentry:ApplyHit({dmg=1,part='stone_1',kind='sword',pos=Vector3(0,1,0),dir=Vector3(1,0,0)})
assert(r.hit and r.material=='stone' and r.part=='stone_1' and not r.killed and not r.broke)
print('PASS material metadata, compatible enriched hit result, reset scratch result, correct deflection material')

local fx={pos=Vector3(4,5,6),dir=Vector3(1,0,0),normal=Vector3(0,1,0),material='soft',tier='light'}
local function emit(expected)
    pool:ClearOwner(b)
    assert(pool:Emit(b,fx)==expected)
    for _,p in ipairs(pool.slots) do if p.active then T.Near(p.x,4); T.Near(p.y,5); T.Near(p.z,6) end end
end
emit(6)
for _,p in ipairs(pool.slots) do if p.active then assert(p.shape=='cube' and p.sx>=.04 and p.sx<=.08 and p.ttl>=.18 and p.ttl<=.30) end end
fx.material='armor'; emit(8)
for _,p in ipairs(pool.slots) do if p.active then
    assert(p.shape=='spark' and p.sy<p.sz/5 and p.ttl>=.15 and p.ttl<=.25)
    local speed=math.sqrt(p.vx^2+p.vy^2+p.vz^2); assert(speed>=1.5 and speed<=3)
    T.Near(p.vy,0) -- tangent to supplied up normal
end end
fx.tier='heavy'; emit(11)
local flashes=0
for _,p in ipairs(pool.slots) do if p.active and p.material=='flash' then flashes=flashes+1; T.Near(p.ttl,.06) end end
assert(flashes==1); pool:UpdateOwner(b,.06); assert(pool.count==10)
fx.tier='light'; fx.weak=true; emit(6)
fx.broke=true; emit(12)
for _,p in ipairs(pool.slots) do if p.active then assert(p.shape=='plate' and p.vy>0 and p.priority==2) end end
fx.broke=false; fx.weak=false; fx.kind='death'; emit(12)
pool:ClearOwner(b); local realBoss=b.boss; b.boss=true; emit(24); b.boss=realBoss
fx.kind='hit'; fx.material='soft'; pool:ClearOwner(b)
for _=1,20 do pool:Emit(b,fx) end
assert(pool.count==40 and pool:GetStats().cubeCount==40)
fx.material='armor'; for _=1,10 do pool:Emit(b,fx) end
assert(pool.count==48,'normal effects cannot spend 16 key-event slots')
fx.broke=true; assert(pool:Emit(b,fx)==12 and pool.count==60)
assert(pool:Emit(b,fx)==12 and pool.count==64 and pool.evicted==8)
local snapshot=pool:GetStats(); assert(snapshot==pool:GetStats() and snapshot.reserved==16 and snapshot.count<=64)
pool:SetLimit(32); assert(pool.count<=32 and pool:GetStats().capacity==32)
pool:ClearOwner(b); fx.broke=false; fx.material='soft'
for _=1,20 do pool:Emit(b,fx) end
assert(pool.count<=16 and pool:GetStats().cubeCount<=20)
print('PASS directed profiles, counts/lifetimes, tangent sparks, heavy flash, weak crosses, armor normals, 32/64 reserve/preemption')

for _,fps in ipairs({30,60}) do
    boss=actor(Beast); local log=events(boss)
    boss:Stagger(3,true)
    for _=1,math.floor(.15*fps) do boss:Update(1/fps,Vector3(0,0,2)) end
    assert(boss.poseRoll<5,'first .15 seconds are loss of footing')
    while boss.stateTime<.36 do boss:Update(1/fps,Vector3(0,0,2)) end
    assert(boss.poseRoll>=65 and boss.poseRoll<=80 and count(log,'stagger_land')==1)
    local shape=boss:GetHurtShapes()[1]
    assert(math.abs(shape.center.x)>.2,'hurt geometry rotates together with rigid body')
    while boss.stateTime<2.59 do boss:Update(1/fps,Vector3(0,0,2)) end
    assert(boss.down)
    T.Tick(boss,.42,Vector3(0,0,2)); assert(not boss.down and boss.poseRoll==0 and count(log,'stagger_land')==1)
    b=actor(Beetle); log=events(b)
    b:SetState('TELEGRAPH')
    while b.state=='TELEGRAPH' do b:Update(1/fps,Vector3(0,0,2)) end
    assert(count(log,'enemy_windup')==2 and log[1].enemy=='beetle' and not log[1].danger)
    assert(log[2].danger and log[2].time>=.42-1e-8 and log[2].time<=.42+1/fps+1e-8)
    assert(b.cue.phase=='whoosh')
end
print('PASS 30/60fps rigid fall/get-up, hurt-shape rotation, one landing cue, two windup cues including danger lock')

b=actor(Beetle); local log=events(b)
b:ApplyHit({dmg=1,part='side_r',dir=Vector3(1,0,0)})
assert(b.reaction.angle>=4 and b.reaction.angle<=8 and b.reaction.shift>=.02 and b.reaction.shift<=.05)
T.Tick(b,.13,combat.pos); assert(b.reaction.age>=.12)
b:ApplyHit({dmg=1000,part='shell',pos=Vector3(.4,.5,.6),dir=Vector3(1,0,0)})
assert(b.particles.count==0 and b:GetStats().deathStage=='hold')
T.Tick(b,.12,combat.pos); assert(b:GetStats().deathStage=='release' and count(log,'die')==0)
T.Tick(b,.13,combat.pos); assert(count(log,'die')==1 and b.particles.count==12)
for _,p in ipairs(b.particles.slots) do if p.active then T.Near(p.x,.4); T.Near(p.z,.6) end end
T.Tick(b,.85,combat.pos); assert(b.particles.count==0 and b.deathFinished and count(log,'die')==1)
assert(count(log,'victory')==0)
print('PASS local recoil real-time decay; death .12 hold/.25 fragments/1.1 clear; delayed single die cue')

for _,broken in ipairs({false,true}) do
    boss=actor(Beast); log=events(boss)
    if broken then boss:ApplyHit({dmg=70,part='back_armor'}) end
    boss:ApplyHit({dmg=301,part='foreleg_l'})
    assert(boss.phase==2 and boss.ragePending and not boss:StartAttack())
    boss.particles:ClearOwner(boss)
    T.Tick(boss,.44,Vector3(0,0,8)); assert(boss.rageActive and count(log,'boss_roar')==0)
    T.Tick(boss,.01,Vector3(0,0,8))
    assert(count(log,'boss_roar')==1 and count(log,'camera_shake')==1 and boss.particles.count==(broken and 10 or 0))
    assert(boss.parts.back_armor.broken==broken and boss:GetHurtShapes()[5].enabled==broken)
    assert(not boss:StartAttack())
    T.Tick(boss,.75,Vector3(0,0,8)); assert(boss.rageDone and not boss.rageActive and boss.state=='CHASE')
    boss:Update(.01,Vector3(0,0,8)); assert(boss.state=='TELEGRAPH' and boss.warning.progress==0)
    boss:ApplyHit({dmg=1,part='foreleg_l'}); T.Tick(boss,.1,Vector3(0,0,8)); assert(count(log,'boss_roar')==1)
    boss:ApplyHit({dmg=10000,part='head'}); T.Tick(boss,1.11,combat.pos)
    assert(count(log,'die')==1 and count(log,'victory')==1 and boss.particles.count==0)
end
boss=actor(Beast); log=events(boss)
boss:ApplyHit({dmg=301,part='foreleg_l',poise=100})
assert(boss.down and boss.ragePending)
T.Tick(boss,2,combat.pos); assert(boss.down and count(log,'boss_roar')==0)
T.Tick(boss,1.2,combat.pos); assert(boss.rageActive and not boss.down)
T.Tick(boss,1.2,combat.pos); assert(boss.rageDone and count(log,'boss_roar')==1)
print('PASS one 1.2s rage sequence, .45 roar/shake, no automatic armor break, broken-only chips, fresh warning, stagger priority, final victory')

local sp=Spawner.New(nil,nil,Terrain,combat)
assert(sp:GetParticlePool()==sp.enemies[1].particles)
local stats=sp:GetPerfStats()
assert(stats.particleReserved==16 and stats.particleCapacity==64 and stats.particleCount<=64)
sp:Destroy()
for _,fps in ipairs({30,60}) do
    local e=actor(Beast); local timeline=events(e)
    e:ApplyHit({dmg=301,part='foreleg_l'})
    for _=1,math.ceil(1.2*fps) do e:Update(1/fps,Vector3(0,0,8)) end
    assert(e.rageDone and count(timeline,'boss_roar')==1)
    for _,event in ipairs(timeline) do if event.name=='boss_roar' then
        assert(event.time>=.45-1e-8 and event.time<=.45+1/fps+1e-8)
    end end
    e:ApplyHit({dmg=10000,part='head'})
    local killedAt=e.age
    for _=1,math.ceil(1.1*fps)+1 do e:Update(1/fps,combat.pos) end
    assert(e.deathFinished and count(timeline,'die')==1 and count(timeline,'victory')==1)
    for _,event in ipairs(timeline) do if event.name=='die' then
        assert(event.time-killedAt>=.25-1e-8 and event.time-killedAt<=.25+1/fps+1e-8)
    end end
end
print('PASS 30/60fps rage/death cue deadlines and shared-pool performance snapshot; enemy_revision19 complete')
