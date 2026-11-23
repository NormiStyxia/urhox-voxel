-- Actual Moves -> State -> Rig switch path; only native nodes/volumes and
-- animation output are adapters. No geometry/volume build may happen here.
package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('weapon_mock')
local Rig=require('combat.WeaponRig')
local Builder=require('combat.WeaponBuilder')
local State=require('combat.CombatState')
local Moves=require('combat.CombatMoves')
local scene=Mock.Node('scene')
local world=Mock.World(scene)
local nomi=Mock.Nomi(scene)
local rig=Rig.New(scene,world,nomi)
local moves
-- Match the scene's cancellation callback, not just the direct Swap call.
State.Configure{rig=rig,explicitSelection=true,log=function()end,
    cancel=function(reason)if moves then moves:Cancel(reason)end end}
State.Enter('test');State.FinishTransition()
local stops,trailClears=0,0
local stop,clearTrail=rig.StopCombatVisual,rig.ClearTrail
function rig:StopCombatVisual()stops=stops+1;return stop(self)end
function rig:ClearTrail()trailClears=trailClears+1;return clearTrail(self)end
rig:SetPose('hand');stops,trailClears=0,0
rig:SetPose('hidden')
assert(stops==1 and trailClears==1,'changed hidden pose tears down exactly once')
local motion=rig.transition
rig:SetPose('hidden')
assert(stops==2 and trailClears==2 and rig.transition==motion,'repeated hidden still clears without restarting dissolve')
State.Configure{rig=rig,explicitSelection=true,log=function()end,
    cancel=function(reason)if moves then moves:Cancel(reason)end end}
State.Enter('test');State.FinishTransition()
local clips={}
local anim={Play=function(_,id)clips[#clips+1]=id;return #clips end,Stop=function()end,Poll=function()return {}end}
moves=Moves.New{state=State,rig=rig,anim=anim,position=function()return Vector3.ZERO end}
local created,writes,rebuilds=world.created,world.writes,world.rebuilds
local oldBuild,oldCompile=Builder.Build,Builder.Compile
Builder.Build=function()error('switch unexpectedly builds')end
Builder.Compile=function()error('switch unexpectedly compiles')end
for _=1,50 do
    moves.clip=nil;State.SetBusy(false);State.FinishTransition()
    local beforeStops,beforeTrails=stops,trailClears
    assert(moves:Swap())
    assert(stops-beforeStops==8 and trailClears-beforeTrails==8,'callback-inclusive swap: one trail clear per teardown, no duplicate hidden teardown')
    assert(State.TransitionRemaining()==.4,'gameplay swap lock unchanged')
    assert(rig.pose=='hidden' and rig.active==State.GetWeapon(),'selected target remains hidden during Q lock')
    local old=rig.active=='sword' and 'bow' or 'sword'
    assert(not rig.entries[old].mesh.node.enabled,'old mesh cannot be resurrected by Cancel/swap')
    for _,layer in ipairs(rig.layers[old]) do assert(not layer.node.enabled)end
    rig:Update(.18)
    assert(rig.pose=='hidden' and not rig.entries[rig.active].mesh.node.enabled)
    State.FinishTransition();assert(rig.pose=='back')
    for _=1,24 do rig:Update(1/60)end
end
assert(#clips==50 and clips[1]=='weapon_swap_sword_to_bow' and clips[2]=='weapon_swap_bow_to_sword')
-- Numeric/Tab/C adapters converge on SelectLoadout. Time keeps its existing
-- casting mode and never requests a third rig model or rebuilds either weapon.
moves.clip=nil;State.SetBusy(false);State.FinishTransition()
assert(moves:SelectLoadout('bow'));moves.clip=nil;State.SetBusy(false);State.FinishTransition()
State.Activity(true)
moves.clip,moves.charge,moves.pendingFire='bow_hold',.85,{u=.85}
moves.hitPending=true;rig:SetBowDraw(.85)
assert(moves:SelectLoadout('time'))
assert(State.GetSelection()=='time' and rig.pose=='hidden' and State.CanUseTime())
assert(not moves.pendingFire and not moves.hitPending and moves.charge==0 and rig.bowDraw==0,'charged bow to time discards pending attacks')
for _,target in ipairs({'sword','bow','sword'}) do
    assert(moves:SelectLoadout(target))
    assert(State.GetSelection()==target and rig.active==target)
    State.FinishTransition();assert(rig.pose=='back')
    for _=1,24 do rig:Update(1/60)end
    moves.clip=nil;State.SetBusy(false)
    assert(moves:SelectLoadout('time') and rig.pose=='hidden')
    local beforeStops=stops
    assert(moves:SelectLoadout('time') and stops==beforeStops,'confirming time remains a no-op')
end
Builder.Build,Builder.Compile=oldBuild,oldCompile
assert(world.created==created and world.writes==writes and world.rebuilds==rebuilds,'weapon/time switches preserve native pool/build counts')
-- Boundary teardown also clears pending visual work; later Update cannot revive it.
for _,reason in ipairs({'manual','mount','death','stop'}) do
    State.SetMounted(false);State.SetDead(false);State.Enter('test');State.FinishTransition();State.Activity(true)
    for _=1,12 do rig:Update(1/60)end
    if reason=='mount' then State.SetMounted(true) elseif reason=='death' then State.SetDead(true) else State.Exit(reason)end
    for _=1,60 do rig:Update(1/60)end
    assert(rig.pose=='hidden')
    for _,entry in pairs(rig.entries)do assert(not entry.mesh.node.enabled)end
    for _,band in ipairs(rig.trails)do assert(not band.node.enabled)end
    for _,ghost in ipairs(rig.images)do assert(not ghost.node.enabled)end
    for _,ghost in ipairs(rig.bowImages)do assert(not ghost.node.enabled)end
    assert(not rig.bowArrow.node.enabled)
end
rig:Dispose()
print('PASS 50 actual Moves/State/Rig switches: 0 Build/Compile/CreateVolume/grid-write/rebuild delta')
