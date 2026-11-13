local S=dofile('tests/combat/core_support.lua')
local A=require('combat.CombatAnim')
local C=require('combat.CombatMoves')
local T=require('combat.CombatTest')
local State=require('combat.CombatState')
local P=require('combat.Projectile')
-- F7 passes normalized snapshot direction and fixed draw p, even while paused.
local anim=A.New(S.anim.character(),nil)
C.SeekPreview(anim,'dodge_slide',.12,0,{moveX=-1,moveZ=0,bow=1,p=.4})
assert(anim.tracks[1].params.moveX==-1 and anim.tracks[1].params.bow==1)
C.SeekPreview(anim,'bow_hold',.2,0,{p=.7})
assert(anim.tracks[1].params.p==.7)
local function Run(hits,abort,fps)
    local position=Vector3.ZERO
    local dummy=C.NewTrainingDummy(Vector3(0,0,1.2))
    local logs,cleaned={},0
    local rig={SetActive=function()end,SetPose=function()end,
        GetStats=function()return {attack=10,speed=1,draw=.7,reach=1,poise=6}end,
        GetHit=function()return {origin=position+Vector3(0,1,0),dir=Vector3.FORWARD,length=2,radius=.12}end}
    State.Configure{rig=rig};State.Enter();State.FinishTransition();State.Activity(true)
    local runner,arrows
    local m=C.New{anim=A.New(S.anim.character(),nil),state=State,rig=rig,
        position=function()return position end,forward=function()return Vector3.FORWARD end,
        enemies=function()return hits and {dummy} or {}end,
        slideStart=function()return true end,slideMotion=function(v)return v,false end,
        fire=function(charge,stats)
            local _,p=arrows:Fire(position+Vector3(0,1,0),Vector3.FORWARD,charge,stats)
            runner:Arrow(p)
        end}
    arrows=P.New{enemies=function()return hits and {dummy} or {}end,hit=function(...)m:Feedback(...)end}
    runner=T.New{moves=m,dummy=dummy,position=function()return position end,direction=function(v)return v end,
        log=function(line)logs[#logs+1]=line end,
        prepare=function(step)
            position=Vector3.ZERO;arrows:Clear();State.SetBusy(false);State.FinishTransition()
            State.SetWeapon(step.weapon);State.FinishTransition();State.Activity(true);m.dodgeCool=0;return true
        end,
        cleanup=function()cleaned=cleaned+1;arrows:Clear()end}
    local frames=0
    while runner.active and frames<4000 do
        frames=frames+1
        local dt=1/(fps or 60)
        local input=runner:Input(dt,true)
        m:Update(dt,input or {allowed=false});position=position+m.motion
        m:AfterPose();arrows:Update(dt);State.Update(dt)
        if abort and frames==30 then runner:Stop('key') end
    end
    assert(not runner.active and cleaned==1 and m.observe==nil)
    runner:Stop('again');assert(cleaned==1,'cleanup must be idempotent')
    assert(not m.lastAttack and not m.lastHeavy and not m.pendingFire and not m.buffer)
    if not abort then
        assert(runner.index==14,'all thirteen cases execute')
        local text=table.concat(logs,'\n')
        assert(text:find('sword_light_1 '..(hits and 'PASS' or 'FAIL'),1,true))
        assert(text:find('arrow_cancel PASS',1,true),'cancel test must actually draw/cancel')
        if hits then
            assert(runner.failed==0,text)
        else assert(runner.failed>=8,'hit_on without settlement cannot pass damage tests') end
    end
    return logs
end
Run(true,false);Run(true,false,30);Run(false,false);Run(true,true)
-- A blocked/focus/menu frame aborts without generating a release shot.
local cancel=0
local m={Cancel=function()cancel=cancel+1 end}
local t=T.New{moves=m,cleanup=function()end,log=function()end}
assert(t:Input(.02,false)==nil and not t.active and cancel==1)
print('core_selftest PASS: actual input/event/settlement observations, missing-hit failure, abort cleanup, F7 params')
