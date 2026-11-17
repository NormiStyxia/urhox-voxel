-- Combat stamina: sprint drain, exhausted lock, regen delay, heavy/plunge costs.
local S=dofile('tests/combat/core_support.lua')
local A=require('combat.CombatAnim')
local State=require('combat.CombatState')
local C=require('combat.CombatMoves')
local St=require('combat.Stamina')
-- 1) Pure model.
local s=St.New();assert(s.value==100 and not s.exhausted)
for _=1,100 do s:Update(.01,true,true) end
S.near(s.value,100-St.SPRINT_RATE,1e-6)
for _=1,100 do s:Update(.01,false,true) end
S.near(s.value,100,1e-6) -- out of combat: sprint is free and the bar refills
s=St.New();while not s.exhausted do s:Update(.01,true,true) end
assert(s.value==0 and not s:CanSprint(),'empty bar locks sprint')
local before=s.value;s:Update(St.REGEN_DELAY-.05,true,false);assert(s.value==before,'regen waits for the delay')
local t=0
while s.exhausted do s:Update(.01,true,false);t=t+.01 end
assert(s.value>=30-1e-6 and s.value<31,'lock lifts at 30%')
assert(s:Spend('heavy') and not s:Spend('heavy'),'30% pays one cross slash, not two')
s=St.New();assert(s:Spend('heavy') and s:Spend('heavy') and s:Spend('heavy') and s:Spend('heavy'))
assert(not s:Spend('plunge') and s.exhausted,'four cross slashes empty the bar')
-- 2) Moves own the bar: exhausted sprint intent is refused in combat.
local rig={SetActive=function()end,SetPose=function()end,GetStats=function()return {attack=10,speed=1,reach=1,poise=6}end}
State.Configure{rig=rig};State.Enter();State.FinishTransition();State.Activity(true)
local running,cancelled=false,0
local foot={Begin=function()end,Finish=function(_,_,c)end,IsRunning=function()return running end,
    Cancel=function()running=false;cancelled=cancelled+1 end}
local m=C.New{anim=A.New(S.anim.character(),nil),state=State,rig=rig,locomotion=foot,
    forward=function()return Vector3.FORWARD end,position=function()return Vector3.ZERO end,enemies=function()return {}end}
running=true
local controls={allowed=true,runIntent=true}
for _=1,200 do controls.runIntent=true;m:Update(.05,controls) ;if running==false then break end end
assert(m.stamina.exhausted and cancelled==1 and controls.runIntent==false,'empty bar stops combat sprint')
controls.runIntent=true;m:Update(.05,controls);assert(controls.runIntent==false,'intent refused while exhausted')
-- 3) Plunge pays 20; without it the air press does nothing.
local air={onGround=false,height=2,y=3}
m=C.New{anim=A.New(S.anim.character(),nil),state=State,rig=rig,airState=function()return air end,
    forward=function()return Vector3.FORWARD end,position=function()return Vector3.ZERO end,enemies=function()return {}end}
assert(m:Action('light') and m.plunging);S.near(m.stamina.value,80,1e-6)
m:Cancel('test');State.SetBusy(false);State.Activity(true)
m.stamina.value=15
assert(not m:Action('light') and not m.plunging,'no stamina, no plunge')
assert(m.stamina.denyAt==m.stamina.clock,'refusal flashes the bar')
print('PASS stamina: sprint drain/exhaust lock/regen delay, cross slash and plunge costs, refusal flash')
