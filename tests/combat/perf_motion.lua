local F=dofile('tests/combat/perf_support.lua')
local S,P=F.S,F.P
local N=F.LoadNomi()
local Old=F.LoadNomi('validation/combat/sword-hitch/before/NomiController.lua.txt')
-- Baseline C.ClipSlidePath is loaded independently too (not the optimized helper).
local f=assert(io.open('validation/combat/sword-hitch/before/CombatMoves.lua.txt'));local source=f:read('*a');f:close()
local oldC=assert(load(source,'baseline Moves'))()
local original=require('combat.CombatMoves')
local distances={.04,.15,.30,.70}
for _,distance in ipairs(distances) do
    local n,c=F.Actor(N);local old,bc=F.Actor(Old)
    package.loaded['combat.CombatMoves']=oldC
    local before=old:ClipAttackMotion(Vector3(0,0,distance))
    package.loaded['combat.CombatMoves']=original
    local after=n:ClipAttackMotion(Vector3(0,0,distance))
    S.near(after.z,before.z)
    print(string.format('R10 motion %.2fm before ground=%d wall=%d total=%d after ground=%d wall=%d total=%d',distance,bc.ground,bc.wall,bc.ground+bc.wall,c.ground,c.wall,c.ground+c.wall))
    if distance==.7 then assert(c.ground+c.wall<=(bc.ground+bc.wall)*.5) end
end
for _,wall in ipairs({.43,.48,.54,.65,.91,1.1}) do
    local n=F.Actor(N,wall);local old=F.Actor(Old,wall)
    package.loaded['combat.CombatMoves']=oldC
    local before=old:ClipAttackMotion(Vector3(0,0,.7))
    package.loaded['combat.CombatMoves']=original
    local after=n:ClipAttackMotion(Vector3(0,0,.7))
    S.near(after.z,before.z)
end
for _,ground in ipairs({function(x,z)return z*.2,1/math.sqrt(1.04)end,
    function(x,z)if z>.42 and z<.59 then return nil end return 0,1 end,
    function(x,z)return z>.3 and .25 or 0,1 end}) do
    local n=F.Actor(N,nil,ground);local old=F.Actor(Old,nil,ground)
    package.loaded['combat.CombatMoves']=oldC
    local before=old:ClipAttackMotion(Vector3(0,0,.7))
    package.loaded['combat.CombatMoves']=original
    S.near(n:ClipAttackMotion(Vector3(0,0,.7)).z,before.z)
end
local n,c=F.Actor(N)
P.BeginFrame();local moved,blocked,debt=n:ClipAttackMotion(Vector3(0,0,1.9))
S.near(moved.z,.8);S.near(debt,1.1);assert(not blocked and P.substeps==8)
n.node.worldPosition=moved
P.BeginFrame();local more,_,rest=n:ClipAttackMotion(Vector3(0,0,debt));S.near(more.z,.8);S.near(rest,.3)
n.node.worldPosition=n.node.worldPosition+more
local last=n:ClipAttackMotion(Vector3(0,0,rest));S.near(moved.z+more.z+last.z,1.9)
local groundBefore=c.ground;n:ClipAttackMotion(Vector3(0,0,.1));assert(c.ground>groundBefore,'new synchronous scope cannot reuse old ground')
print('PASS 9-point footprint/<=.10m segments/wall binary/slope/step/void parity; eight-substep cap and lossless debt')
local external=c.ground
n:SlideGround(Vector3.ZERO);n:SlideGround(Vector3.ZERO)
assert(c.ground==external+2,'standalone dust/ground reads cannot reuse stale scope records')
-- Real Moves consumes the third motion return without losing debt or leaking it
-- into a replacement action. Animation remains the only event clock.
local C=require('combat.CombatMoves');local A=require('combat.CombatAnim');local State=require('combat.CombatState')
local rig={pose='hand',SetActive=function()end,SetPose=function()end,GetStats=function()return {attack=10,speed=1,reach=1}end}
State.Configure{rig=rig};State.Enter();State.FinishTransition();State.Activity(true)
local actor=F.Actor(N)
local m=C.New{anim=A.New(S.anim.character(),nil),state=State,rig=rig,
 position=function()return actor.node.worldPosition end,forward=function()return Vector3.FORWARD end,
 attackMotion=function(v)return actor:ClipAttackMotion(v)end}
assert(m:Play('sword_light_1'));m.motionDebt=1.9
m:Update(.001,{allowed=true});S.near(m.motion.z,.8);assert(m.motionDebt>1)
actor.node.worldPosition=actor.node.worldPosition+m.motion
m.hitstop=1;local held=m.motionDebt;m:Update(.1,{allowed=true});S.near(m.motion.z,0);S.near(m.motionDebt,held)
m:Cancel('test');assert(m.motionDebt==0);m:Update(.016,{allowed=true});S.near(m.motion.z,0)
print('PASS actual Moves motion debt, hitstop freeze, cancellation clears outstanding impulse')
