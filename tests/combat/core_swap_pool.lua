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
State.Configure{rig=rig,log=function()end}
State.Enter('test');State.FinishTransition()
local clips={}
local anim={Play=function(_,id)clips[#clips+1]=id;return #clips end,Stop=function()end,Poll=function()return {}end}
local moves=Moves.New{state=State,rig=rig,anim=anim,position=function()return Vector3.ZERO end}
local created,writes,rebuilds=world.created,world.writes,world.rebuilds
local oldBuild,oldCompile=Builder.Build,Builder.Compile
Builder.Build=function()error('switch unexpectedly builds')end
Builder.Compile=function()error('switch unexpectedly compiles')end
for _=1,50 do
    moves.clip=nil;State.SetBusy(false);State.FinishTransition()
    assert(moves:Swap())
    -- The authored stow event commits the desired weapon later in the clip.
    rig:SetActive(State.GetWeapon());rig:SetPose('back')
    for _=1,24 do rig:Update(1/60)end
end
Builder.Build,Builder.Compile=oldBuild,oldCompile
assert(#clips==50 and clips[1]=='weapon_swap_sword_to_bow' and clips[2]=='weapon_swap_bow_to_sword')
assert(world.created==created and world.writes==writes and world.rebuilds==rebuilds,'50 swaps preserve native pool/build counts')
rig:Dispose()
print('PASS 50 actual Moves/State/Rig switches: 0 Build/Compile/CreateVolume/grid-write/rebuild delta')
