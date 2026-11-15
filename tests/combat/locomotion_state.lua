local S=dofile('tests/combat/locomotion_support.lua')
for _,combat in ipairs({false,true}) do
 local m,f=S.New(combat)
 for _,dt in ipairs({.01,.24,.52,1}) do
  S.Tick(m,dt,{runIntent=true,actualSpeed=7.2})
  assert(f:IsRunning() and not m.clip and m:MoveScale()==1)
  assert(S.State.InCombat()==combat,'running cannot enter combat')
 end
 S.Tick(m,.01,{runIntent=false});assert(not f:IsRunning())
 S.Tick(m,.01,{runIntent=true,allowed=false});assert(not f:IsRunning())
 S.Tick(m,.01,{runIntent=true,mounted=true});assert(not f:IsRunning())
 S.Tick(m,.01,{runIntent=true,onGround=false});assert(not f:IsRunning())
 S.Tick(m,.01,{runIntent=true,axis=Vector3.ZERO});assert(not f:IsRunning())
 assert(m:ApplyHit{dmg=10,dir=Vector3.FORWARD}.hit,'running supplies no damage protection')
end
local m,f=S.New(true)
S.Tick(m,.1,{runIntent=true,actualSpeed=7.2});assert(f:IsRunning())
S.Tick(m,.01,{runIntent=true,attackTap=true})
assert(m.clip=='sword_light_1' and not f:IsRunning() and f.weight==0 and m:MoveScale()==0)
-- Fixed tables, no per-frame state allocation in the pure intent helper.
local params=f.animOpts.params
m:Cancel('test');m.blocked=false
for _=1,10 do S.Tick(m,.01,{runIntent=true,actualSpeed=7.2}) end
local input={runIntent=true,allowed=true,onGround=true,actualSpeed=7.2,axis=Vector3.FORWARD,travel=0}
collectgarbage('collect');collectgarbage('stop');local before=collectgarbage('count')
for _=1,100 do f:Finish(.01,input,m) end
local bytes=(collectgarbage('count')-before)*1024;collectgarbage('restart')
assert(bytes<256 and params==f.animOpts.params)
print('PASS ordinary held run both modes, release/gates/air, no immunity, attack priority, stable pose buffers')
