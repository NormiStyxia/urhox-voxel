-- Selection owns the mode; enemy alerts and idle time never choose for the player.
local S=dofile('tests/combat/core_support.lua')
local State=require('combat.CombatState')
local C=require('combat.CombatMoves')
local A=require('combat.CombatAnim')
local Input=require('ui.TouchInput')
local rig={pose='hidden',active='sword',SetPose=function(self,p)self.pose=p end,
    SetActive=function(self,id)assert(id=='sword' or id=='bow','time is not a rig model');self.active=id end,
    GetStats=function()return {attack=10,poise=6,speed=1,draw=.7,reach=1}end}
local moves,shots,aggro
local function new()
    moves=nil;shots=0;aggro=true
    State.Configure{rig=rig,explicitSelection=true,aggro=function()return aggro end,log=function()end,
        cancel=function(reason)if moves then moves:Cancel(reason)end end}
    moves=C.New{anim=A.New(S.anim.character(),nil),state=State,rig=rig,
        position=function()return Vector3.ZERO end,forward=function()return Vector3.FORWARD end,
        fire=function()shots=shots+1;return true end}
end
local function tick(n,controls)
    for _=1,n do
        moves:Update(.01,controls or {allowed=true});moves:AfterPose();State.Update(.01)
    end
end
new()
assert(State.GetSelection()=='time' and State.CanUseTime() and State.CanSheath())
State.OnEnemyAggro('enemy');State.OnPlayerHit();State.Update(20)
assert(State.GetSelection()=='time' and State.CanUseTime(),'alert and damage notifications cannot auto-equip a sword')
assert(moves:SelectLoadout('sword'));tick(40)
assert(State.GetSelection()=='sword' and not State.CanUseTime() and rig.pose=='back')
State.Update(30)
assert(State.GetSelection()=='sword','quiet timeout cannot choose time automatically')
local swung=false
moves.observe=function(kind,e)if kind=='start' and e.clip=='sword_light_1' then swung=true end end
tick(1,{allowed=true,attackTap=true});tick(130)
assert(swung and State.GetSelection()=='sword' and not moves.clip,'first attack uses existing draw/action path')
assert(moves:SelectLoadout('time') and State.CanUseTime(),'aggro cannot lock time selection or add the old 1s mode cooldown')
assert(rig.pose=='hidden' and not moves.pendingFire and not moves.hitPending)
assert(moves:SelectLoadout('bow'));tick(40)
assert(State.GetSelection()=='bow' and rig.active=='bow' and rig.pose=='back')
tick(1,{allowed=true,attack=true});tick(45,{allowed=true,attack=true})
assert(moves.charge>0 and moves:SelectLoadout('time'))
tick(100);assert(shots==0 and State.GetSelection()=='time','changing from a charged bow discards, never fires')
assert(moves:SelectLoadout('time') and rig.pose=='hidden','same slot is a no-op')
assert(not moves:SelectLoadout('future') and State.GetSelection()=='time')
assert(moves:SelectLoadout('sword'));tick(40)
assert(moves:SelectLoadout('bow') and moves.clip=='weapon_swap_sword_to_bow')
assert(not moves:SelectLoadout('time'),'authored swap transition cannot be bypassed')
tick(50);assert(State.GetSelection()=='bow')
assert(moves:SelectLoadout('sword'));tick(50)
State.Activity(true);assert(moves:Action('light'))
assert(not moves:SelectLoadout('time'),'locked attack window is respected')
tick(10);moves:Cancel('test');State.FinishTransition()
assert(moves:SelectLoadout('time'));moves.invuln=0
assert(moves:ApplyHit{dmg=1,dir=Vector3.RIGHT}.hit)
assert(State.GetSelection()=='time' and not State.CanUseTime(),'hit reaction locks casting, not the selected loadout')
tick(100);assert(State.CanUseTime() and rig.pose=='hidden')
State.SetMounted(true);assert(not State.CanUseTime() and not moves:SelectLoadout('bow'))
State.SetMounted(false);State.SetDead(true);moves.dead=true
assert(not moves:SelectLoadout('sword') and not State.CanUseTime())
print('PASS explicit selection: three slots, aggro, idle, same slot, charge cancel, authored locks, hit/mount/death gates')

-- Real mobile key adapter: rewind cannot be mistaken for Q selection.
KEY_SPACE,KEY_SHIFT,KEY_F,KEY_E,KEY_Q,KEY_R='space','shift','f','e','q','r'
KEY_C,KEY_G,KEY_L,KEY_B,KEY_TAB,KEY_T='c','g','l','b','tab','t'
Input.SetEnabled(true);Input.Clear();Input.Set('rewind',true)
assert(not Input.KeyPress(KEY_Q) and not Input.KeyDown(KEY_Q))
assert(Input.KeyPress(KEY_R) and Input.KeyDown(KEY_R))
Input.Set('rewind',false);Input.Clear()
print('PASS mobile rewind maps to R, never Q')

-- Time users remain in exploration mode when hurt, but still render the real
-- hurt/death overlay. Removing automatic weapon selection must not hide hits.
local f=assert(io.open('scripts/ruins/RuinsScene.lua'));local source=f:read('*a');f:close()
local line
for s in source:gmatch('[^\n]+')do if s:find("Safe('Animation.Apply'",1,true)then line=s;break end end
assert(line)
local applied=0
local env=setmetatable({CombatState={InCombat=function()return false end},
 combatAnim_={Apply=function()applied=applied+1 end},combatMoves_={clip='hit_light',dead=false},
 animPreview_={index=0},Safe=function(_,fn,obj)fn(obj)end},{__index=_G})
local frame=assert(load(line,'Scene time hit reaction','t',env))
frame();assert(applied==1)
env.combatMoves_.clip=nil;frame();assert(applied==1)
print('PASS Scene preserves time-slot hit reaction without auto-equipping a weapon')
