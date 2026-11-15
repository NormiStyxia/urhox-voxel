local S=dofile('tests/combat/core_support.lua')
local State=require('combat.CombatState')
local C=require('combat.CombatMoves')
local A=require('combat.CombatAnim')
local Camera=require('combat.CombatCamera')
local m,rig,starts,poses,shots
local function New(weapon)
 m=nil;starts={};poses={};shots=0
 rig={pose='hidden',active=weapon or 'sword',SetActive=function(self,w)self.active=w end,
 SetPose=function(self,p) if self.pose~=p then poses[#poses+1]=p end;self.pose=p end,
 SetTrail=function()end,GetStats=function()return {attack=10,speed=1,draw=.7,reach=1}end}
 State.Configure{rig=rig,weapon=weapon,log=function()end,cancel=function(reason)if m then m:Cancel(reason)end end}
 State.Enter('manual');State.FinishTransition()
 m=C.New{anim=A.New(S.anim.character(),nil),rig=rig,state=State,
 forward=function()return Vector3.FORWARD end,position=function()return Vector3.ZERO end,
 fire=function()shots=shots+1 end,aimPitch=function()return 24 end}
 m.observe=function(kind,e)if kind=='start' then starts[#starts+1]=e.clip end end
end
local function tick(dt,input)
 input=input or {allowed=true}
 m:Update(dt,input)
 local p,pitch=m:BowParameters(-10)
 m.anim:SetParam('p',p);m.anim:SetParam('aimPitch',pitch)
 m.anim:SetParam('weaponInHand',m:WeaponInHand() and 1 or 0)
 m:AfterPose();State.Update(dt)
end
local function frames(n,input)for _=1,n do tick(.01,input) end end
local function untilTrue(fn)
 for _=1,200 do if fn() then return end;tick(.01) end
 error('timed out waiting for clip/event')
end
local function count(id)local n=0;for _,s in ipairs(starts)do if s==id then n=n+1 end end;return n end
New();assert(rig.pose=='back' and State.GetPose()=='back')
frames(20,{allowed=true,axis=Vector3.RIGHT});assert(rig.pose=='back' and not m.anim:IsPlaying('stance_combat'))
tick(.01,{allowed=true,runIntent=true,axis=Vector3.RIGHT});frames(60)
assert(rig.pose=='back' and count('sword_draw')==0,'run never draws')
New();tick(.01,{allowed=true,attackTap=true})
untilTrue(function()return m.clip=='sword_light_1' and m.cancelOpen end)
tick(.01,{allowed=true,attackTap=true});assert(m.clip=='sword_light_2')
untilTrue(function()return m.clip=='sword_light_2' and m.cancelOpen end)
tick(.01,{allowed=true,attackTap=true});assert(m.clip=='sword_light_3')
untilTrue(function()return not m.clip end)
assert(count('sword_draw')==1 and count('sword_light_1')==1 and count('sword_light_2')==1 and count('sword_light_3')==1)
assert(rig.pose=='hand');frames(37);assert(rig.pose=='hand','grace starts after recovery')
frames(4);assert(rig.pose=='back' and State.TransitionRemaining()==0 and not m.clip)
-- New input during the Rig-only return flight: no sheath clip, no busy lock.
tick(.01,{allowed=true,attackTap=true});assert(m.clip=='sword_draw')
untilTrue(function()return m.clip=='sword_light_1' end)
assert(count('sword_draw')==2 and count('sword_light_1')==2 and count('sword_sheath')==0)
untilTrue(function()return m.cancelOpen end)
untilTrue(function()return not m.clip end);frames(42);assert(rig.pose=='back')
-- A late input at the final recovery boundary consumes once (not dropped by stow).
New();State.Activity(true);assert(m:Action('light'));frames(29)
tick(.01,{allowed=true,attackTap=true});frames(45)
assert(count('sword_light_2')==1 and count('sword_draw')==0)
-- Q hides before switching, stays hidden through stowed event, then target back.
New();assert(m:Swap());assert(rig.active=='bow' and rig.pose=='hidden')
frames(18);assert(rig.pose=='hidden');frames(23)
assert(State.GetWeapon()=='bow' and rig.pose=='back' and not m.clip)
assert(m:Swap());frames(41)
assert(rig.active=='sword' and rig.pose=='back','swap cancel never resurrects old hand weapon')
-- Late buffered attack after swap selects target weapon once, then bow_draw.
New();assert(m:Swap());frames(30);tick(.01,{allowed=true,attack=true});frames(58,{allowed=true,attack=true})
assert(count('bow_equip')==0 and count('bow_draw')==1 and m.clip=='bow_hold' and rig.active=='bow')
-- Form boundaries prevent stale animation events from bringing a weapon back.
for _,reason in ipairs({'manual','quiet','mount','death','stop'}) do
 New('bow');State.Activity(true);m:Action('hold');frames(25,{allowed=true,attack=true})
 assert(m.charge>0)
 if reason=='mount' then State.SetMounted(true) elseif reason=='death' then State.SetDead(true) else State.Exit(reason) end
 assert(rig.pose=='hidden' and State.GetPose()=='hidden' and not m.pendingFire)
 frames(65,{allowed=false});assert(rig.pose=='hidden' and shots==0 and not m.anim:IsPlaying('stance_combat'))
 State.SetMounted(false);State.SetDead(false);frames(10);assert(rig.pose=='hidden','unmount/revive never revives old weapon')
end
for _,reason in ipairs({'menu','focus','touch-clear'}) do
 New('bow');State.Activity(true);m:Action('hold');frames(40,{allowed=true,attack=true})
 local p=m.charge;m:Cancel(reason);assert(m.charge==0)
 frames(10,{allowed=false});local saved,pitch=m:BowParameters(0);S.near(saved,p);S.near(pitch,24)
 frames(50,{allowed=false});assert(shots==0 and rig.pose=='back')
end
local f=assert(io.open('scripts/ruins/RuinsScene.lua'));local src=f:read('*a');f:close()
assert(not src:find("pose=function(p,previous)",1,true),'no Scene back callback that resurrects hand')
assert(src:find("'weaponInHand',combatMoves_:WeaponInHand() and 1 or 0",1,true))
assert(src:find("params.weaponInHand=params.weaponInHand==1 and 0 or 1",1,true),'F7 explicit hand/back preview control')
local cam=Camera.New();S.near(cam:Update(.1,{},true,true).focus:Length(),0)
local base
for line in src:gmatch('[^\n]+')do if line:find("Safe('Animation.Base'",1,true)then base=line;break end end
assert(base)
local armed
local env=setmetatable({M={ride={mode='free'}},dt=.016,nomi_={Animate=function()end},
 caster_={charging=false,castAnim=0},combatMoves_={hitstop=0,WeaponInHand=function()return false end},
 Safe=function(_,fn,obj,dt,value)armed=value end},{__index=_G})
assert(load(base,'actual Scene base armed routing','t',env))();assert(armed==false)
env.combatMoves_.WeaponInHand=function()return true end
assert(load(base,'actual Scene base armed routing','t',env))();assert(armed==true)
print('PASS stow/run ownership, grace, combo, swap, bow cancellation, base armed routing')
