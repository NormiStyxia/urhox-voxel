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
print('PASS pool capacity/reuse, full penetration cap, wall ordering/embed expiry, parabolic integration')
