local S=dofile('tests/combat/core_support.lua')
local P=require('combat.Projectile')
local hits=0
local function Enemy(x,boss)
    return {boss=boss,active=true,GetHurtShapes=function() return {{id='body',center=Vector3(x,0,0),radius=.4}} end,
        ApplyHit=function(_,info) hits=hits+1; return {hit=true} end}
end
local enemies={Enemy(1),Enemy(2),Enemy(3)}
local p=P.New{enemies=function() return enemies end}
assert(p:Fire(Vector3.ZERO,Vector3(1,0,0),1,{attack=8}))
p:Update(.1); assert(hits==2,'full arrow pierces exactly one small enemy')
hits=0
p=P.New{enemies=function() return enemies end,cast=function(a,b)
    return a.x<=.5 and b.x>=.5 and (.5-a.x)/(b.x-a.x) or nil end}
p:Fire(Vector3.ZERO,Vector3(1,0,0),1,{attack=8}); p:Update(.1)
assert(hits==0 and p.pool[1].embedded,'wall before enemy')
p:Update(.8); assert(not p.pool[1].active)
p=P.New{}
for i=1,12 do assert(p:Fire(Vector3.ZERO,Vector3(1,0,0),0,{})) end
assert(not p:Fire(Vector3.ZERO,Vector3(1,0,0),0,{})); assert(#p.pool==12)
p:Clear(); assert(p:Fire(Vector3.ZERO,Vector3(1,0,0),.5,{}))
p:Update(.1); S.near(p.pool[1].pos.x,3); S.near(p.pool[1].pos.y,-.03)
p:Clear(); p:Fire(Vector3.ZERO,Vector3(1,0,0),1,{attack=10,crystalRadius=.8,crystalDamageMultiplier=.25,armorBreak=1.25})
S.near(p.pool[1].damage,18); S.near(p.pool[1].crystalDamage,4.5); S.near(p.pool[1].armorBreak,1.25)
-- Crystal burst follows resolved arrow damage (charge tier and target weak point).
local function DamageEnemy(center,radius,multiplier,boss)
    return {hp=1000,boss=boss,active=true,
        GetHurtShapes=function() return {{id='body',center=center,radius=radius,weak=multiplier>1}} end,
        ApplyHit=function(self,info)
            self.received=(self.received or 0)+info.dmg
            self.hp=math.max(0,self.hp-info.dmg*multiplier)
            return {hit=true}
        end}
end
for _,tier in ipairs({{.1,.5},{.5,1},{1,1.8}}) do
    for _,weak in ipairs({1,1.6}) do
        local direct=DamageEnemy(Vector3(1,0,0),.3,weak,true)
        local splash=DamageEnemy(Vector3(.7,.6,0),.1,1,false)
        p=P.New{enemies=function() return {direct,splash} end}
        p:Fire(Vector3.ZERO,Vector3(1,0,0),tier[1],{attack=10,crystalRadius=.8,crystalDamageMultiplier=.25})
        p:Update(.1)
        S.near(splash.received,10*tier[2]*weak*.25)
        S.near(p.pool[1].damage,10*tier[2])
    end
end
-- Piercing into a second target recalculates its burst, without carrying weak damage.
local first=DamageEnemy(Vector3(1,0,0),.3,1.6,false)
local second=DamageEnemy(Vector3(3,0,0),.3,1,false)
p=P.New{enemies=function() return {first,second} end}
p:Fire(Vector3.ZERO,Vector3(1,0,0),1,{attack=10,crystalRadius=.8,crystalDamageMultiplier=.25})
p:Update(.1)
S.near(first.received,18); S.near(second.received,18); S.near(p.pool[1].crystalDamage,4.5)
-- Old fixed damage is intentionally unsupported; slot reuse clears its multiplier.
p:Clear(); p:Fire(Vector3.ZERO,Vector3(1,0,0),.1,{attack=10,crystalRadius=.8,crystalDamage=999})
S.near(p.pool[1].crystalDamage,0); S.near(p.pool[1].crystalDamageMultiplier,0)
print('PASS crystal weak/mid/full tiers, resolved weak damage, piercing isolation, multiplier slot reset')
print('PASS pool capacity/reuse, full penetration cap, wall ordering/embed expiry, parabolic integration')
