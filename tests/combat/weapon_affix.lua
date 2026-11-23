package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
require('weapon_mock')
-- Sub-stats (one stat tweak) and one-line passives (one multiplier per hit).
local Catalog=require('combat.WeaponCatalog')
local Store=require('combat.WeaponStore')
local C=require('combat.CombatMoves')
local function near(a,b,e) assert(math.abs(a-b)<(e or 1e-9),tostring(a)..' != '..tostring(b)) end
local function stats(class,id,level)
    local slot={weapon=id,imprints={},levels={[id]=level or 1},ranks={},failures={}}
    for _,imprint in ipairs(Catalog.Imprints[class]) do slot.ranks[imprint.id]=1; slot.failures[imprint.id]=0 end
    return Catalog.Stats(class,{slots={[class]=slot}})
end
-- Sub-stats: each weapon changes exactly one number.
near(stats('sword','iron').reach,1.06)
near(stats('sword','warden').reach,1.12)
near(stats('sword','wing').poise,6*1.10)
near(stats('bow','field').move,.5*1.10)
near(stats('bow','silver').armorBreak,1*1.10)
near(stats('bow','thorn').move,.5*1.10)
near(stats('time','clock').attack,6*1.10)
assert(stats('sword','iron').passive=='stable' and stats('bow','thorn').passive=='thorn')
-- The removed stats are gone from every weapon.
for _,class in ipairs({'sword','bow'}) do
    local s=stats(class,class=='sword' and 'wing' or 'thorn')
    assert(s.draw==nil and s.range==nil and s.speed==nil and s.spread==nil and s.projectileSpeed==nil)
end
assert(stats('time','clock').terrainPower==nil,'terrain power removed')
-- Passives: each fires only under its own condition.
local P=Catalog.Passive
local function pair(id,ctx) local d,p=P(id,ctx or {}) return d,p end
local d,p=pair('stable',{combo=3}) near(p,1.2) near(d,1)
d,p=pair('stable',{combo=2}) near(p,1)
d,p=pair('guard',{staggered=true}) near(d,1.15)
d,p=pair('guard',{staggered=false}) near(d,1)
d,p=pair('wind',{sprintFresh=true}) near(d,1.25)
d,p=pair('hunt',{unaware=true}) near(d,1.15)
d,p=pair('hunt',{unaware=false}) near(d,1)
d,p=pair('silver',{full=true}) near(p,1.25)
d,p=pair('silver',{full=false}) near(p,1)
d,p=pair('thorn',{full=true}) near(d,1.20)
d,p=pair('star',{shatter=true}) near(d,1.20)
d,p=pair('star',{shatter=false}) near(d,1)
d,p=pair(nil,{combo=3,full=true}) near(d,1) near(p,1)
-- Wind window: the first hit within one second after a sprint ends.
local m=setmetatable({age=10,sprintEndAt=9.5,windUsed=false},C)
assert(m:WindReady(),'fresh within one second')
m.windUsed=true; assert(not m:WindReady(),'only the first hit')
m.windUsed=false; m.age=11.2; assert(not m:WindReady(),'expires after one second')
print('PASS weapon affix: sub-stats change one number, removed stats gone, passives gated by condition, wind window')

local config=Store.Default()
local base=stats('sword','iron')
local sword=Catalog.Stats('sword',config.progress)
near(sword.attack,base.attack*1.08)
near(sword.reach,base.reach*1.16)
local changed=assert(Store.Edit(config,'sword','refine','edge','edge',function()return 1 end))
near(Catalog.Stats('sword',changed.progress).attack,base.attack*1.16)
near(Catalog.Stats('sword',config.progress).attack,base.attack*1.08)
local slot=changed.progress.slots.sword
slot.counts.impact,slot.counts.ningshi=1,1
changed=assert(Store.Edit(changed,'sword','imprint','impact'))
changed=assert(Store.Edit(changed,'sword','imprint','ningshi'))
sword=Catalog.Stats('sword',changed.progress)
near(sword.reach,base.reach)
near(sword.poise,base.poise*1.27)
local origin,forward=Vector3.ZERO,Vector3.FORWARD
local zone=C.MeleeZone('sword_light_1',origin,forward,sword.reach)
local wider=C.MeleeZone('sword_light_1',origin,forward,Catalog.Stats('sword',config.progress).reach)
assert(wider.radius>zone.radius)

local bow=Catalog.Stats('bow',config.progress)
local projectile=require('combat.Projectile').New({random=function() return .5 end})
local fired,arrow=projectile:Fire(origin,forward,1,bow)
assert(fired and arrow)
near(arrow.damage,8*1.08*1.5*1.2)
near(arrow.armorBreak,1.20)
local drawMove=setmetatable({clip='bow_hold',rig={GetStats=function()return bow end}},C)
near(drawMove:MoveScale(),.5*1.1*1.1)

GetPlatform=function() return 'MacOS' end
local Spells=require('ruins.TimeSpells')
local terrainRadius
local spellTarget={canShatter=true,Shatter=function(_,opts) terrainRadius=opts.radius; return true end}
local target={id='imprint_target'}
local spellHit,enemyRadius
local Hit=require('combat.Hit')
local queryZone=Hit.QueryZone
Hit.QueryZone=function(_,zone)
    enemyRadius=zone.radius
    return {{enemy=target,shape={id='body'},pos=origin}}
end
assert(Spells.BY_ID.shatter.cast({puzzles={list={}},spellDamaged={},
    catalystStats=function() return Catalog.Stats('time',config.progress) end,
    spellHit=function(_,info) spellHit=info;return true end},
    {hit=true,object=spellTarget,pos=origin,dir=forward},1))
Hit.QueryZone=queryZone
near(terrainRadius,Spells.ShatterRadius(1)*1.12)
near(enemyRadius,Spells.ShatterRadius(1))
near(spellHit.dmg,6*1.1*1.1*1.5*1.2)
near(spellHit.poise,3*1.20)
print('PASS equipped imprint effects reach melee zones, arrow damage and armor break, draw movement, and shatter damage, poise and terrain radius')
