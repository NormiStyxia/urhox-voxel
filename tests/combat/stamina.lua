-- Combat stamina: sprint drain, exhausted lock, regen delay, heavy cost.
local S=dofile('tests/combat/core_support.lua')
local A=require('combat.CombatAnim')
local State=require('combat.CombatState')
local C=require('combat.CombatMoves')
local St=require('combat.Stamina')
-- 1) Pure model.
local s=St.New();assert(s.value==100 and not s.exhausted)
for _=1,100 do s:Update(.01,true,true) end
S.near(s.value,100-St.SPRINT_RATE,1e-6)
s=St.New()
for _=1,100 do s:Update(.01,false,true) end
S.near(s.value,100-St.SPRINT_RATE,1e-6) -- sprint drains outside combat too
s:Update(St.REGEN_DELAY-.05,false,false);S.near(s.value,100-St.SPRINT_RATE,1e-6) -- explore regen waits for the delay
for _=1,100 do s:Update(.01,false,false) end
S.near(s.value,100,1e-6) -- then the bar refills
s=St.New();for _=1,500 do s:Update(.01,false,false) end;S.near(s.value,100,1e-6) -- plain running costs nothing
s=St.New();while not s.exhausted do s:Update(.01,true,true) end
assert(s.value==0 and not s:CanSprint(),'empty bar locks sprint')
local before=s.value;s:Update(St.REGEN_DELAY-.05,true,false);assert(s.value==before,'regen waits for the delay')
local t=0
while s.exhausted do s:Update(.01,true,false);t=t+.01 end
assert(s.value>=30-1e-6 and s.value<31,'lock lifts at 30%')
assert(s:Spend('heavy') and not s:Spend('heavy'),'30% pays one cross slash, not two')
s=St.New();assert(s:Spend('heavy') and s:Spend('heavy') and s:Spend('heavy') and s:Spend('heavy'))
assert(not s:Spend('heavy') and s.exhausted,'four cross slashes empty the bar')
-- 2) Moves own the bar: exhausted sprint intent is refused in combat.
local rig={SetActive=function()end,SetPose=function()end,GetStats=function()return {attack=10,speed=1,reach=1,poise=6}end}
State.Configure{rig=rig};State.Enter();State.FinishTransition();State.Activity(true)
local running,cancelled=false,0
local foot={Begin=function()end,Finish=function(_,_,c)end,IsRunning=function()return running end,
    IsSprinting=function()return running end,
    Cancel=function()running=false;cancelled=cancelled+1 end}
local m=C.New{anim=A.New(S.anim.character(),nil),state=State,rig=rig,locomotion=foot,
    forward=function()return Vector3.FORWARD end,position=function()return Vector3.ZERO end,enemies=function()return {}end}
running=true
local controls={allowed=true,runIntent=true,sprintIntent=true}
for _=1,200 do controls.runIntent,controls.sprintIntent=true,true;m:Update(.05,controls);if m.stamina.exhausted then break end end
assert(m.stamina.exhausted and controls.sprintIntent==false,'empty bar refuses the sprint')
assert(controls.runIntent==true and cancelled==0,'exhausted sprint falls back to a run, never stops it')
controls.sprintIntent=true;m:Update(.05,controls);assert(controls.sprintIntent==false,'intent refused while exhausted')
-- 3) Removed/unknown costs cannot consume stamina, delay regen or flash the HUD.
for _,empty in ipairs({false,true}) do
 s=St.New();s.value=empty and 0 or 65;s.exhausted=empty
 local value,idle,shown,deny=s.value,s.idle,s.shownAt,s.denyAt
 assert(St.COST.plunge==nil and not s:Spend('plunge') and not s:Spend('unknown'))
 assert(s.value==value and s.idle==idle and s.shownAt==shown and s.denyAt==deny)
end
-- An exhausted aerial light still follows the ordinary free-light rule.
m=C.New{anim=A.New(S.anim.character(),nil),state=State,rig=rig,
    airState=function()error('ordinary attacks must not request fall control')end,
    forward=function()return Vector3.FORWARD end,position=function()return Vector3.ZERO end,enemies=function()return {}end}
m.stamina.value,m.stamina.exhausted=0,true
assert(m:Action('light') and m.clip=='sword_light_1')
assert(m.stamina.value==0 and m.stamina.denyAt==-99,'ordinary air light has no removed cost or refusal flash')
print('PASS stamina: sprint drain/exhaust lock/regen delay, cross slash cost, removed cost has no side effects, exhausted air light')
