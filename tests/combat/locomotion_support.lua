local S=dofile('tests/combat/core_support.lua')
local A=require('combat.CombatAnim')
local State=require('combat.CombatState')
local Moves=require('combat.CombatMoves')
local F=require('ruins.FootLocomotion')
local stats={attack=10,speed=1,reach=1,draw=.7,poise=6}
local rig={SetActive=function()end,SetPose=function()end,GetStats=function()return stats end}
local function New(combat)
    State.Configure{rig=rig}
    if combat then State.Enter();State.Update(.31);State.Activity(true) end
    local foot=F.New()
    local character=S.anim.character()
    local m=Moves.New{anim=A.New(character,nil),state=State,rig=rig,locomotion=foot,
        forward=function()return Vector3.FORWARD end,position=function()return Vector3.ZERO end,
        enemies=function()return {} end}
    return m,foot,character
end
local function Tick(m,dt,c)
    c=c or {};if c.allowed==nil then c.allowed=true end
    if c.onGround==nil then c.onGround=true end
    if c.axis==nil then c.axis=Vector3.FORWARD end
    m:Update(dt,c)
    return m.motion:Length()
end
return {New=New,Tick=Tick,F=F,near=S.near,State=State,Anim=A,Mock=S.anim}
