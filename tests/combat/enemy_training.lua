-- Offline regression for the isolated five-enemy training driver.
package.path='scripts/?.lua;tests/?.lua;'..package.path
local T=require('combat.enemy_support')
local Spawner=require('combat.enemies.Spawner')
local Base=require('combat.enemies.EnemyBase')

local terrain,combat=T.Fixture()
local sp=Spawner.NewTraining(nil,nil,terrain,combat)
local enemies=sp:GetEnemies()
local pool=sp:GetParticlePool()
assert(sp.training and not sp.boss,'training starts without a Boss')
assert(#enemies==0 and #sp.obstacles==0,'training starts as an empty arena')
assert(pool and pool:GetStats().count==0,'empty training still owns a clean particle pool')

local names={'WoodSpirit','NestWeaver','RockColossus','RuinConstruct','TimeWraith'}
local previous
for _,name in ipairs(names) do
    local enemy=sp:SpawnTraining(name,Vector3(0,0,0))
    assert(sp:GetEnemies()==enemies,'GetEnemies table reference changed')
    assert(#enemies==1 and enemies[1]==enemy,'training keeps one enemy')
    assert(enemy.config.model==name,'wrong model dispatched for '..name)
    assert(enemy.active and not enemy.boss,'training enemy is active and not a Boss')
    if previous then
        assert(previous.particles==nil,'replaced training enemy kept its particle owner')
        assert(previous.visual==nil,'replaced training enemy kept its visual')
    end
    sp:Update(.016,Vector3(0,0,1.8))
    assert(enemy.selected,'training enemy was not selected by the normal scheduler')
    previous=enemy
end

-- Reopening the same actor destroys its old warning/projectile owner first.
local old=sp:SpawnTraining('RuinConstruct',Vector3(1,0,0))
old:SetState(Base.State.TELEGRAPH)
assert(old.warning.visible,'training warning did not activate before replacement')
local reopened=sp:SpawnTraining('RuinConstruct',Vector3(2,0,0))
assert(old~=reopened and #enemies==1 and enemies[1]==reopened,'same-model reopen retained duplicate')
assert(old.particles==nil and old.visual==nil and not old.warning.visible and not old.selected,
    'same-model reopen did not clear old warning/effects/selection')

local killed=sp:SpawnTraining('TimeWraith',Vector3(0,0,0))
local result=killed:ApplyHit({dmg=99999,part='mantle',kind='arrow',dir=Vector3(0,0,1)})
assert(result.killed and killed.dead,'training actor lethal hit failed')
T.Tick(killed,1.3,Vector3(0,0,1.8))
assert(killed.deathFinished and combat.deaths==1,'training death did not settle once')
sp:ClearTraining()
assert(#enemies==0 and sp:GetParticlePool()==pool,'ClearTraining invalidated public state or pool')
assert(pool:GetStats().count==0,'ClearTraining left particles/projectiles alive')
assert(sp:ClearTraining() and #enemies==0,'ClearTraining is not idempotent')
sp:Destroy()
assert(sp:GetParticlePool()==nil and pool.references==0,'training particle pool was not released')
print('PASS enemy training: empty arena, five swaps, same-model reopen, lethal cleanup, stable table and particle release')
