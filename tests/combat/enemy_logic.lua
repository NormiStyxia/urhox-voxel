package.path='scripts/?.lua;tests/?.lua;'..package.path
local T=require('combat.enemy_support')
local Base=require('combat.enemies.EnemyBase')
local Beetle=require('combat.enemies.MossBeetle')
local Sentry=require('combat.enemies.StoneSentry')
local Beast=require('combat.enemies.StoneBeast')
local S=Base.State
local terrain,combat=T.Fixture()
local b=Beetle.New(nil,nil,terrain,combat,Vector3.ZERO,'beetle')
assert(b.state==S.IDLE)
T.Tick(b,1.21,Vector3(35,0,35)); assert(b.state==S.PATROL)
b:Reset(); b:Update(.01,combat.pos); assert(b.state==S.ALERT and combat.aggros==1)
T.Tick(b,.39,combat.pos); assert(b.state==S.ALERT and combat.hits==0)
T.Tick(b,.02,combat.pos); assert(b.state==S.TELEGRAPH)
T.Tick(b,.59,combat.pos); assert(b.state==S.TELEGRAPH and combat.hits==0)
assert(b.warning.visible and b.warning.step>=5)
T.Tick(b,.02,combat.pos); assert(b.state==S.ATTACK)
T.Tick(b,.2,combat.pos); assert(b.state==S.RECOVER and combat.hits==1)
T.Near(b.position.z,1.8)
T.Tick(b,.78,combat.pos); assert(b.state==S.RECOVER)
T.Tick(b,.03,combat.pos); assert(b.state~=S.RECOVER)
print('PASS state transitions, 0.4 alert, 0.6 telegraph, 1.8m lunge, 0.8 recovery, one hit')

b:Reset()
local r=b:ApplyHit({dmg=10,part='shell',dir=Vector3(0,0,-1)})
assert(r.hit); T.Near(b.hp,23)
b:ApplyHit({dmg=10,part='shell',dir=Vector3(0,0,-1)})
assert(b.parts.shell.broken and b.result.partBroken=='shell'); T.Near(b.hp,16)
assert(not b:ApplyHit({dmg=4,part='belly'}).hit)
b:ApplyHit({dmg=4,part='side_l'}); T.Near(b.hp,10.4)
b:ApplyHit({dmg=100}); assert(b.dead and combat.deaths==1 and not b:GetHurtShapes()[1].enabled)
assert(not b:Reset()); b:ApplyHit({dmg=10}); assert(combat.deaths==1 and not b.result.hit)
print('PASS frontal armor, part break, belly weakness, one-shot death notification, no respawn')

b=Beetle.New(nil,nil,terrain,combat,Vector3(47,0,0),'edge')
assert(not b:Move(2,0)); assert(b.position.x<=47.5)
local narrow={VOID_Y=-128,HasGround=function(x,z,margin) return not (x>.7 and x<1.3) end,
    IsSafeGround=function(x,y,z) return not (x>.7 and x<1.3) end,
    GroundHeight=function(x,z) if x>.7 and x<1.3 then return nil end return 0 end}
b=Beetle.New(nil,nil,narrow,combat,Vector3.ZERO,'gap')
assert(not b:Move(2,0)); assert(b.position.x<.7,'must not jump across a gap with safe endpoint')
assert(not b:Move(100,0) and b.blockReason=='budget')
print('PASS swept edge/footprint/gap checks and bounded movement work')

local s=Sentry.New(nil,nil,terrain,combat,Vector3.ZERO,'sentry')
combat.pos=Vector3(0,0,10); combat.hits=0
s:Update(.01,combat.pos); T.Tick(s,.42,combat.pos)
assert(s.state==S.TELEGRAPH)
T.Tick(s,.88,combat.pos); assert(not s.stones[1].active and combat.hits==0)
T.Tick(s,.03,combat.pos); assert(s.stones[1].active)
local before=s.stones[1].z
s:TickExtras(.1,combat.pos)
T.Near(math.sqrt(s.stones[1].vx^2+s.stones[1].vy^2+s.stones[1].vz^2),12)
assert(s.stones[1].z>before)
local hp=s.hp
assert(s:ApplyHit({part='stone_1',kind='sword',dmg=1}).hit)
assert(not s.stones[1].active and s.hp==hp)
s:BeginAttack(); T.Tick(s,1,combat.pos); assert(combat.hits==1)
s:ClearExtras(); assert(not s:GetHurtShapes()[3].enabled)
s:Reset(); s:Chase(.1,Vector3(0,0,4),4); assert(s.position.z<0)
print('PASS sentry 0.9 telegraph, 12m/s pooled projectile, sword interception, ranged damage, retreat')

local boss=Beast.New(nil,nil,terrain,combat,Vector3.ZERO,'boss')
assert(boss.hp==600 and boss.maxPoise==100 and #boss:GetHurtShapes()==5)
assert(not boss:ApplyHit({dmg=100,part='core'}).hit)
local a=boss:ApplyHit({dmg=40,part='foreleg_l',poise=0})
assert(a.partBroken=='foreleg_l' and not boss.down and boss.pendingTrip and boss.poise==0)
boss:Stagger(3,true)
local old=boss.hp; boss:ApplyHit({dmg=10,part='foreleg_r'}); T.Near(old-boss.hp,15)
boss:Reset(); boss:ApplyHit({dmg=70,part='back_armor'}); assert(boss.parts.back_armor.broken)
old=boss.hp; boss:ApplyHit({dmg=10,part='core'}); T.Near(old-boss.hp,16)
boss:Reset(); boss:ApplyHit({dmg=1,poise=100,part='head'}); assert(boss.down and boss.staggerDuration==3)
T.Near(boss.hp,598.4) -- head weak point, independently of the later down multiplier
boss:Reset(); boss:ApplyHit({dmg=301,part='head'}); assert(boss.phase==2 and not boss.parts.back_armor.broken)
boss:SelectAttack(); assert(boss.doubleCharge)
boss:AfterRecover(); assert(not boss.doubleCharge and boss.state==S.TELEGRAPH)
boss:SelectAttack(); boss:SelectAttack(); assert(boss.attack.telegraph==1.1*.85)
print('PASS five parts, hidden core, leg break/down 3s, down x1.5, core x1.6, poise, phase two')

boss:Reset(); boss.aggro=true; boss:SelectAttack(); boss:SetState(S.TELEGRAPH)
boss.obstacles={{x=0,z=2,radius=.5}}
combat.pos=Vector3(0,0,8)
T.Tick(boss,.61,combat.pos); assert(boss.state==S.ATTACK)
T.Tick(boss,.12,combat.pos); assert(boss.state==S.STAGGER and boss.staggerDuration==2.5)
boss.obstacles={}; boss:Reset(); boss.attack=Beast.Config.attacks[2]; boss:SetState(S.TELEGRAPH)
combat.pos=Vector3(0,0,2); combat.hits=0
T.Tick(boss,.52,combat.pos); combat.pos=Vector3(0,0,-2)
T.Tick(boss,.19,combat.pos); T.Tick(boss,.23,combat.pos); assert(combat.hits==0,'sweep cannot hit behind after aim locks')
boss:Reset(); boss.attack=Beast.Config.attacks[3]; boss:SetState(S.TELEGRAPH)
combat.pos=Vector3(0,1,2)
T.Tick(boss,1.11,combat.pos); T.Tick(boss,.23,combat.pos); assert(combat.hits==0,'jump avoids shockwave')
print('PASS charge/pillar stun 2.5s, 120 degree sweep exclusion, jump-over stomp')
boss:Reset(); boss.attack=Beast.Config.attacks[2]; boss:SetState(S.TELEGRAPH)
combat.pos=Vector3(0,0,2); combat.hits=0
T.Tick(boss,.69,combat.pos); assert(combat.hits==0)
T.Tick(boss,.3,combat.pos); assert(combat.hits==1)
boss:Reset(); boss.attack=Beast.Config.attacks[3]; boss:SetState(S.TELEGRAPH)
combat.hits=0; T.Tick(boss,1.09,combat.pos); assert(combat.hits==0)
T.Tick(boss,.3,combat.pos); assert(combat.hits==1)
print('PASS sweep/stomp positive damage cases also require completed telegraphs')

local Visual=require('combat.enemies.EnemyVisual')
for _,class in ipairs({Beetle,Sentry,Beast}) do
    local chunks,count=Visual.Sculpt(class.Config)
    assert(count>0 and count<=3000 and #chunks>1)
    for _,chunk in ipairs(chunks) do for _,cell in ipairs(chunk.cells) do assert(cell[4]>=200 and cell[4]<=239) end end
    print('PASS sculpt '..class.Config.kind..' voxels='..count..' pieces='..#chunks)
end
print('PASS enemy_logic complete')
