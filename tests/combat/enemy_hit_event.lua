-- Unified-event handoff: settlement is authoritative; borrowed presentation consumes once.
package.path='scripts/?.lua;tests/?.lua;'..package.path
local T=require('combat.enemy_support')
local Beetle=require('combat.enemies.MossBeetle')
local Beast=require('combat.enemies.StoneBeast')
local Sentry=require('combat.enemies.StoneSentry')
local Hit=require('combat.Hit')
local terrain,combat=T.Fixture()
local function enemy(class,id)
    return class.New(nil,nil,terrain,combat,Vector3.ZERO,id)
end
local function event(info,r)
    return {swingId=info.swingId,weapon='sword',tier=info.heavy and 'heavy' or 'light',
        material=r.material,part=r.part,pos=info.pos,dir=info.dir,normal=info.normal,
        broke=r.broke,staggered=r.staggered,killed=r.killed,weak=r.weak}
end
local a,b=enemy(Beetle,'sweep_a'),enemy(Beetle,'sweep_b')
local info={dmg=1,part='side_l',kind='sword',swingId='sword:51',deferPresentation=true,
    pos=Vector3(-.6,.3,0),dir=Vector3(1,0,0),normal=Vector3(-1,0,0)}
local ar=Hit.Apply(a,info); local br=Hit.Apply(b,info)
assert(ar.hit and br.hit and a.hp==28.6 and b.hp==28.6)
assert(a.presentedHits==0 and b.presentedHits==0 and a.particles.count==0)
assert(a.reaction.age==1 and b.reaction.age==1 and a.hitStop==0)
local borrowed=event(info,ar)
assert(a:OnHitEvent(borrowed))
assert(a.presentedHits==1 and b.presentedHits==0 and a.particles:CountOwner(a)==6)
local serial=a.particles.serial
assert(not a:OnHitEvent(borrowed) and a.particles.serial==serial)
assert(b:OnHitEvent(borrowed),'same swing must still present the second target')
assert(b.presentedHits==1 and b.particles:CountOwner(b)==6 and a.particles.count==12)
assert(not b:OnHitEvent(borrowed))
assert(a.reaction.age==0 and a.reaction.part=='belly')
borrowed.pos.x=100; borrowed.dir.z=100; borrowed.normal.x=100
T.Near(a.impact.pos.x,-.6); T.Near(a.impact.dir.z,0); T.Near(a.impact.normal.x,-1)
assert(a.impact~=borrowed)
a:Destroy(); b:Destroy()
print('PASS deferred settlement: no immediate particles/reaction; sweep presents each target once; duplicate event ignored; borrowed vectors copied')

local e=enemy(Beetle,'legacy')
local legacy={dmg=1,part='shell',pos=Vector3(.4,.5,0),dir=Vector3(-1,0,0),swingId=52}
local r=e:ApplyHit(legacy)
assert(e.presentedHits==1 and e.particles:CountOwner(e)==8 and e.reaction.age==0 and e.hitStop==.04)
serial=e.particles.serial
assert(not e:OnHitEvent(event(legacy,r)) and e.particles.serial==serial)
e.reaction.age=.07
local defer={dmg=1,part='side_r',swingId=53,deferPresentation=true,pos=Vector3(.5,.3,0),dir=Vector3(-1,0,0)}
r=e:ApplyHit(defer)
assert(e.reaction.age==.07 and e.reaction.part=='shell' and e.presentedHits==1 and e.particles.serial==serial)
local nextEvent=event(defer,r)
nextEvent.swingId=52; assert(not e:OnHitEvent(nextEvent))
nextEvent.swingId=53; nextEvent.part='shell'; assert(not e:OnHitEvent(nextEvent))
nextEvent.part='side_r'; assert(e:OnHitEvent(nextEvent) and e.presentedHits==2 and e.reaction.part=='belly')
e:Reset(); r=e:ApplyHit(defer); nextEvent=event(defer,r); e:Reset(); assert(not e:OnHitEvent(nextEvent))
e:Destroy()
print('PASS default/explicit legacy behavior; previous reaction preserved until handoff; mismatched events and reset cannot consume a token')

local boss=enemy(Beast,'armor')
info={dmg=56,armorBreak=1.25,poise=100,part='back_armor',swingId=54,deferPresentation=true,heavy=true,
    pos=Vector3(0,1.4,-1),dir=Vector3(0,0,1),normal=Vector3(0,0,-1)}
r=boss:ApplyHit(info)
assert(r.broke and r.staggered and boss.down and boss.parts.back_armor.broken and boss.hp==544)
assert(boss:GetHurtShapes()[5].enabled and boss.particles.count==0 and boss.reaction.age==1)
borrowed=event(info,r); assert(boss:OnHitEvent(borrowed))
assert(boss.particles:CountOwner(boss)==12 and boss.presentedHits==1 and boss.reaction.angle==8)
for _,p in ipairs(boss.particles.slots) do if p.active then assert(p.shape=='plate' and p.vz<0) end end
serial=boss.particles.serial; assert(not boss:OnHitEvent(borrowed) and boss.particles.serial==serial)
boss:Destroy()
print('PASS armor/HP/poise settlement before presentation; one armor burst replaces heavy particles; shared HitEvent tier drives recoil')

boss=enemy(Beast,'death')
local names={}
boss.onEvent=function(name) names[#names+1]=name end
info={dmg=10000,part='head',swingId=55,deferPresentation=true,heavy=true,
    pos=Vector3(1,2,3),dir=Vector3(1,0,0),normal=Vector3(0,1,0)}
r=boss:ApplyHit(info)
assert(r.killed and boss.dead and not boss.deathPresentationReady and boss.particles.count==0)
assert(boss.reaction.age==1 and not boss.deathBurst)
borrowed=event(info,r); assert(boss:OnHitEvent(borrowed))
assert(boss.deathPresentationReady and boss.presentedHits==1 and boss.particles.count==0)
assert(boss.deathImpact.pos~=borrowed.pos and boss.deathImpact.dir~=borrowed.dir and boss.deathImpact.normal~=borrowed.normal)
borrowed.pos.x,borrowed.pos.y,borrowed.pos.z=99,99,99
borrowed.dir.x,borrowed.dir.z=0,1; borrowed.normal.y=0
borrowed.part,borrowed.material,borrowed.tier,borrowed.weapon,borrowed.swingId='shell','soft','light','bow',99
assert(boss.deathImpact.part=='head' and boss.deathImpact.material=='armor' and boss.deathImpact.tier=='heavy')
assert(boss.deathImpact.weapon=='sword' and boss.deathImpact.swingId==55 and boss.deathImpact.killed)
T.Near(boss.deathImpact.pos.x,1); T.Near(boss.deathImpact.dir.x,1); T.Near(boss.deathImpact.normal.y,1)
assert(not boss:OnHitEvent(borrowed))
T.Tick(boss,.25,combat.pos)
assert(boss.particles:CountOwner(boss)==24)
for _,p in ipairs(boss.particles.slots) do if p.active then T.Near(p.x,1); T.Near(p.y,2); T.Near(p.z,3) end end
T.Tick(boss,.85,combat.pos)
local dies,wins=0,0
for _,name in ipairs(names) do if name=='die' then dies=dies+1 elseif name=='victory' then wins=wins+1 end end
assert(dies==1 and wins==1 and boss.particles.count==0)
boss:Destroy()
print('PASS deferred death copies all retained scalars/vectors; no immediate burst; delayed 24 fragments/die and single victory remain enemy-owned')

local s=enemy(Sentry,'deflect')
s:BeginAttack()
info={dmg=1,kind='sword',part='stone_1',swingId=56,deferPresentation=true,pos=Vector3(0,1,1),dir=Vector3(1,0,0)}
r=s:ApplyHit(info)
assert(r.hit and r.material=='stone' and not s.stones[1].active and s.particles.count==0 and s.hp==s.maxHP)
borrowed=event(info,r); assert(s:OnHitEvent(borrowed))
assert(s.particles.count==6 and s.reaction.age==1,'detached stone cannot recoil its caster')
assert(not s:OnHitEvent(borrowed))
s.particles:ClearOwner(s); s:BeginAttack(); info.deferPresentation=false; r=s:ApplyHit(info)
assert(r.hit and s.particles.count==6 and s.presentedHits==2)
s:Destroy()
print('PASS deflection supports deferred and legacy paths without caster reaction or duplicate chips; enemy_hit_event complete')
