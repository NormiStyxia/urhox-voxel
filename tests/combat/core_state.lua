-- Lua 5.4 offline; no runtime or rendering. Stub enemies report aggro heartbeats.
package.path='scripts/?.lua;'..package.path
local State=require('combat.CombatState')
local calls,cancelled={},{}
local rig={}
function rig:SetActive(w) self.weapon=w end
function rig:SetPose(p) self.pose=p; calls[#calls+1]=p end
function rig:GetHit() return {origin={x=0,y=1,z=0},dir={x=0,y=0,z=1},length=1,radius=.12} end
function rig:GetStats() return {attack=10,speed=1,reach=1,poise=6} end
function rig:Update() end
local function reset()
    State.Configure({rig=rig,cancel=function(reason) cancelled[#cancelled+1]=reason end})
end
local function eq(actual,expected) assert(actual==expected,tostring(actual)..' ~= '..tostring(expected)) end
reset()
eq(State.Get(),'EXPLORE');eq(State.CanUseTime(),true);eq(State.Glow(),1);eq(rig.pose,'hidden')
State.Enter('manual')
eq(State.Get(),'COMBAT_IDLE');eq(State.CanUseTime(),false);eq(State.Glow(),0);eq(rig.pose,'back')
eq(State.Activity(),false) -- draw transition cannot be bypassed by ordinary attack
eq(State.Activity(true),true) -- dodge is the explicit cancellation exception
eq(rig.pose,'hand');eq(State.Get(),'COMBAT_ACTIVE')
State.Update(2.49);eq(State.Get(),'COMBAT_ACTIVE')
State.Update(.02);eq(State.Get(),'COMBAT_IDLE');eq(rig.pose,'back')
State.Update(3.50);eq(State.Get(),'EXPLORE');eq(State.CanUseTime(),false);eq(rig.pose,'hidden')
State.Update(.4);eq(State.Glow(),0);eq(State.CanUseTime(),false)
State.Update(.61);eq(State.CanUseTime(),true)
eq(State.ReadyFlash(),true);State.Update(.4);eq(State.Glow(),1)

reset()
local enemy={id='stub',alive=true}
function enemy:Update() if self.alive then State.OnEnemyAggro(self.id) end end
for _=1,80 do enemy:Update();State.Update(.1) end
eq(State.Get(),'COMBAT_IDLE') -- heartbeat prevents premature 6s exit
enemy.alive=false
State.Update(5.8);eq(State.InCombat(),true)
State.OnPlayerHit();State.Update(5.9);eq(State.InCombat(),true)
State.Update(.11);eq(State.InCombat(),false)

reset();State.Enter('manual');State.Update(.31);State.Activity();State.SetBusy(true)
State.Update(10);eq(State.Get(),'COMBAT_ACTIVE')
State.SetBusy(false);State.Update(.01);eq(State.Get(),'EXPLORE')

reset();State.Enter('manual');State.SetMounted(true)
eq(State.Get(),'EXPLORE');eq(rig.pose,'hidden');eq(State.Glow(),0)
eq(State.Enter('manual'),false);State.OnEnemyAggro('stub');eq(State.Get(),'EXPLORE')
State.SetMounted(false);State.Update(1.1);eq(State.CanUseTime(),true)
State.SetDead(true);eq(State.Enter('hit'),false);eq(State.CanUseTime(),false)
State.SetDead(false);State.Update(1);eq(State.CanUseTime(),true)

reset();State.Enter('manual');eq(State.SetWeapon('bow'),false)
State.Update(.31);eq(State.SetWeapon('bow'),true);eq(rig.weapon,'bow');eq(rig.pose,'back')
eq(State.Activity(),false);State.Update(.41);eq(State.Activity(),true)
State.Exit('manual');eq(cancelled[#cancelled],'manual');eq(State.CanUseTime(),false)
State.Stop();eq(State.Get(),'EXPLORE');eq(rig.pose,'hidden')
State.Configure{rig=rig,aggro=function() return true end}
State.OnEnemyAggro('enemy');eq(State.Exit('manual'),false);eq(State.InCombat(),true)
State.SetMounted(true);eq(State.InCombat(),false)
print('PASS core_state: visibility, draw/dodge gate, 2.5s back, 6s quiet/aggro/hit, 1s spell delay, mount/death, swap, cancellation')
local logs={}
State.Configure{log=function(line) logs[#logs+1]=line end}
State.Enter('manual');State.Enter('manual')
eq(#logs,1);assert(logs[1]:find('EXPLORE->COMBAT_IDLE manual',1,true))
for i=1,100 do State.Log('same','same') end
eq(#logs,2)
for i=1,100 do State.Log('burst'..i,'burst') end
eq(#logs,48)
State.Update(1);State.Log('same','same');eq(#logs,49)
print('PASS bounded event logs: actual state changes only, duplicate guard and 48 lines/sec ceiling')
