package.path='scripts/?.lua;tests/?.lua;'..package.path
local T=require('combat.enemy_support')
local Terrain=require('ruins.RuinsTerrain')
local Spawner=require('combat.enemies.Spawner')
local _,combat=T.Fixture()
local sp=Spawner.New(nil,nil,Terrain,combat)
assert(#sp.enemies==7,'two packs of 2 beetles + 1 sentry, and independent boss')
assert(#sp.rejected==0)
assert(#sp.obstacles>=2 and #sp.obstacles<=3)
for _,e in ipairs(sp.enemies) do
    assert(e.config.ranged or e.attackGroup==sp.attackGroup,'melee actors must share the scheduler')
end
for _,p in ipairs(sp.placements) do
    assert(Terrain.IsSafeGround(p.x,p.y,p.z))
    assert((p.x^2+(p.z+64)^2)>=225)
    assert((p.x^2+(p.z-Terrain.ISLAND.bridgeMainZ)^2)>=225)
    assert((p.x^2+(p.z-Terrain.ISLAND.bridgeRingZ)^2)>=225)
    print(string.format('PLACEMENT %s %.3f %.3f %.3f',p.id,p.x,p.y,p.z))
end
assert(sp:ValidPosition(0,-44,.5)==nil,'void cannot spawn')
assert(sp:ValidPosition(0,-64,.5)==nil,'spawn protection')
assert(sp:ValidPosition(0,-36,.5)==nil,'bridge protection')
assert(sp:ValidPosition(0,4,.5)==nil,'dragon exclusion')
for x=-60,60,12 do for z=-60,60,12 do
    sp:Update(.016,Vector3(x,6,z))
    assert(sp.activeCount<=4 and sp.aiUpdates<=4)
end end
local enemy=sp.enemies[1]
enemy:SetActive(true)
for _=1,600 do
    enemy:Update(.05,Vector3(-44,6,-12))
    assert(Terrain.IsSafeGround(enemy.position.x,enemy.position.y,enemy.position.z),'pursuit entered void')
end
enemy:Reset()
enemy:SetActive(true); enemy:ApplyHit({dmg=5,poise=0})
assert(enemy.hp<enemy.maxHP)
sp:Update(.1,Vector3(70,6,70)); assert(enemy.hp==enemy.maxHP and not enemy.aggro)
enemy:SetActive(true); enemy:ApplyHit({dmg=1000}); assert(enemy.defeated)
sp:Reset(); sp:Update(.1,enemy.home); assert(enemy.dead and enemy.hp==0)
local invalid={ISLAND=Terrain.ISLAND,VOID_Y=-128,GroundHeight=function() return nil end,
    HasGround=function() return false end,IsSafeGround=function() return false end}
local rejected=Spawner.New(nil,nil,invalid,combat)
assert(#rejected.enemies==0 and #rejected.rejected==7)
print('PASS terrain-verified placement, spawn/bridge/dragon exclusion, four AI cap, survivor reset/no revival')
print('PASS enemy_spawner complete')
