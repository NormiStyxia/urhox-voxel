package.path='scripts/?.lua;tests/?.lua;'..package.path
local T=require('combat.enemy_support')
local Base=require('combat.enemies.EnemyBase')
local Beetle=require('combat.enemies.MossBeetle')
local Beast=require('combat.enemies.StoneBeast')
local Sentry=require('combat.enemies.StoneSentry')
local Spawner=require('combat.enemies.Spawner')
local Terrain=require('ruins.RuinsTerrain')
local terrain,combat=T.Fixture()
local b=Beetle.New(nil,nil,terrain,combat,Vector3.ZERO,'r16')
assert(not b:GetHurtShapes()[4].enabled and not b:ApplyHit({dmg=1,part='belly'}).hit)
for _,id in ipairs({'side_l','side_r'}) do
    local before=b.hp; b:ApplyHit({dmg=1,part=id}); T.Near(before-b.hp,1.4)
end
for _,dir in ipairs({Vector3(0,0,1),Vector3(0,0,-1)}) do
    local before=b.hp; b:ApplyHit({dmg=1,part='shell',dir=dir}); T.Near(before-b.hp,.7)
end
b:Reset(); b.aggro=true; b:SetState('ATTACK'); b:FinishAttack()
assert(b.poseRoll==180 and b:GetHurtShapes()[4].enabled)
assert(b.hurtShapes[4].center.y>.5,'underside shape must turn with its body')
local before=b.hp; b:ApplyHit({dmg=1,part='belly'}); T.Near(before-b.hp,1.4)
b.hitStop=0; T.Tick(b,.79,combat.pos); assert(b.hurtShapes[4].enabled)
T.Tick(b,.01,combat.pos); assert(b.state=='CHASE' and b.poseRoll==0 and not b.hurtShapes[4].enabled)
assert(not b:ApplyHit({dmg=1,part='belly'}).hit)
print('PASS side abdomen x1.4; shell -30% from either direction; underside only during .8s flipped recovery')

local boss=Beast.New(nil,nil,terrain,combat,Vector3.ZERO,'rage')
boss:ApplyHit({dmg=301,part='foreleg_l'})
assert(boss.phase==2 and boss.parts.back_armor.armor==70 and not boss:GetHurtShapes()[5].enabled)
assert(not boss:ApplyHit({dmg=1,part='core'}).hit)
boss.hitStop=0; boss:Chase(.1,Vector3(0,0,20),20); T.Near(boss.position.z,.23)
for i=1,3 do
    boss:SelectAttack()
    assert(boss.attack.telegraph>=Beast.Config.attacks[i].telegraph*.85)
    assert(boss.attack.recover<Beast.Config.attacks[i].recover)
end
boss:Reset(); boss:ApplyHit({dmg=56,armorBreak=1.25,part='back_armor',poise=7})
assert(boss.parts.back_armor.broken and boss.hp==544 and boss.poise==7)
assert(boss:GetHurtShapes()[5].enabled and boss.phase==1)
print('PASS rage speed +15%, shorter recovery, independent armor; armorBreak scales armor without scaling HP/poise')

-- A small interior hole missed by the old center + circumference checks.
local probe=boss.footprint[3]
local hx,hz=probe.x+.2,probe.z
local hole={VOID_Y=-128}
function hole.HasGround(x,z) return (x-hx)^2+(z-hz)^2>.065^2 end
function hole.GroundHeight(x,z) if hole.HasGround(x,z) then return 0 end end
function hole.IsSafeGround(x,y,z) return hole.HasGround(x,z) and y==0 end
boss=Beast.New(nil,nil,hole,combat,Vector3.ZERO,'interior')
assert(not boss:Move(1,0) and boss.blockReason=='edge' and boss.position.x<.2)
-- Off-center void strip catches knockback and retreat even with safe center/end.
local strip={VOID_Y=-128}
function strip.HasGround(x,z) return not (x>.45 and x<.65 and z>.30) end
function strip.GroundHeight(x,z) if strip.HasGround(x,z) then return 0 end end
function strip.IsSafeGround(x,y,z) return strip.HasGround(x,z) and y==0 end
b=Beetle.New(nil,nil,strip,combat,Vector3.ZERO,'knock')
b:Knockback({dir=Vector3(1,0,0)},1)
assert(b.moveBlocked and b.position.x<.45 and b:SafeHeight(b.position.x,b.position.z)~=nil)
local sentry=Sentry.New(nil,nil,strip,combat,Vector3.ZERO,'retreat')
sentry:Chase(.2,Vector3(-2,0,0),2)
assert(sentry.moveBlocked and sentry.position.x<.45)
print('PASS swept body interior, off-center gap, knockback and sentry retreat truncate before unsupported footprint')

local sp=Spawner.New(nil,nil,Terrain,combat)
assert(#sp.enemies==7 and #sp.rejected==0)
for _,suffix in ipairs({'w','e'}) do
    local bugs,spirits=0,0
    for _,e in ipairs(sp.enemies) do
        if e.id:find('_'..suffix) then
            if e.kind=='moss_beetle' then bugs=bugs+1 elseif e.kind=='stone_sentry' then spirits=spirits+1 end
        end
    end
    assert(bugs==2 and spirits==1)
end
sp:Update(.01,sp.enemies[1].home)
local firstStats=sp:GetPerfStats()
assert(firstStats.minorCount>=3 and firstStats.minorCount<=4 and firstStats.bossCount==0)
local ranged=sp.enemies[3]; ranged:SetActive(true); ranged:BeginAttack()
assert(ranged.stones[1].active)
sp:Update(.01,sp.boss.home)
local stats=sp:GetPerfStats()
assert(stats==firstStats and stats.activeCount==1 and stats.bossCount==1 and stats.minorCount==0)
assert(not ranged.stones[1].active and sp.attackGroup.count<=1)
for _,e in ipairs(sp.enemies) do if not e.boss then assert(not e.active) end end
sp:Update(.01,Vector3(-60,6,-60)); assert(sp:GetPerfStats().bossCount==0)
sp.boss:SetActive(true); sp.boss:ApplyHit({dmg=10000,part='head'})
sp:Reset(); sp:Update(.01,sp.boss.home)
assert(sp.boss.dead and sp:GetPerfStats().bossCount==0)
print('PASS encounter composition; Boss/minor isolation including projectile cleanup; defeated Boss cannot reactivate')

local pack={}
for i=1,4 do pack[i]=Beetle.New(nil,nil,terrain,combat,Vector3.ZERO,'pool_'..i) end
local pool=pack[1].particles
for _,e in ipairs(pack) do assert(e.particles==pool) end
-- Clear earlier actors using this same scene/combat key, then saturate the pool.
for _,slot in ipairs(pool.slots) do pool:Hide(slot) end
local firstSlot=pool.slots[1]
for _,e in ipairs(pack) do
    for _=1,30 do pool:Emit(e,3,false) end
    assert(pool.count<=64)
end
assert(pool.count==64)
for _,e in ipairs(pack) do e:ApplyHit({dmg=1000}) end
assert(pool.count<=64 and pool.peak<=64)
for _,e in ipairs(pack) do T.Tick(e,1.5,combat.pos) end
assert(pool.count==0 and pool.slots[1]==firstSlot)
assert(pool:Emit(pack[1],16,true)==16 and pool.slots[1]==firstSlot)
for _,e in ipairs(pack) do e:Destroy() end
assert(pool.count==0)
for _,class in ipairs({Beetle,Sentry,Beast}) do
    local e=class.New(nil,nil,terrain,combat,Vector3.ZERO,'stats')
    local info=e:GetStats()
    assert(info==e:GetStats() and info.activeCount==1 and info.voxelCount<=3000 and info.voxelCount>0)
    assert(info.surfaceFacesEstimate>0 and info.drawSubmissionsEstimate>0)
    e:SetActive(false); assert(e:GetStats().activeCount==0 and e:GetStats().drawSubmissionsEstimate==0)
    e:Destroy()
end
stats=sp:GetPerfStats()
assert(stats.particleCapacity==64 and stats.particleCount<=64 and stats.voxelCount>0)
assert(stats.actualDrawCalls==false and stats.actualFrameMs==false)
sp:Destroy()
print('PASS shared 64-slot hit/death pool saturates/reuses/cleans; stats reuse snapshots and label unmeasured GPU/frame counters')
