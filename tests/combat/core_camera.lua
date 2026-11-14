local S=dofile('tests/combat/core_support.lua')
local Camera=require('combat.CombatCamera')
local C=require('combat.CombatMoves')
local A=require('combat.CombatAnim')
local State=require('combat.CombatState')
local Particles=require('combat.enemies.EnemyParticles')
local function near(a,b,tolerance) assert(math.abs(a-b)<(tolerance or 1e-6),a..' ~= '..b) end
near(Camera.Spring(0),1);near(Camera.Spring(.18),0)
local low=0
for i=0,650 do low=math.min(low,Camera.Spring(i/1000)) end
assert(low<-.028 and low>-.032,'second order spring 3% overshoot')
local m={charge=0}
local function sample(fps)
    local cam=Camera.New();cam:Slide(Vector3.FORWARD)
    for _=1,fps/10 do cam:Update(1/fps,m,true,true) end
    return cam.output
end
local a,b=sample(30),sample(60)
near(a.focus.z,b.focus.z);near(a.distance,b.distance);near(a.fov,b.fov)
local cam=Camera.New();cam:Slide(Vector3.RIGHT)
local out=cam:Update(0,m,true,true)
near(out.focus.x,0);near(out.focus.y,0);near(out.focus.z,0)
out=cam:Update(.05,m,true,true);near(out.fov,.8*Camera.Pulse(.05,.08,.22))
out=cam:Update(.03,m,true,true);near(out.distance,.12*Camera.Pulse(.08,.10,.22))
cam:Follow();out=cam:Update(.06,m,true,true);near(out.distance,-.10);near(out.fov,0)
out=cam:Update(.9,m,true,true);near(out.distance,0);near(out.focus:Length(),0);near(out.fov,0)
cam:Slide(Vector3.FORWARD);out=cam:Update(.03,m,false,true)
near(out.distance,0);near(out.focus:Length(),0);near(out.fov,0)
cam:Cancel();out=cam:Update(.01,m,true,true);near(out.focus:Length(),0)
local function bow(fps)
    local c=Camera.New();local move={clip='bow_hold',charge=1}
    for _=1,fps/2 do c:Update(1/fps,move,true,true) end
    near(c.output.fov,-12);near(c.output.look,.60);near(c.output.cross,1)
    move.clip=nil
    for _=1,fps/10 do c:Update(1/fps,move,true,true) end
    near(c.output.fov,0);near(c.output.look,1);return c
end
bow(30);bow(60)
cam=Camera.New();m={clip='sword_light_1',whooshTime=.07}
out=cam:Update(0,m,true,true);near(out.distance,.08)
m.whooshTime=.10;out=cam:Update(0,m,true,true);near(out.distance,0)
cam:Land();out=cam:Update(.02,m,true,true);near(out.focus.y,-.03)
cam=Camera.New();cam:Full();out=cam:Update(.02,{clip='bow_hold',charge=1},true,true);assert(out.focus.y>0)
out=cam:Update(.08,{clip='bow_hold',charge=1},true,true);near(out.focus.y,0)
out=cam:Update(.5,{clip='bow_hold',charge=1},true,true);near(out.focus.y,0)
-- Real authored motion is sent to exactly one terrain/wall clip port per frame.
local called,total=0,0
local rig={SetActive=function()end,SetPose=function()end,GetStats=function()return {attack=10,speed=1,reach=1}end}
State.Configure{rig=rig};State.Enter();State.FinishTransition();State.Activity(true)
local moves=C.New{anim=A.New(S.anim.character(),nil),state=State,rig=rig,camera=Camera.New(),
 position=function()return Vector3.ZERO end,forward=function()return Vector3.FORWARD end,
 attackMotion=function(v)called=called+1;total=total+v:Length();return Vector3.ZERO end}
moves:Update(.01,{allowed=true,attackTap=true})
for i=1,45 do moves:Update(.01,{allowed=true});near(moves.motion:Length(),0) end
assert(called>0 and total>.4 and total<.8,'W4 .45-.7m lunge passes footprint clip, not direct teleport')
-- Existing shared pool, exactly four cubes over .54m; never creates air dust.
local pool=Particles.Acquire(nil,nil,{})
local owner,other={},{}
pool:Emit(other,{pos=Vector3.ZERO,dir=Vector3.FORWARD,kind='death'})
local preserved=pool:CountOwner(other)
local n=C.EmitDustStreak(pool,owner,Vector3.ZERO,Vector3.FORWARD,function()return 0,1 end)
assert(n==4 and pool:CountOwner(owner)==4 and pool:CountOwner(other)==preserved)
local min,max=0,0
for _,slot in ipairs(pool.slots) do if slot.active and slot.owner==owner then min=math.min(min,slot.z);max=math.max(max,slot.z) end end
near(max-min,.54)
assert(C.EmitDustStreak(pool,owner,Vector3.ZERO,Vector3.FORWARD,function()return nil end)==0)
pool:UpdateOwner(owner,.21);assert(pool:CountOwner(owner)==0 and pool:CountOwner(other)==preserved)
pool:Release(owner)
-- Execute actual F7 camera method using the same library port, preserve yaw and
-- follow state and route final camera position through obstruction correction.
local f=assert(io.open('scripts/ruins/NomiController.lua'));local source=f:read('*a');f:close()
local code=assert(source:match('(function N:UpdateCombatPreview.-)\nend'))..'\nend'
local N={};assert(load(code,'F7 closeup port','t',setmetatable({N=N},{__index=_G})))()
local n=setmetatable({yaw=12,camYaw=34,camPitch=10,node={worldPosition=Vector3(1,2,3)},camTarget={position=Vector3(4,5,6)},
 cam={SetModeConfig=function(_,id,config)assert(id=='combatPreview' and config.distance==2.6 and config.offset.y==1.2)end,
 SetTransitionSpeed=function()end,SetMode=function()end,
 Update=function(_,dt,target,yaw,pitch)near(yaw,12+180+15);near(pitch,6);near(target.position.x,1)end},
 ApplyCombatOffset=function(_,offset)near(offset:Length(),0)end},{__index=N})
n:UpdateCombatPreview(.016,1,15);near(n.camYaw,34);near(n.camPitch,10);near(n.camTarget.position.x,4)
print('PASS core_camera: spring/overshoot/FPS/F3/no drift, bow reset/full-once, real lunge clipping, shared ground streak, F7 orbit preservation')
-- Accepted-only camera impulses; cancellation changes neither health nor input.
State.Configure{rig=rig};State.Enter();State.FinishTransition();State.Activity(true)
local safe=false
local cc=Camera.New()
local controller=C.New{anim=A.New(S.anim.character(),nil),state=State,rig=rig,camera=cc,
 position=function()return Vector3.ZERO end,forward=function()return Vector3.FORWARD end,
 slideStart=function()return safe end}
assert(not controller:Action('dodge',Vector3.RIGHT) and not cc.slideAt)
safe=true;assert(controller:Action('dodge',Vector3.RIGHT));assert(cc.slideDir.x==1)
controller:Update(.01,{allowed=true,attackTap=true})
controller:Update(.21,{allowed=true})
assert(controller.clip=='sword_light_1' and cc.followAt and not cc.slideAt)
-- Actual Scene rig-event consumer drains once; new Rig owns arrival flash.
local file=assert(io.open('scripts/ruins/RuinsScene.lua'));local scene=file:read('*a');file:close()
local code=assert(scene:match('(        if combatRig_%.PopEvents then.-)\n    end\nend'))
local sounds,flashes={},0
local events={'materialize','materialized','blade_draw','blade_sheath'}
local r={PopEvents=function()local e=events;events={};return e end,ArrivalFlash=function()end,Flash=function()flashes=flashes+1 end}
local env=setmetatable({Safe=function(_,fn,...)return pcall(fn,...)end,CombatState={PerfCall=function(_,fn,...)return fn(...)end},combatRig_=r,CombatAudio={Play=function(name) sounds[#sounds+1]=name end},nomi_={Position=function()return Vector3.ZERO end}},{__index=_G})
local consume=assert(load(code,'actual Rig lifecycle consumer','t',env))
consume();consume();assert(#sounds==3 and flashes==0,'no dual animation/arrival flash and no duplicate event sound')
assert(scene:find("Safe('Animation.Params',combatAnim_.SetParam,combatAnim_,'aimPitch',pitch)",1,true))
assert(scene:find('combatRig_:SetBowDraw(p)',1,true))
local f=assert(io.open('scripts/ruins/RuinsHUD.lua'));local hud=f:read('*a');f:close()
assert(hud:find('Draw.Rect(vg,x-1,y-1,2,2,c)',1,true),'reticle centre remains fixed while arms contract')
print('PASS accepted-only slide/follow impulse, Rig arrival-only sound/flash, aimPitch/bow draw ports, reticle centre unchanged')

local branch=assert(scene:match('(        if previewAllowed and Press%(KEY_P%) then.-)\n        if previewAllowed and clip.id'))
local penv={params={},previewAllowed=true,KEY_P=80,Press=function(key)return key==80 end}
local toggle=assert(load(branch,'actual F7 P toggle','t',penv))
toggle();assert(penv.params.legacyPose==1 and penv.changed)
toggle();assert(penv.params.legacyPose==0)
penv.previewAllowed=false;penv.changed=false;toggle();assert(penv.params.legacyPose==0 and not penv.changed)
local preview=A.New(S.anim.character(),nil)
C.SeekPreview(preview,'sword_light_1',.12,.12,{legacyPose=1})
assert(preview.tracks[1].params.legacyPose==1)
C.SeekPreview(preview,'sword_light_1',.12,.12,{legacyPose=0})
assert(preview.tracks[1].params.legacyPose==0)
assert(scene:find("Safe('Animation.Params',combatAnim_.SetParam,combatAnim_,'p',p)",1,true))
assert(scene:find('if not sample and not legacy then',1,true),'legacy preview must not report stale IK sample')
print('PASS F7 P toggles/reseeks same frame, disabled outside preview, continuous bow p and legacy diagnostics isolation')
