package.path='scripts/?.lua;tests/?.lua;'..package.path
-- Sub-stats (one stat tweak) and one-line passives (one multiplier per hit).
local Catalog=require('combat.WeaponCatalog')
local C=require('combat.CombatMoves')
local function near(a,b,e) assert(math.abs(a-b)<(e or 1e-9),tostring(a)..' != '..tostring(b)) end
local function stats(class,id,level)
    local slot={weapon=id,imprint='',levels={[id]=level or 1},ranks={},failures={}}
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
