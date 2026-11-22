-- Jump cancels every light stage on the same frame, then movement is free.
local S=dofile('tests/combat/core_support.lua')
local A=require('combat.CombatAnim')
local State=require('combat.CombatState')
local C=require('combat.CombatMoves')
local D=require('combat.AnimClips')
local rig={SetActive=function()end,SetPose=function()end,GetStats=function()return {attack=10,speed=1,reach=1,poise=6}end}
local function New()
    State.Configure{rig=rig};State.Enter();State.FinishTransition();State.Activity(true)
    return C.New{anim=A.New(S.anim.character(),nil),state=State,rig=rig,
        forward=function()return Vector3.FORWARD end,position=function()return Vector3.ZERO end,enemies=function()return {}end}
end
for stage,row in ipairs(D.Combo) do
    local clip=D.Clips[row.id]
    for _,at in ipairs({.02,clip.phases.active[1]+.01,clip.dur-.05}) do
        local m=New();m.combo=stage-1;assert(m:Action('light') and m.clip==row.id)
        m:Update(at,{allowed=true});assert(m.clip==row.id)
        m:Update(.01,{allowed=true,jump=true,onGround=true})
        assert(m.clip==nil and not m.hitOpen and m:MoveScale()==1,'jump frees movement on the same frame')
        assert(m.motion:Length()==0,'no leftover lunge after the cancel')
    end
end
-- Heavy release and charge are committed; jump does not cancel them.
local m=New();assert(m:Action('heavy'));m:Update(.05,{allowed=true,jump=true,onGround=true})
assert(m.clip=='sword_heavy_release')
-- In the air, jump has no effect on the ordinary light attack.
m=New();m.o.airState=function(out)out.onGround,out.height,out.y=false,2,2;return out end
assert(m:Action('light') and m.clip=='sword_light_1')
m:Update(.01,{allowed=true,jump=true,onGround=false});assert(m.clip=='sword_light_1')
print('PASS jump cancels all five light stages at start/active/recovery; heavy stays committed; airborne light uses ordinary rules')
